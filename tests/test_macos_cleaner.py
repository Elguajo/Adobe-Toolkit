#!/usr/bin/env python3
"""Fixture tests for the conservative macOS UI-cleanup helpers."""

from __future__ import annotations

import os
import sqlite3
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / "macos" / "clean" / "lib"
LS_HELPER = LIB / "launch_services_records.py"
LP_HELPER = LIB / "launchpad_reconcile.py"
CLEANER = LIB / "adobe-cleaner-macos.sh"
MANIFEST = ROOT / "shared" / "cleaner-manifest.json"
SCHEMA = ROOT / "shared" / "cleaner-manifest.schema.json"
MANIFEST_VALIDATOR = ROOT / "shared" / "validate_cleaner_manifest.py"


def run(command: list[str], **kwargs: object) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, text=True, capture_output=True, check=False, **kwargs)  # type: ignore[arg-type]


def make_db(path: Path, valid_schema: bool = True) -> None:
    with sqlite3.connect(path) as conn:
        conn.executescript(
            """
            CREATE TABLE items (rowid INTEGER PRIMARY KEY, parent_id INTEGER NOT NULL DEFAULT 0, ordering INTEGER);
            CREATE TABLE apps (item_id INTEGER PRIMARY KEY, title VARCHAR, bundleid VARCHAR);
            """
        )
        if valid_schema:
            conn.execute("CREATE TABLE image_cache (item_id INTEGER, image_data BLOB)")


def add_app(db: Path, item_id: int, title: str, bundle_id: str) -> None:
    with sqlite3.connect(db) as conn:
        conn.execute("INSERT INTO items(rowid) VALUES (?)", (item_id,))
        conn.execute("INSERT INTO apps(item_id, title, bundleid) VALUES (?, ?, ?)", (item_id, title, bundle_id))
        conn.execute("INSERT INTO image_cache(item_id) VALUES (?)", (item_id,))


