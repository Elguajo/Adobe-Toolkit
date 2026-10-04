#!/usr/bin/env python3
"""Optional macOS v1 backend. Never dispatches legacy interactive maintenance."""
from __future__ import annotations

import datetime
import fnmatch
import glob
import hashlib
import json
import os
from pathlib import Path
import signal
import stat
import sys
import uuid

from processes import Cancelled, Workers

OPERATIONS = {'backup-scan': 'backup.scan', 'backup-create': 'backup.create',
              'restore-validate': 'restore.validate', 'restore-apply': 'restore.apply',
              'cleanup-preview': 'cleanup.preview', 'diagnose': 'diagnose.run'}
CODES = {'success': 0, 'cancelled': 2, 'invalid': 3, 'unavailable': 4,
         'unsupported': 4, 'partial': 6, 'failed': 7}


class Invalid(Exception):
    pass


class Unavailable(Exception):
    pass


def identity(*values):
    return hashlib.sha256(json.dumps(values, ensure_ascii=True).encode()).hexdigest()


def no_links(path):
    for component in (path, *path.parents):
        if component.is_symlink():
            raise Invalid(f'Symlink is outside the v1 copy policy: {component}')


def safe_text(value):
    if not value or any(c in value for c in '\0\t\r\n'):
        raise Invalid('Paths must be nonempty and representable in the v1 TSV manifest.')
    return value


def scope_stats(path):
    """Logical counts for preview; links are counted but never followed."""
    info = path.lstat()
    if stat.S_ISDIR(info.st_mode):
        counts = [scope_stats(child) for child in path.iterdir()]
        return sum(row[0] for row in counts), sum(row[1] for row in counts)
    return 1, info.st_size


def tree(path, excludes=()):
    """Fingerprint and count copy scope, without following links or silently skipping errors."""
    digest = hashlib.sha256()
    count = size = 0

    def visit(node):
        nonlocal count, size
        if any(fnmatch.fnmatchcase(node.name, pattern) for pattern in excludes):
            return
        info = node.lstat()
        if stat.S_ISLNK(info.st_mode) or not (stat.S_ISREG(info.st_mode) or stat.S_ISDIR(info.st_mode)):
            raise Invalid(f'Unsupported copy item: {node}')
        digest.update(str((str(node.relative_to(path.parent)), info.st_mode, info.st_ino,
                           info.st_size, info.st_mtime_ns)).encode('utf-8'))
        if stat.S_ISDIR(info.st_mode):
            for child in sorted(node.iterdir()):
                visit(child)
        else:
            count += 1
            size += info.st_size
    no_links(path)
    visit(path)
    return count, size, digest.hexdigest()


