#!/usr/bin/env python3
"""Fixture tests for macOS backup/restore validation and headless failures."""

from __future__ import annotations

import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BACKUPPER = ROOT / "macos" / "AdobeBackuper.command"


def run(command: list[str], **kwargs: object) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, text=True, capture_output=True, check=False, **kwargs)  # type: ignore[arg-type]


def manifest(root: Path, row: str, metadata: str = "") -> None:
    (root / "manifest.tsv").write_text(
        "backup_path\trestore_parent\tadmin\n" + row + "\n", encoding="utf-8"
    )
    if metadata:
        (root / "meta.tsv").write_text(metadata, encoding="utf-8")


class BackupRestoreTests(unittest.TestCase):
    def source_function(self, home: Path, command: str) -> subprocess.CompletedProcess[str]:
        return run(
            ["bash", "-c", f'source "{BACKUPPER}"; {command}'],
            env={**os.environ, "HOME": str(home), "ADOBE_BACKUP_LIBRARY_ONLY": "true"},
        )

    def test_traversal_manifest_is_rejected_before_restore(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home = root / "home"
            home.mkdir()
            manifest(root, "User_Library/../../outside\t" + str(home / "Library") + "\tfalse")
            result = self.source_function(home, f'validate_restore_manifest "{root}"')
            self.assertEqual(result.returncode, 3)
            self.assertIn("Refusing manifest backup path", result.stderr)

    def test_disallowed_restore_target_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home = root / "home"
            home.mkdir()
            manifest(root, "User_Library/Preferences/com.adobe.test.plist\t/tmp\tfalse")
            result = self.source_function(home, f'validate_restore_manifest "{root}"')
            self.assertEqual(result.returncode, 3)
            self.assertIn("Refusing manifest restore target", result.stderr)

    def test_allowed_user_and_admin_destinations_are_accepted(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home = root / "home"
            home.mkdir()
            user_backup = root / "user"
            user_backup.mkdir()
            manifest(
                user_backup,
                "User_Library/Preferences/com.adobe.test.plist\t"
                + str(home / "Library/Preferences")
                + "\tfalse",
                "backup_format_version\t1\nplatform\tmacos\n",
            )
            result = self.source_function(home, f'validate_restore_manifest "{user_backup}"')
            self.assertEqual(result.returncode, 0, result.stderr)

            admin_backup = root / "admin"
            admin_backup.mkdir()
            manifest(admin_backup, "System_Apps_Data/Applications/Adobe Test.app\t/Applications\ttrue")
            result = self.source_function(home, f'validate_restore_manifest "{admin_backup}"')
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_unknown_backup_format_version_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home = root / "home"
            home.mkdir()
            manifest(root, "User_Library/Preferences/com.adobe.test.plist\t" + str(home / "Library") + "\tfalse", "backup_format_version\t2\n")
            result = self.source_function(home, f'validate_backup_metadata "{root}"')
            self.assertEqual(result.returncode, 3)

    def test_missing_restore_source_returns_invalid_structure_code(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home = root / "home"
            home.mkdir()
            result = run(
                ["bash", str(BACKUPPER), "--restore-headless", str(root / "missing")],
                env={**os.environ, "HOME": str(home)},
            )
            self.assertEqual(result.returncode, 3)
            self.assertIn("Restore source is not a directory", result.stderr)

    def test_headless_backup_returns_nonzero_when_copy_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home = root / "home"
            source = home / "Library/Application Support/Adobe"
            source.mkdir(parents=True)
            (source / "prefs.txt").write_text("fixture", encoding="utf-8")
            fake_bin = root / "bin"
            fake_bin.mkdir()
            fake_rsync = fake_bin / "rsync"
            fake_rsync.write_text("#!/bin/sh\nexit 7\n", encoding="utf-8")
            fake_rsync.chmod(0o755)
            selection_file = root / "selection.txt"
            selection_file.write_text(str(source) + "\n", encoding="utf-8")
            result = run(
                ["bash", str(BACKUPPER), "--backup-headless", str(selection_file)],
                env={**os.environ, "HOME": str(home), "PATH": f"{fake_bin}:{os.environ['PATH']}"},
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Backup finished with errors", result.stderr)

    def test_backup_excludes_regenerable_adobe_modules_and_recovery_data(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home = root / "home"
            adobe = home / "Library/Application Support/Adobe"
            (adobe / "Adobe Photoshop 2026/Settings").mkdir(parents=True)
            (adobe / "Adobe Photoshop 2026/Settings/prefs.txt").write_text("keep", encoding="utf-8")
            model = adobe / "Adobe Photoshop 2026/AddonModules/sensei_model_cache/model.data"
            model.parent.mkdir(parents=True)
            model.write_text("regenerate", encoding="utf-8")
            recovery = adobe / "Adobe Photoshop 2026/AutoRecover/recovery.psb"
            recovery.parent.mkdir(parents=True)
            recovery.write_text("temporary", encoding="utf-8")

            result = run(
                ["bash", str(BACKUPPER), "--backup-headless"],
                env={**os.environ, "HOME": str(home)},
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            backup = next((home / "Desktop/Backups").glob("Adobe_Backup_*"))
            copied = backup / "User_Library/Application Support/Adobe/Adobe Photoshop 2026"
            self.assertEqual((copied / "Settings/prefs.txt").read_text(encoding="utf-8"), "keep")
            self.assertFalse((copied / "AddonModules").exists())
            self.assertFalse((copied / "AutoRecover").exists())

    def test_headless_restore_returns_nonzero_when_copy_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home = root / "home"
            home.mkdir()
            backup = root / "backup"
            item = backup / "User_Library/Preferences/com.adobe.test.plist"
            item.parent.mkdir(parents=True)
            item.write_text("fixture", encoding="utf-8")
            manifest(backup, "User_Library/Preferences/com.adobe.test.plist\t" + str(home / "Library/Preferences") + "\tfalse")
            fake_bin = root / "bin"
            fake_bin.mkdir()
            fake_rsync = fake_bin / "rsync"
            fake_rsync.write_text("#!/bin/sh\nexit 7\n", encoding="utf-8")
            fake_rsync.chmod(0o755)
            result = run(
                ["bash", str(BACKUPPER), "--restore-headless", str(backup)],
                env={**os.environ, "HOME": str(home), "PATH": f"{fake_bin}:{os.environ['PATH']}"},
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("rsync failed", result.stderr)

    def test_headless_privileged_restore_returns_nonzero_when_admin_command_fails(self) -> None:
        """Protect the rsync/AppleScript failure shown by the original restore output."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home = root / "home"
            home.mkdir()
            backup = root / "backup"
            item = backup / "System_Apps_Data/Applications/Adobe Test.app"
            item.mkdir(parents=True)
            manifest(backup, "System_Apps_Data/Applications/Adobe Test.app\t/Applications\ttrue")
            fake_bin = root / "bin"
            fake_bin.mkdir()
            fake_osascript = fake_bin / "osascript"
            fake_osascript.write_text(
                "#!/bin/sh\necho 'rsync: Operation not permitted' >&2\nexit 23\n",
                encoding="utf-8",
            )
            fake_osascript.chmod(0o755)
            result = run(
                ["bash", str(BACKUPPER), "--restore-headless", str(backup)],
                env={**os.environ, "HOME": str(home), "PATH": f"{fake_bin}:{os.environ['PATH']}"},
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("privileged restore command failed", result.stderr)
            self.assertNotIn("Restore Complete", result.stdout)

    def test_privileged_restore_stages_backup_before_calling_admin_helper(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home = root / "home"
            home.mkdir()
            backup = root / "backup"
            item = backup / "System_Apps_Data/Applications/Adobe Test.app"
            item.mkdir(parents=True)
            (item / "plugin.txt").write_text("fixture", encoding="utf-8")
            manifest(backup, "System_Apps_Data/Applications/Adobe Test.app\t/Applications\ttrue")
            fake_bin = root / "bin"
            fake_bin.mkdir()
            command_log = root / "admin-command.txt"
            fake_osascript = fake_bin / "osascript"
            fake_osascript.write_text(
                "#!/bin/sh\nprintf '%s\\n' \"$2\" > \"$ADOBE_TEST_COMMAND_LOG\"\nexit 0\n",
                encoding="utf-8",
            )
            fake_osascript.chmod(0o755)

            result = run(
                ["bash", str(BACKUPPER), "--restore-headless", str(backup)],
                env={
                    **os.environ,
                    "HOME": str(home),
                    "PATH": f"{fake_bin}:{os.environ['PATH']}",
                    "ADOBE_TEST_COMMAND_LOG": str(command_log),
                },
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            command = command_log.read_text(encoding="utf-8")
            self.assertNotIn(str(backup), command)
            match = re.search(r"'(/private/tmp/adobe-restore\.[^']+)'", command)
            self.assertIsNotNone(match, command)
            self.assertFalse(Path(match.group(1)).exists())

    def test_legacy_privileged_restore_stages_desktop_style_backup(self) -> None:
        """Legacy backups have no manifest, matching the original failed restore."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home = root / "home"
            home.mkdir()
            backup = root / "Adobe_Backup_legacy"
            item = backup / "System_Apps_Data/Applications/Adobe Test.app"
            item.mkdir(parents=True)
            (item / "plugin.txt").write_text("fixture", encoding="utf-8")
            fake_bin = root / "bin"
            fake_bin.mkdir()
            command_log = root / "admin-command.txt"
            fake_osascript = fake_bin / "osascript"
            fake_osascript.write_text(
                "#!/bin/sh\nprintf '%s\\n' \"$2\" > \"$ADOBE_TEST_COMMAND_LOG\"\nexit 0\n",
                encoding="utf-8",
            )
            fake_osascript.chmod(0o755)

            result = run(
                ["bash", str(BACKUPPER), "--restore-headless", str(backup)],
                env={
                    **os.environ,
                    "HOME": str(home),
                    "PATH": f"{fake_bin}:{os.environ['PATH']}",
                    "ADOBE_TEST_COMMAND_LOG": str(command_log),
                },
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            command = command_log.read_text(encoding="utf-8")
            self.assertNotIn(str(backup), command)
            self.assertIn("/private/tmp/adobe-restore.", command)

    def test_selection_file_filters_backup_sources(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home = root / "home"
            selected = home / "Library/Application Support/Adobe"
            selected.mkdir(parents=True)
            (selected / "prefs.txt").write_text("fixture", encoding="utf-8")
            selection_file = root / "selection.txt"
            selection_file.write_text("/not/a/selected/source\n", encoding="utf-8")
            result = run(
                ["bash", str(BACKUPPER), "--backup-headless", str(selection_file)],
                env={**os.environ, "HOME": str(home)},
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            backup = next((home / "Desktop/Backups").glob("Adobe_Backup_*/manifest.tsv"))
            self.assertEqual(backup.read_text(encoding="utf-8"), "backup_path\trestore_parent\tadmin\n")
            metadata = backup.with_name("meta.tsv").read_text(encoding="utf-8")
            self.assertIn("backup_format_version\t1\n", metadata)
            self.assertIn("platform\tmacos\n", metadata)

    def test_manifest_path_never_escapes_backup_root(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home = root / "home"
            home.mkdir()
            result = self.source_function(
                home,
                f'CURRENT_BACKUP_FOLDER="{root}/backup"; manifest_path "{root}/outside"',
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("outside the backup root", result.stderr)


if __name__ == "__main__":
    unittest.main()