class LaunchServicesTests(unittest.TestCase):
    def test_manifest_validation_rejects_unsafe_root_target(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            manifest = Path(directory) / "manifest.json"
            data = MANIFEST.read_text(encoding="utf-8").replace('"/Applications/Adobe*"', '"/"')
            manifest.write_text(data, encoding="utf-8")
            result = run(["python3", str(MANIFEST_VALIDATOR), str(manifest), str(SCHEMA)])
            self.assertEqual(result.returncode, 3)
            self.assertIn("unsafe root-level target", result.stderr)

    def test_current_manifest_is_valid(self) -> None:
        result = run(["python3", str(MANIFEST_VALIDATOR), str(MANIFEST), str(SCHEMA)])
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_dry_run_path_removal_does_not_delete_or_write_logs(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home = root / "home"
            target = home / "Library/Application Support/Adobe"
            target.mkdir(parents=True)
            (target / "prefs.txt").write_text("fixture", encoding="utf-8")
            manifest = root / "manifest.json"
            manifest.write_text(
                '{"version":1,"macos":{"kill_patterns":[],"paths_remove":["~/Library/Application Support/Adobe"]},'
                '"windows":{"processes":[],"services":[],"paths_remove":[]}}',
                encoding="utf-8",
            )
            command = (
                f'source "{CLEANER}"; CLEANER_DIR="{ROOT / "macos" / "clean"}"; '
                f'MANIFEST="{manifest}"; DRY_RUN=1; UI_DIAGNOSTIC_ONLY=""; '
                'adobe_cleaner_init_results; adobe_cleaner_remove_paths'
            )
            result = run(["bash", "-c", command], env={**os.environ, "HOME": str(home)})
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue((target / "prefs.txt").exists())
            self.assertFalse((home / "Library/Logs/AdobeEnvironmentToolkit-cleaner.log").exists())

    def test_failed_path_removal_is_reported_as_partial_success(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home = root / "home"
            target = home / "Library/Application Support/Adobe"
            target.mkdir(parents=True)
            manifest = root / "manifest.json"
            manifest.write_text(
                '{"version":1,"macos":{"kill_patterns":[],"paths_remove":["~/Library/Application Support/Adobe"]},'
                '"windows":{"processes":[],"services":[],"paths_remove":[]}}',
                encoding="utf-8",
            )
            command = (
                f'source "{CLEANER}"; CLEANER_DIR="{ROOT / "macos" / "clean"}"; '
                f'MANIFEST="{manifest}"; DRY_RUN=0; UI_DIAGNOSTIC_ONLY=""; '
                'rm() { return 1; }; adobe_cleaner_init_results; adobe_cleaner_remove_paths; adobe_cleaner_print_report'
            )
            result = run(["bash", "-c", command], env={**os.environ, "HOME": str(home)})
            self.assertEqual(result.returncode, 1)
            self.assertIn("Cleanup completed with warnings", result.stdout)
            self.assertIn("FILESYSTEM: " + str(target), result.stdout)
            self.assertTrue(target.exists())
    def test_missing_adobe_any_location_and_live_apps_are_classified_safely(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            live_adobe = root / "Adobe Live.app"
            live_other = root / "Other.app"
            live_adobe.mkdir()
            live_other.mkdir()
            dump = f"""----
bundle id: com.Adobe.Photoshop
path: /Applications/Adobe Photoshop.app
error: Bundle node not found on disk
----
bundle id: com.adobe.archive
path: /Volumes/External/Archive/Adobe Archive.app
error: Bundle node not found on disk
----
bundle id: com.adobe.live
path: {live_adobe}
----
bundle id: org.example.live
path: {live_other}
----
bundle id: com.adobe.archive
path: /Volumes/External/Archive/Adobe Archive.app
error: Bundle node not found on disk
"""
            result = run(["python3", str(LS_HELPER)], input=dump)
            self.assertEqual(result.returncode, 0, result.stderr)
            lines = result.stdout.splitlines()
            stale = [line for line in lines if line.startswith("STALE\t")]
            self.assertEqual(len(stale), 2)
            self.assertTrue(any("/Applications/Adobe Photoshop.app" in line for line in stale))
            self.assertTrue(any("/Volumes/External/Archive/Adobe Archive.app" in line for line in stale))
            self.assertIn("LIVE\tcom.adobe.live", lines)
            self.assertIn("LIVE\torg.example.live", lines)

    def test_missing_unrelated_or_non_application_registration_is_preserved(self) -> None:
        dump = """----
bundle id: org.example.missing
path: /Applications/Other.app
error: Bundle node not found on disk
----
bundle id: com.adobe.document
path: /tmp/missing.pdf
error: Bundle node not found on disk
"""
        result = run(["python3", str(LS_HELPER)], input=dump)
        self.assertEqual(result.stdout, "")


class LaunchpadTests(unittest.TestCase):
    def test_plan_removes_orphan_adobe_and_preserves_unrelated_without_provenance(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            db = Path(directory) / "db"
            make_db(db)
            add_app(db, 1, "Creative Cloud", "com.adobe.acc.AdobeCreativeCloud")
            add_app(db, 2, "Other Missing App", "org.example.missing")
            result = run(["python3", str(LP_HELPER), "plan", str(db), "--provenance-stdin"], input="")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("REMOVE\t1\tCreative Cloud\tcom.adobe.acc.AdobeCreativeCloud", result.stdout)
            self.assertIn("PRESERVE\t2\tOther Missing App\torg.example.missing", result.stdout)

    def test_provenance_allows_only_the_recorded_non_adobe_bundle(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            db = Path(directory) / "db"
            make_db(db)
            add_app(db, 3, "Web Gallery", "com.apple.ScriptEditor.id.Web-Gallery")
            add_app(db, 4, "Other Missing", "org.example.missing")
            provenance = "com.apple.ScriptEditor.id.Web-Gallery\tWeb Gallery\t/Applications/Adobe Tools/Web Gallery.app\n"
            result = run(["python3", str(LP_HELPER), "plan", str(db), "--provenance-stdin"], input=provenance)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("REMOVE\t3\tWeb Gallery\tcom.apple.ScriptEditor.id.Web-Gallery", result.stdout)
            self.assertIn("PRESERVE\t4\tOther Missing\torg.example.missing", result.stdout)

    def test_live_adobe_registration_is_preserved(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            db = Path(directory) / "db"
            make_db(db)
            add_app(db, 5, "Creative Cloud", "com.adobe.acc.AdobeCreativeCloud")
            result = run(
                ["python3", str(LP_HELPER), "plan", str(db), "--live-id", "COM.ADOBE.ACC.ADOBECREATIVEcloud"],
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, "")

    def test_apply_deletes_only_confirmed_individual_rows_in_one_database(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            db = Path(directory) / "db"
            make_db(db)
            add_app(db, 6, "Creative Cloud", "com.adobe.acc.AdobeCreativeCloud")
            add_app(db, 7, "Unrelated", "org.example.live")
            result = run(["python3", str(LP_HELPER), "apply", str(db), "--id", "6"])
            self.assertEqual(result.returncode, 0, result.stderr)
            with sqlite3.connect(db) as conn:
                self.assertEqual(conn.execute("SELECT count(*) FROM items WHERE rowid=6").fetchone()[0], 0)
                self.assertEqual(conn.execute("SELECT count(*) FROM apps WHERE item_id=6").fetchone()[0], 0)
                self.assertEqual(conn.execute("SELECT count(*) FROM image_cache WHERE item_id=6").fetchone()[0], 0)
                self.assertEqual(conn.execute("SELECT count(*) FROM apps WHERE item_id=7").fetchone()[0], 1)

    def test_unexpected_schema_is_a_safe_skip(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            db = Path(directory) / "db"
            make_db(db, valid_schema=False)
            result = run(["python3", str(LP_HELPER), "plan", str(db)])
            self.assertEqual(result.returncode, 3)
            self.assertIn("SCHEMA_SKIP", result.stdout)

    def test_dry_run_and_missing_sqlite_do_not_mutate_database(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            db = root / "db"
            make_db(db)
            add_app(db, 8, "Creative Cloud", "com.adobe.acc.AdobeCreativeCloud")
            before = db.read_bytes()
            base = f'source "{CLEANER}"; CLEANER_DIR="{ROOT / "macos" / "clean"}"; LAUNCHPAD_DB="{db}"; '
            dry_run = run(
                ["bash", "-c", base + 'DRY_RUN=1; UI_DIAGNOSTIC_ONLY=""; LAUNCH_SERVICES_AVAILABLE=1; LAUNCH_SERVICES_LIVE_IDS=(); CLEANUP_PROVENANCE=""; ADOBE_UI_CHANGED=0; adobe_cleaner_reconcile_launchpad; adobe_cleaner_restart_dock_if_needed'],
                env={**os.environ, "HOME": str(root)},
            )
            self.assertEqual(dry_run.returncode, 0, dry_run.stderr)
            self.assertIn("would back up the database", dry_run.stdout)
            self.assertIn("Dock would be restarted", dry_run.stdout)
            self.assertEqual(db.read_bytes(), before)
            missing_sqlite = run(
                ["bash", "-c", base + 'DRY_RUN=0; UI_DIAGNOSTIC_ONLY=""; LAUNCH_SERVICES_AVAILABLE=1; LAUNCH_SERVICES_LIVE_IDS=(); CLEANUP_PROVENANCE=""; SQLITE3_BIN=/no/sqlite3; adobe_cleaner_reconcile_launchpad'],
                env={**os.environ, "HOME": str(root)},
            )
            self.assertEqual(missing_sqlite.returncode, 0, missing_sqlite.stderr)
            self.assertIn("sqlite3 is unavailable", missing_sqlite.stdout)
            self.assertEqual(db.read_bytes(), before)

    def test_shell_reconciliation_backs_up_before_applying_fixture_transaction(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            db = root / "db"
            make_db(db)
            add_app(db, 9, "Creative Cloud", "com.adobe.acc.AdobeCreativeCloud")
            base = f'source "{CLEANER}"; CLEANER_DIR="{ROOT / "macos" / "clean"}"; LAUNCHPAD_DB="{db}"; '
            result = run(
                ["bash", "-c", base + 'DRY_RUN=0; UI_DIAGNOSTIC_ONLY=""; LAUNCH_SERVICES_AVAILABLE=1; LAUNCH_SERVICES_LIVE_IDS=(); CLEANUP_PROVENANCE=""; ADOBE_UI_CHANGED=0; adobe_cleaner_reconcile_launchpad'],
                env={**os.environ, "HOME": str(root)},
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("Launchpad database transaction completed.", result.stdout)
            self.assertEqual(len(list(root.glob("db.AdobeEnvironmentToolkit-*.bak"))), 1)
            with sqlite3.connect(db) as conn:
                self.assertEqual(conn.execute("SELECT count(*) FROM apps WHERE item_id=9").fetchone()[0], 0)


if __name__ == "__main__":
    unittest.main()
