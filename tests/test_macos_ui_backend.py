"""v1 end-to-end tests with temporary HOME and fake managed/system resources only."""
import json
import os
from pathlib import Path
import shutil
import signal
import sqlite3
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
STAGING = ROOT / 'gui/adobe-toolkit/macos/tools/stage_backend.py'
RESOURCE = ROOT / 'gui/adobe-toolkit/macos/Sources/ToolkitCore/Resources/Backend'


class BackendTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name).resolve()
        self.root = self.base / 'managed'
        shutil.copytree(RESOURCE, self.root, ignore=shutil.ignore_patterns('__pycache__'))
        shutil.copyfile(ROOT / 'macos/ui-json/adobe-toolkit-backend-v1',
                        self.root / 'macos/ui-json/adobe-toolkit-backend-v1')
        self.home = self.base / 'home'
        self.home.mkdir()
        self.applications = self.base / 'Applications'
        self.applications.mkdir()
        self.env = {**os.environ, 'HOME': str(self.home), 'PYTHONDONTWRITEBYTECODE': '1'}
        legacy = self.root / 'macos/AdobeBackuper.command'
        legacy.write_text(legacy.read_text().replace('/Applications', str(self.applications)))
        self.pgrep = self.fake('pgrep', 'exit 1')
        self.lsregister = self.fake('lsregister', "printf '%s\\n' 'bundle id: com.adobe.fixture' 'path: /missing/Adobe Fixture.app'")
        self.code = self.root / 'macos/ui-json/backend.py'
        self.code.write_text(self.code.read_text().replace("Path('/usr/bin/pgrep')", f'Path({str(self.pgrep)!r})')
                             .replace("Path('/Applications')", f'Path({str(self.applications)!r})')
                             .replace("Path('/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister')", f'Path({str(self.lsregister)!r})'))
        data = json.loads((self.root / 'shared/cleaner-manifest.json').read_text())
        data['macos']['paths_remove'] = [str(self.home / 'Library/Application Support/Adobe'), str(self.base / 'missing*')]
        data['macos']['kill_patterns'] = ['fake process']
        (self.root / 'shared/cleaner-manifest.json').write_text(json.dumps(data))
        self.source = self.home / 'Library/Application Support/Adobe'
        self.source.mkdir(parents=True)
        (self.source / 'settings.txt').write_text('fixture')
        (self.source / 'cache').mkdir()
        (self.source / 'cache/noise').write_text('exclude me')
        dock = self.home / 'Library/Application Support/Dock'
        dock.mkdir()
        self.db = dock / 'fixture.db'
        with sqlite3.connect(self.db) as conn:
            conn.executescript('CREATE TABLE items (rowid INTEGER); CREATE TABLE apps (item_id INTEGER,title TEXT,bundleid TEXT); CREATE TABLE image_cache (item_id INTEGER); INSERT INTO apps VALUES(1,"Fixture","com.adobe.fixture");')

    def fake(self, name, body):
        path = self.base / name
        path.write_text('#!/bin/bash\n' + body + '\n')
        path.chmod(0o700)
        return path

    def command(self, mode, *args, entry=None):
        return ['/bin/bash', str(entry or self.root / 'adobe-toolkit-backend-v1'), '--ui-json', mode, *map(str, args)]

    def invoke(self, mode, *args, status='success', entry=None):
        result = subprocess.run(self.command(mode, *args, entry=entry), env=self.env, cwd=self.base,
                                capture_output=True, text=True, timeout=10)
        try: envelope = json.loads(result.stdout)
        except ValueError: self.fail(f'Not one JSON object: {result.stdout!r}; {result.stderr}')
        self.assertEqual(envelope['status'], status, result.stderr + result.stdout)
        self.assertEqual(envelope['exitCode'], result.returncode)
        self.assertEqual(envelope['schemaVersion'], 1)
        self.assertEqual(envelope['mutates'], mode in ('backup-create', 'restore-apply'))
        self.assertIsNone(envelope['logPath'])
        self.assertEqual(len({i['id'] for i in envelope['items']}), len(envelope['items']))
        for item in envelope['items']:
            if mode == 'backup-scan':
                self.assertGreaterEqual(item['fileCount'], 0)
                self.assertGreaterEqual(item['bytes'], 0)
                self.assertTrue(item['displayPath'].startswith('/'))
            else:
                self.assertTrue(item['state'])
                self.assertIn('message', item)
        return envelope

    def selection(self):
        scan = self.invoke('backup-scan')
        path = self.base / 'selection'
        path.write_text('\n'.join(i['id'] for i in scan['items']) + '\n')
        path.chmod(0o600)
        return path, scan

    def backup(self):
        selection, _ = self.selection()
        return Path(self.invoke('backup-create', '--selection-file', selection)['summary']['backupPath'])

    def snapshot(self):
        return {str(p.relative_to(self.home)): (p.stat().st_mode, p.stat().st_mtime_ns,
                p.read_bytes() if p.is_file() else None) for p in self.home.rglob('*')}

    def test_capabilities_and_both_optional_cli_dispatches(self):
        expected = {'backup.scan', 'backup.create', 'restore.validate', 'restore.apply', 'cleanup.preview', 'diagnose.run'}
        for entry in (None, self.root / 'macos/AdobeBackuper.command'):
            self.assertEqual(set(self.invoke('capabilities', entry=entry)['summary']['operations']), expected)
        # Cleaner entry is not staged because managed preview never invokes legacy cleaner.
        cleaner = self.root / 'macos/clean/AdobeCleaner.command'
        shutil.copyfile(ROOT / 'macos/clean/AdobeCleaner.command', cleaner)
        self.assertEqual(set(self.invoke('capabilities', entry=cleaner)['summary']['operations']), expected)

    def test_scan_and_create_preserve_format_and_exclusions(self):
        selection, scan = self.selection()
        self.assertEqual(scan['items'][0]['fileCount'], 1)
        self.assertEqual(scan['items'][0]['bytes'], 7)
        self.assertEqual(self.invoke('backup-scan')['items'], scan['items'])
        result = self.invoke('backup-create', '--selection-file', selection)
        backup = Path(result['summary']['backupPath'])
        self.assertEqual((backup / 'User_Library/Application Support/Adobe/settings.txt').read_text(), 'fixture')
        self.assertFalse((backup / 'User_Library/Application Support/Adobe/cache').exists())
        self.assertTrue((backup / 'manifest.tsv').read_text().startswith('backup_path\trestore_parent\tadmin\n'))
        self.assertEqual(backup.stat().st_mode & 0o777, 0o700)
        self.assertTrue(selection.exists())  # host owns/removes selection; backend never unlinks host input

    def test_customizations_use_same_enumerator_and_safe_copy_destination_pairs(self):
        app = self.applications / 'Adobe After Effects Fixture'
        (app / 'Plug-ins/Effects').mkdir(parents=True)
        (app / 'Plug-ins/Effects/stock.plugin').write_text('excluded')
        (app / 'Plug-ins/custom.plugin').write_text('custom')
        (app / 'Scripts/ScriptUI Panels').mkdir(parents=True)
        (app / 'Scripts/ScriptUI Panels/panel.jsx').write_text('panel')
        (app / 'Presets/User/Scripts').mkdir(parents=True)
        (app / 'Presets/User/Scripts/custom.jsx').write_text('script')
        backup = self.backup()
        copied = backup / 'App_Customizations' / app.name
        self.assertTrue((copied / 'Plug-ins/custom.plugin').is_file())
        self.assertFalse((copied / 'Plug-ins/Effects').exists())
        self.invoke('restore-validate', '--source', backup)
        (app / 'Plug-ins/unrelated.plugin').write_text('preserve')
        self.invoke('restore-apply', '--source', backup)
        self.assertEqual((app / 'Plug-ins/unrelated.plugin').read_text(), 'preserve')

    def test_restore_source_with_spaces_unicode_and_shell_metacharacters_is_one_argument(self):
        backup = self.backup()
        strange = self.base / "Bä ckup';$(touch unexpected)"
        backup.rename(strange)
        self.invoke('restore-validate', '--source', strange)
        self.invoke('restore-apply', '--source', strange)
        self.assertFalse((self.base / 'unexpected').exists())

    def test_stale_unknown_duplicate_and_path_selections_fail_before_mutation(self):
        selection, _ = self.selection()
        original = selection.read_text()
        (self.source / 'settings.txt').write_text('changed fixture')
        self.invoke('backup-create', '--selection-file', selection, status='invalid')
        for text in ('f' * 64, original + original, str(self.source)):
            selection.write_text(text)
            self.invoke('backup-create', '--selection-file', selection, status='invalid')
        self.assertFalse((self.home / 'Desktop').exists())

    def test_selection_permissions_and_symlinks_fail_closed(self):
        selection, _ = self.selection()
        selection.chmod(0o644)
        self.invoke('backup-create', '--selection-file', selection, status='invalid')
        selection.chmod(0o600)
        link = self.base / 'selection-link'
        link.symlink_to(selection)
        self.invoke('backup-create', '--selection-file', link, status='invalid')
        self.assertFalse((self.home / 'Desktop').exists())

    def test_safe_copy_restore_preserves_unrelated_files_and_revalidates_apply(self):
        backup = self.backup()
        (self.source / 'settings.txt').write_text('new content')
        (self.source / 'unrelated.txt').write_text('preserve')
        self.invoke('restore-validate', '--source', backup)
        self.invoke('restore-apply', '--source', backup)
        self.assertEqual((self.source / 'settings.txt').read_text(), 'fixture')
        self.assertEqual((self.source / 'unrelated.txt').read_text(), 'preserve')
        (backup / 'meta.tsv').write_text('backup_format_version\t2\n')
        before = self.snapshot()
        self.invoke('restore-apply', '--source', backup, status='invalid')
        self.assertEqual(self.snapshot(), before)

    def test_safe_copy_replaces_different_contents_with_identical_size_and_mtime(self):
        backup = self.backup()
        saved = backup / 'User_Library/Application Support/Adobe/settings.txt'
        destination = self.source / 'settings.txt'
        destination.write_text('changed')
        info = saved.stat()
        os.utime(destination, ns=(info.st_atime_ns, info.st_mtime_ns))
        self.assertEqual(destination.stat().st_size, info.st_size)
        self.assertEqual(destination.stat().st_mtime_ns, info.st_mtime_ns)
        (self.source / 'unrelated.txt').write_text('preserve')
        self.invoke('restore-apply', '--source', backup)
        self.assertEqual(destination.read_bytes(), saved.read_bytes())
        self.assertEqual((self.source / 'unrelated.txt').read_text(), 'preserve')

    def test_restore_rejects_traversal_wrong_pairs_privilege_empty_and_overlap(self):
        backup = self.backup()
        manifest = backup / 'manifest.tsv'
        original = manifest.read_text()
        rows = ['User_Library/../outside\t' + str(self.home / 'Library') + '\tfalse',
                'User_Library/Application Support/Adobe\t' + str(self.home / 'Library/Preferences') + '\tfalse',
                'System_Apps_Data/Applications/Adobe Test.app\t/Applications\ttrue',
                original.splitlines()[1] + '\n' + original.splitlines()[1], '']
        for row in rows:
            manifest.write_text(original.splitlines()[0] + '\n' + row + '\n')
            self.invoke('restore-validate', '--source', backup, status='invalid')

    def test_restore_rejects_missing_source_and_source_or_destination_symlinks(self):
        self.invoke('restore-validate', '--source', self.base / 'missing', status='invalid')
        backup = self.backup()
        target = backup / 'User_Library/Application Support/Adobe/settings.txt'
        target.unlink()
        target.symlink_to(self.source / 'settings.txt')
        self.invoke('restore-apply', '--source', backup, status='invalid')
        target.unlink()
        target.write_text('fixture')
        destination = self.source / 'settings.txt'
        destination.unlink()
        destination.symlink_to(self.base / 'outside')
        self.invoke('restore-apply', '--source', backup, status='invalid')
        self.assertFalse((self.base / 'outside').exists())

    def test_cleanup_preview_and_diagnose_make_no_files_logs_or_database_changes(self):
        before = self.snapshot()
        preview = self.invoke('cleanup-preview')
        self.assertEqual(preview['summary']['scope'], 'manifest-full-cleanup')
        self.assertTrue(any(i['state'] == 'would_remove' for i in preview['items']))
        self.assertTrue(any(i['state'] == 'stale' for i in preview['items']))
        self.assertEqual(preview['summary']['targetCount'], 1)
        self.assertGreater(preview['summary']['bytes'], 0)
        self.invoke('diagnose')
        self.assertEqual(self.snapshot(), before)
        self.assertFalse(list(self.root.rglob('__pycache__')))
        self.assertFalse(list(self.home.rglob('*-shm')))
        self.assertFalse((self.home / 'Library/Logs').exists())

    def test_diagnostic_dependency_and_schema_failures_are_visible_skips(self):
        self.lsregister.write_text('#!/bin/bash\nexit 7\n')
        result = self.invoke('diagnose')
        self.assertTrue(result['warnings'])
        self.assertEqual(result['items'][0]['state'], 'skipped')
        self.lsregister.write_text('#!/bin/bash\nexit 0\n')
        self.db.write_bytes(b'invalid database')
        result = self.invoke('diagnose')
        self.assertTrue(result['warnings'])
        self.assertEqual(result['items'][0]['state'], 'skipped')

    def test_partial_copy_reports_actual_failures(self):
        fake = self.fake('rsync', 'echo copy-error >&2; exit 23')
        self.code.write_text(self.code.read_text().replace("Path('/usr/bin/rsync')", f'Path({str(fake)!r})'))
        selection, _ = self.selection()
        backup = self.invoke('backup-create', '--selection-file', selection, status='partial')
        self.assertEqual(backup['summary']['failed'], 1)
        self.assertEqual(backup['summary']['completed'], 0)
        self.assertEqual(backup['items'][0]['state'], 'failed')

    def test_mutating_cancellation_returns_cancelled_and_stops_grandchildren(self):
        backup = self.backup()
        marker = self.base / 'writing'
        writer = self.base / 'writer.py'
        writer.write_text('import signal,time,sys\nsignal.signal(signal.SIGTERM,signal.SIG_IGN)\n'
                          'while True:\n with open(sys.argv[1],"a") as f: f.write("x")\n time.sleep(.01)\n')
        fake = self.fake('rsync', f'echo copy-started >&2; "{sys.executable}" "{writer}" "{marker}" & wait')
        self.code.write_text(self.code.read_text().replace("Path('/usr/bin/rsync')", f'Path({str(fake)!r})'))
        process = subprocess.Popen(self.command('restore-apply', '--source', backup), env=self.env,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            for _ in range(300):
                if marker.exists(): break
                time.sleep(.01)
            self.assertTrue(marker.exists())
            process.send_signal(signal.SIGTERM)
            out, err = process.communicate(timeout=5)
            result = json.loads(out)
            self.assertEqual(process.returncode, 2, err)
            self.assertEqual(result['status'], 'cancelled')
            self.assertTrue(result['mutates'])
            self.assertTrue(result['warnings'])
            self.assertIn(b'copy-started', err)
            self.assertTrue(result['summary']['currentDestination'])
            self.assertEqual(result['items'][-1]['state'], 'cancelled')
            size = marker.stat().st_size
            time.sleep(.1)
            self.assertEqual(marker.stat().st_size, size)
        finally:
            if process.poll() is None: process.kill()
            process.communicate()

    def test_unsupported_operations_bad_arguments_and_missing_managed_dependencies(self):
        for mode in ('cleanup.apply', 'repair-preview', 'repair.apply', 'unknown'):
            self.invoke(mode, status='unsupported')
        for mode, args in [('backup-scan', ['--source', '/tmp']), ('restore-apply', []),
                           ('restore-validate', ['--source', '/tmp', '--delete']), ('capabilities', ['--password'])]:
            self.invoke(mode, *args, status='invalid')
        (self.root / 'shared/cleaner-manifest.json').unlink()
        self.invoke('capabilities', status='unavailable')

    def test_non_executable_copy_dependency_disables_capabilities(self):
        fake = self.fake('rsync', 'exit 0')
        fake.chmod(0o600)
        self.code.write_text(self.code.read_text().replace("Path('/usr/bin/rsync')", f'Path({str(fake)!r})'))
        self.invoke('capabilities', status='unavailable')

    def test_malformed_cleaner_manifest_fails_closed_without_logs(self):
        (self.root / 'shared/cleaner-manifest.json').write_text('{"version":2}')
        before = self.snapshot()
        self.invoke('cleanup-preview', status='invalid')
        self.assertEqual(self.snapshot(), before)

    def test_duplicate_launch_services_records_are_deduplicated_without_losing_distinct_paths(self):
        self.lsregister.write_text("#!/bin/bash\ncat <<'DUMP'\n"
                                  'bundle id: com.adobe.fixture\npath: /missing/Adobe One.app\n----\n'
                                  'bundle id: com.adobe.fixture\npath: /missing/Adobe One.app\n----\n'
                                  'bundle id: com.adobe.fixture\npath: /missing/Adobe Two.app\nDUMP\n')
        result = self.invoke('diagnose')
        self.assertEqual(len([i for i in result['items'] if i.get('displayPath', '').endswith('.app')]), 2)

    def test_active_launchpad_wal_is_read_without_sidecars_and_has_freshness_warning(self):
        Path(str(self.db) + '-wal').write_bytes(b'fixture WAL')
        before = self.snapshot()
        result = self.invoke('diagnose')
        self.assertTrue(any('WAL' in warning for warning in result['warnings']))
        self.assertEqual(self.snapshot(), before)

    def test_staged_resources_match_canonical_sources(self):
        result = subprocess.run([sys.executable, str(STAGING), '--check'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == '__main__': unittest.main()
