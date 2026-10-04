#!/usr/bin/env python3
"""Stage/check byte-identical managed resources; never locate a backend at runtime."""
import argparse
from pathlib import Path
import shutil
import sys

ROOT = Path(__file__).resolve().parents[4]
DESTINATION = Path(__file__).resolve().parents[1] / 'Sources/ToolkitCore/Resources/Backend'
FILES = ['macos/AdobeBackuper.command', 'macos/ui-json/backend.py', 'macos/ui-json/processes.py',
         'macos/ui-json/bridge.sh', 'macos/ui-json/adobe-toolkit-backend-v1', 'macos/clean/lib/launch_services_records.py',
         'macos/clean/lib/launchpad_reconcile.py', 'shared/cleaner-manifest.json',
         'shared/validate_cleaner_manifest.py']


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    files = {DESTINATION / name: ROOT / name for name in FILES}
    files[DESTINATION / 'adobe-toolkit-backend-v1'] = ROOT / 'macos/ui-json/managed-launcher'
    for destination, source in files.items():
        if args.check:
            if not destination.is_file() or destination.read_bytes() != source.read_bytes():
                print(f'Managed resource out of date: {destination}', file=sys.stderr)
                return 1
        else:
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, destination)
            destination.chmod(0o755 if destination.name == 'adobe-toolkit-backend-v1' else 0o644)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
