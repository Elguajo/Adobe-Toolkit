#!/usr/bin/python3
"""Fake managed resource for local native acceptance; never use Adobe paths."""
import json
import os
from pathlib import Path
import shutil
import signal
import stat
import sys
import time

ROOT = Path(__file__).resolve().parents[3]
if not (ROOT / '.acceptance-root').is_file() or not ROOT.name.startswith('adobe-toolkit-acceptance-'):
    raise SystemExit('Fake backend requires a generated temporary acceptance root')

MODES = {'backup-scan': 'backup.scan', 'backup-create': 'backup.create',
         'restore-validate': 'restore.validate', 'restore-apply': 'restore.apply',
         'cleanup-preview': 'cleanup.preview', 'diagnose': 'diagnose.run',
         'capabilities': 'capabilities'}
FILES = {'a' * 64: 'preset.txt', 'b' * 64: 'extension.txt'}
cancelled = False


def cancel(_signal, _frame):
    global cancelled
    cancelled = True


def audit(event, **fields):
    with (ROOT / 'calls.jsonl').open('a') as output:
        output.write(json.dumps(dict(event=event, pid=os.getpid(), **fields)) + '\n')


def main():
    if len(sys.argv) < 3 or sys.argv[1] != '--ui-json' or sys.argv[2] not in MODES:
        raise SystemExit(4)
    operation = MODES[sys.argv[2]]
    mutates = operation in ['backup.create', 'restore.apply']
    summary, items, errors = {}, [], []
    status = 'success'
    audit('start', operation=operation, arguments=sys.argv[1:])
    if operation == 'capabilities':
        summary = {'operations': [v for v in MODES.values() if v != 'capabilities']}
    elif operation == 'backup.scan':
        summary = {'backupRoot': str(ROOT / 'backups'), 'totalFiles': 2, 'totalBytes': 18}
        items = [{'id': identifier, 'category': 'preferences', 'displayPath': str(ROOT / 'sources' / name),
                  'fileCount': 1, 'bytes': (ROOT / 'sources' / name).stat().st_size}
                 for identifier, name in FILES.items()]
    elif operation == 'backup.create':
        if len(sys.argv) != 5 or sys.argv[3] != '--selection-file':
            raise SystemExit(4)
        selection = Path(sys.argv[4])
        info = selection.lstat()
        if not stat.S_ISREG(info.st_mode) or stat.S_IMODE(info.st_mode) != 0o600 or info.st_uid != os.getuid():
            raise SystemExit(4)
        ids = selection.read_text().splitlines()
        if not ids or len(ids) != len(set(ids)) or any(identifier not in FILES for identifier in ids):
            raise SystemExit(4)
        audit('selection', path=str(selection), mode=stat.S_IMODE(info.st_mode),
              directoryMode=stat.S_IMODE(selection.parent.stat().st_mode), ids=ids)
        destination = ROOT / 'backups' / ('backup-' + str(time.time_ns()))
        destination.mkdir()
        for identifier in ids:
            shutil.copy2(ROOT / 'sources' / FILES[identifier], destination / FILES[identifier])
        summary = {'backupPath': str(destination), 'currentDestination': str(destination),
                   'completed': len(ids), 'failed': 0}
    elif operation in ['restore.validate', 'restore.apply']:
        if len(sys.argv) != 5 or sys.argv[3] != '--source':
            raise SystemExit(4)
        # Fixed generated input only: never inspect any other chosen folder.
        source = Path(sys.argv[4]).resolve()
        if source != ROOT / 'valid backup':
            status, errors = 'invalid', ['Fake validation rejects this source.']
        else:
            summary = {'source': str(source), 'currentDestination': str(ROOT / 'destination'),
                       'completed': 0, 'failed': 0}
            if mutates:
                for name in FILES.values():
                    shutil.copy2(source / name, ROOT / 'destination' / name)
                summary['completed'] = 2
    else:
        summary = {'targets': 1, 'readOnly': True}
        items = [{'id': 'fake-observation', 'category': 'temporary', 'state': 'observed',
                  'displayPath': str(ROOT / 'sources'), 'message': 'Simulated observation only.'}]
    if mutates and status == 'success':
        scenario = json.loads((ROOT / 'scenario.json').read_text())
        status = scenario['status']
        assert status in ['success', 'partial', 'failed']
        delay = float(scenario['delay'])
        assert 0 <= delay <= 25
        deadline = time.monotonic() + delay
        while not cancelled and time.monotonic() < deadline:
            time.sleep(0.05)
        if cancelled:
            status = 'cancelled'
        elif status != 'success':
            summary['failed'] = 1
            errors = ['Simulated copy error; temporary copies may remain.']
    code = {'success': 0, 'cancelled': 2, 'invalid': 3, 'partial': 6, 'failed': 7}[status]
    result = dict(schemaVersion=1, operation=operation, status=status, exitCode=code,
                  mutates=mutates, summary=summary, items=items,
                  warnings=['FAKE managed resource; temporary data only.'], errors=errors, logPath=None)
    audit('finish', operation=operation, status=status, exitCode=code, summary=summary)
    print('Fake backend diagnostic: ' + operation, file=sys.stderr)
    print(json.dumps(result), flush=True)
    return code


if __name__ == '__main__':
    signal.signal(signal.SIGTERM, cancel)
    raise SystemExit(main())