class Backend:
    def __init__(self, root):
        self.root = Path(root).resolve()
        self.home = Path.home().resolve()
        self.backup_root = self.home / 'Desktop/Backups'
        self.rsync = Path('/usr/bin/rsync')
        self.applications = Path('/Applications')
        self.pgrep = Path('/usr/bin/pgrep')
        self.lsregister = Path('/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister')
        self.launchpad = self.home / 'Library/Application Support/Dock'
        self.workers = Workers()
        self.items = []
        self.summary = {}
        self.warnings = []
        self.mutation_started = False

    def child(self, args, allowed=(0,)):
        try:
            rc, out, err = self.workers.run([str(arg) for arg in args], env={**os.environ,
                                          'HOME': str(self.home), 'PATH': '/usr/bin:/bin:/usr/sbin:/sbin',
                                          'PYTHONDONTWRITEBYTECODE': '1'})
        except (FileNotFoundError, PermissionError) as exc:
            raise Unavailable(f'Cannot execute managed dependency: {args[0]}: {exc}') from exc
        if err:
            sys.stderr.buffer.write(err)
            sys.stderr.flush()
        if allowed is not None and rc not in allowed:
            raise Invalid(f'Validation failed (exit {rc}).')
        return rc, out

    def ready(self):
        needed = ['macos/ui-json/bridge.sh', 'macos/AdobeBackuper.command',
                  'shared/cleaner-manifest.json', 'shared/validate_cleaner_manifest.py',
                  'macos/clean/lib/launch_services_records.py', 'macos/clean/lib/launchpad_reconcile.py']
        if any(not (self.root / name).is_file() or not (self.root / name).resolve().is_relative_to(self.root)
               for name in needed) or not self.rsync.is_file() or not os.access(self.rsync, os.X_OK):
            raise Unavailable('Managed backend dependencies are missing.')

    def scan(self):
        _, data = self.child(['/bin/bash', self.root / 'macos/ui-json/bridge.sh', 'scan'])
        fields = data.decode('utf-8').split('\0')
        records = []
        while fields and fields[0]:
            end = fields.index('')
            row, fields = fields[:end], fields[end + 1:]
            if len(row) < 6:
                raise Invalid('Malformed managed enumeration.')
            category, source, destination, parent, admin, kind = row[:6]
            source = Path(safe_text(source))
            relative = safe_text(destination.removeprefix('/__v1_backup__/'))
            safe_text(parent)
            excludes = [v.removeprefix('--exclude=') for v in row[6:]]
            count, size, fingerprint = tree(source, excludes)
            if not count:
                continue
            item_id = identity(category, str(source), relative, parent, excludes, fingerprint)
            records.append({'id': item_id, 'category': category, 'displayPath': str(source),
                            'fileCount': count, 'bytes': size, 'relative': relative,
                            'parent': parent, 'excludes': excludes})
        self.items = [{key: item[key] for key in ('id', 'category', 'displayPath', 'fileCount', 'bytes')}
                      for item in records]
        self.summary = {'backupRoot': str(self.backup_root), 'fileCount': sum(i['fileCount'] for i in records),
                        'bytes': sum(i['bytes'] for i in records), 'itemCount': len(records)}
        return records

    def observation(self, category, state, path, message, key=None):
        item = {'id': identity(category, key, str(path), message), 'category': category,
                'state': state, 'message': message}
        if path is not None:
            item['displayPath'] = str(path)
        for existing in self.items:
            if existing['id'] == item['id']:
                return existing
        self.items.append(item)
        return item

    def copy(self, source, parent, excludes=(), checksum=False):
        # Safe copy has no mirror/delete switch. Diagnostic rsync stdout goes to stderr.
        self.mutation_started = True
        self.summary['currentDestination'] = str(parent / source.name)
        parent.mkdir(parents=True, exist_ok=True)
        # Restore must replace different contents even when size/mtime match.
        rc, out = self.child([self.rsync, '-a', '--safe-links', *(['--checksum'] if checksum else []),
                              *('--exclude=' + e for e in excludes),
                              '--', source, str(parent) + '/'], allowed=None)
        if out:
            sys.stderr.buffer.write(out)
        return rc

    def create(self, selection):
        path = Path(selection)
        if not path.is_absolute():
            raise Invalid('Selection file must be absolute.')
        # O_NOFOLLOW and fstat validate the opened file, not a racy prior path check.
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        with os.fdopen(fd, 'r', encoding='utf-8') as stream:
            info = os.fstat(stream.fileno())
            if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077 or info.st_size > 1024 * 1024:
                raise Invalid('Selection must be an owner-only regular UTF-8 file.')
            ids = stream.read().splitlines()
        if not ids or len(ids) != len(set(ids)) or any(len(i) != 64 or any(c not in '0123456789abcdef' for c in i) for i in ids):
            raise Invalid('Selection must contain unique current-scan IDs only.')
        records = {item['id']: item for item in self.scan()}
        self.items = []
        if any(i not in records for i in ids):
            raise Invalid('Selection is unknown or stale; scan again.')
        selected = [records[i] for i in ids]
        no_links(self.backup_root)
        self.mutation_started = True
        self.backup_root.mkdir(parents=True, exist_ok=True)
        folder = self.backup_root / ('Adobe_Backup_' + datetime.datetime.now().strftime('%Y-%m-%d_%H-%M-%S') + '_' + uuid.uuid4().hex[:8])
        folder.mkdir(mode=0o700)
        self.items = []
        self.summary = {'backupRoot': str(self.backup_root), 'backupPath': str(folder), 'completed': 0, 'failed': 0}
        meta = 'backup_format_version\t1\ntool_version\t1\nplatform\tmacos\ncreated\t' + datetime.datetime.now().isoformat() + '\n'
        (folder / 'meta.tsv').write_text(meta, encoding='utf-8')
        with (folder / 'manifest.tsv').open('w', encoding='utf-8') as manifest:
            manifest.write('backup_path\trestore_parent\tadmin\n')
            for item in selected:
                destination = folder / item['relative']
                rc = self.copy(Path(item['displayPath']), destination.parent, item['excludes'])
                state = 'failed' if rc else 'copied'
                self.summary['failed' if rc else 'completed'] += 1
                self.observation(item['category'], state, destination, f'Copy exit {rc}', item['id'])
                if not rc:
                    manifest.write(f"{item['relative']}\t{item['parent']}\tfalse\n")
                    manifest.flush()
        return 'partial' if self.summary['failed'] else 'success'

    def validate(self, raw):
        source = Path(raw)
        if not source.is_absolute() or not source.is_dir():
            raise Invalid('Restore source must be an absolute directory with a v1 manifest.')
        source = source.resolve()
        for name in ('manifest.tsv', 'meta.tsv'):
            if os.path.lexists(source / name):
                no_links(source / name)
                if not (source / name).is_file():
                    raise Invalid('Manifest and metadata must be regular files.')
        if not (source / 'manifest.tsv').is_file():
            raise Invalid('Manifest is required; GUI v1 does not guess legacy layouts.')
        self.child(['/bin/bash', self.root / 'macos/ui-json/bridge.sh', 'validate', source])
        rows = (source / 'manifest.tsv').read_text(encoding='utf-8').splitlines()[1:]
        records = []
        for row in rows:
            if not row:
                continue
            fields = row.split('\t')
            if len(fields) != 3:
                raise Invalid('Invalid manifest row.')
            relative, raw_parent, admin = fields
            safe_text(relative)
            safe_text(raw_parent)
            # Re-check the exact bytes consumed here; the legacy validation read must
            # never authorize a different manifest swapped in between the two reads.
            if relative.startswith('/') or any(part in ('', '.', '..') for part in relative.split('/')):
                raise Invalid('Invalid relative backup path.')
            if any(part in ('', '.', '..') for part in raw_parent.strip('/').split('/')):
                raise Invalid('Invalid restore destination path.')
            if admin != 'false' or not relative.startswith(('User_Library/', 'User_Documents/', 'App_Customizations/')):
                raise Invalid('Privileged/system restore items are unsupported in GUI v1.')
            item = source / relative
            if not item.resolve().is_relative_to(source):
                raise Invalid('Backup item escapes the restore source.')
            parent = Path(raw_parent)
            if not parent.is_absolute():
                raise Invalid('Restore destination must be absolute.')
            no_links(item)
            no_links(parent)
            destination = parent / item.name
            no_links(destination)
            # Reject a source/destination overlap and all destination links before rsync.
            if source.is_relative_to(destination) or destination.is_relative_to(source):
                raise Invalid('Restore source overlaps destination.')
            tree(item)
            if destination.exists():
                tree(destination)
            # User restore must retain its original Library/Documents relative mapping.
            if relative.startswith('User_Library/'):
                expected = self.home / 'Library' / relative.removeprefix('User_Library/')
                if destination != expected:
                    raise Invalid('Mismatched user Library restore destination.')
            elif relative.startswith('User_Documents/'):
                expected = self.home / 'Documents' / relative.removeprefix('User_Documents/')
                if destination != expected or not expected.is_relative_to(self.home / 'Documents/Adobe'):
                    raise Invalid('Mismatched user Documents restore destination.')
            else:
                app_name, separator, item_path = relative.removeprefix('App_Customizations/').partition('/')
                if not separator or not any(fnmatch.fnmatchcase(app_name, pattern) for pattern in
                                           ('Adobe After Effects *', 'Adobe Illustrator *', 'Adobe Photoshop *')):
                    raise Invalid('Unsupported application customization.')
                if item_path not in ('Plug-ins', 'Scripts/ScriptUI Panels') and not fnmatch.fnmatchcase(item_path, 'Presets/*/Scripts'):
                    raise Invalid('Unsupported application customization path.')
                app_root = self.applications / app_name
                if not app_root.is_dir() or destination != app_root / item_path:
                    raise Invalid('Mismatched application customization restore destination.')
            if any(destination == r[2] or destination.is_relative_to(r[2]) or r[2].is_relative_to(destination) for r in records):
                raise Invalid('Duplicate or overlapping restore destinations.')
            records.append((item, parent, destination))
        if not records:
            raise Invalid('Manifest has no restorable items.')
        self.items = []
        for item, parent, destination in records:
            self.observation('restore', 'validated', destination, 'Safe copy destination validated.')
        self.summary = {'source': str(source), 'itemCount': len(records), 'safeCopy': True}
        return records

    def restore(self, source):
        records = self.validate(source)  # Revalidate every apply, never trust a prior UI validation.
        self.items = []
        self.summary.update(completed=0, failed=0)
        for item, parent, destination in records:
            rc = self.copy(item, parent, checksum=True)
            self.summary['failed' if rc else 'completed'] += 1
            self.observation('restore', 'failed' if rc else 'copied', destination, f'Copy exit {rc}')
        return 'partial' if self.summary['failed'] else 'success'

    def cleaner_manifest(self):
        self.child([sys.executable, self.root / 'shared/validate_cleaner_manifest.py',
                    self.root / 'shared/cleaner-manifest.json'])
        return json.loads((self.root / 'shared/cleaner-manifest.json').read_text())['macos']

    def diagnose(self):
        if not self.lsregister.is_file():
            self.warnings.append('Launch Services dump unavailable; Launchpad reconciliation skipped.')
            self.observation('ui', 'skipped', self.lsregister, 'Launch Services resource is missing.')
            return
        rc, dump = self.child([self.lsregister, '-dump'], allowed=tuple(range(256)))
        if rc:
            self.warnings.append('Launch Services dump failed; Launchpad reconciliation skipped.')
            self.observation('ui', 'skipped', self.lsregister, f'Launch Services dump exit {rc}.')
            return
        # Load the existing parser without its write/output command path.
        import importlib.util
        spec = importlib.util.spec_from_file_location('ls_records', self.root / 'macos/clean/lib/launch_services_records.py')
        module = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = module
        spec.loader.exec_module(module)
        live = set()
        for record in module.records(dump.decode('utf-8').splitlines()):
            if not record.path.lower().endswith('.app'):
                continue
            if Path(record.path).exists():
                live.update(i for i in (record.bundle_id, record.canonical_id) if i)
            elif module.is_adobe_identity(record):
                self.observation('ui', 'stale', record.path, 'Missing Adobe Launch Services registration.', record.bundle_id)
        databases = sorted(self.launchpad.glob('*.db'))
        if not databases:
            self.observation('ui', 'not_found', self.launchpad, 'Launchpad database not found.')
        for db in databases:
            args = [sys.executable, self.root / 'macos/clean/lib/launchpad_reconcile.py', 'plan', db, '--immutable']
            if Path(str(db) + '-wal').exists():
                self.warnings.append(f'Launchpad WAL is active; immutable snapshot may omit recent records: {db}')
            for bundle_id in sorted(live):
                args += ['--live-id', bundle_id]
            rc, output = self.child(args, allowed=(0, 3))
            if rc:
                self.warnings.append(f'Launchpad schema/read skipped: {db}')
                self.observation('ui', 'skipped', db, 'Launchpad schema/read unavailable.')
            else:
                for row in output.decode('utf-8').splitlines():
                    kind, item_id, title, bundle_id, reason = row.split('\t')
                    self.observation('ui', 'stale' if kind == 'REMOVE' else 'preserved', db, reason, str(db) + item_id)

    def preview(self):
        data = self.cleaner_manifest()
        for pattern in data['paths_remove']:
            expanded = pattern.replace('~', str(self.home), 1) if pattern.startswith('~') else pattern
            matches = sorted(glob.glob(expanded)) if glob.has_magic(expanded) else ([expanded] if os.path.lexists(expanded) else [])
            for path in matches or [expanded]:
                found = path in matches
                item = self.observation('filesystem', 'would_remove' if found else 'not_found', path,
                                        'Manifest-scoped target; no deletion performed.' if found else 'Manifest target not found.')
                if found:
                    try:
                        item['fileCount'], item['bytes'] = scope_stats(Path(path))
                    except OSError as exc:
                        self.warnings.append(f'Cannot estimate target size: {path}: {exc}')
                if found and ('/LaunchAgents/' in path or '/LaunchDaemons/' in path):
                    self.observation('launchd', 'would_bootout', path, 'Service unload is previewed only.')
        # pgrep reads process state. No pkill/launchctl/sudo/maintenance executable is invoked.
        for pattern in data['kill_patterns']:
            rc, output = self.child([self.pgrep, '-f', pattern], allowed=(0, 1))
            self.observation('processes', 'would_stop' if rc == 0 else 'not_found', None,
                             f'{pattern}: {len(output.splitlines())} matching processes; no signals sent.', pattern)
        self.diagnose()
        self.observation('post_actions', 'skipped', None, 'DNS flush and Dock restart are never executed by preview.')
        targets = [item for item in self.items if item['category'] == 'filesystem' and item['state'] == 'would_remove']
        self.summary = {'itemCount': len(self.items), 'scope': 'manifest-full-cleanup', 'nonMutating': True,
                        'targetCount': len(targets), 'fileCount': sum(item.get('fileCount', 0) for item in targets),
                        'bytes': sum(item.get('bytes', 0) for item in targets),
                        'sizeComplete': all('bytes' in item for item in targets)}

    def dispatch(self, mode, args):
        if mode not in (*OPERATIONS, 'capabilities'):
            return 'unsupported'
        expected = {'backup-create': '--selection-file', 'restore-validate': '--source', 'restore-apply': '--source'}
        if mode in expected:
            if len(args) != 2 or args[0] != expected[mode]:
                raise Invalid('Expected one input option and one absolute path.')
        elif args:
            raise Invalid('Unexpected backend arguments.')
        self.ready()
        if mode == 'capabilities':
            self.summary = {'operations': list(OPERATIONS.values()), 'cancellation': 'worker-process-groups'}
        elif mode == 'backup-scan': self.scan()
        elif mode == 'backup-create': return self.create(args[1])
        elif mode == 'restore-validate': self.validate(args[1])
        elif mode == 'restore-apply': return self.restore(args[1])
        elif mode == 'cleanup-preview': self.preview()
        elif mode == 'diagnose':
            self.diagnose()
            self.summary = {'itemCount': len(self.items), 'nonMutating': True}
        return 'success'


def main():
    arguments = sys.argv[1:]
    mode = arguments[1] if len(arguments) >= 2 and arguments[0] == '--ui-json' else ''
    backend = Backend(Path(__file__).resolve().parents[2])
    signal.signal(signal.SIGTERM, backend.workers.cancel)
    signal.signal(signal.SIGINT, backend.workers.cancel)
    errors = []
    try:
        if sys.version_info < (3, 9):
            raise Unavailable('System Python 3.9 or newer is required.')
        status = backend.dispatch(mode, arguments[2:]) if mode else 'invalid'
    except Cancelled:
        status = 'cancelled'
        backend.warnings.append('Cancelled; completed/partial copies may remain. No rollback is implied.')
        for output in backend.workers.interrupted_output:
            if output:
                sys.stderr.buffer.write(output)
        if backend.mutation_started and 'currentDestination' in backend.summary:
            backend.observation('copy', 'cancelled', backend.summary['currentDestination'],
                                'Copy interrupted; destination may be partial. No rollback is implied.')
    except Unavailable as exc:
        status = 'partial' if backend.mutation_started else 'unavailable'
        errors.append(str(exc))
    except (Invalid, ValueError, UnicodeError) as exc:
        status = 'partial' if backend.mutation_started else 'invalid'
        errors.append(str(exc))
    except OSError as exc:
        status = 'partial' if backend.mutation_started else 'invalid'
        errors.append(str(exc))
    except Exception as exc:
        status = 'partial' if backend.mutation_started else 'failed'
        errors.append(str(exc))
    if mode != 'backup-scan':
        backend.items = [item for item in backend.items if 'state' in item]
    backend.summary['timestamp'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    envelope = {'schemaVersion': 1, 'operation': OPERATIONS.get(mode, mode or 'unknown'),
                'status': status, 'exitCode': CODES[status], 'mutates': mode in ('backup-create', 'restore-apply'),
                'summary': backend.summary, 'items': backend.items, 'warnings': backend.warnings,
                'errors': errors, 'logPath': None}
    print(json.dumps(envelope, ensure_ascii=True), flush=True)
    return CODES[status]


if __name__ == '__main__':
    raise SystemExit(main())
