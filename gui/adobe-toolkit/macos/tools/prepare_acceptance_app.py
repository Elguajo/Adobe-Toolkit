#!/usr/bin/env python3
"""Create an unsigned, disposable GUI wrapper containing only a fake backend."""
import json
from pathlib import Path
import plistlib
import shutil
import tempfile


def main():
    package = Path(__file__).resolve().parents[1]
    binary = package / '.build/release/AdobeToolkit'
    if not binary.is_file():
        raise SystemExit('First run: swift build --package-path gui/adobe-toolkit/macos -c release')
    root = Path(tempfile.mkdtemp(prefix='adobe-toolkit-acceptance-')).resolve()
    root.chmod(0o700)
    (root / '.acceptance-root').touch()
    app = root / 'AdobeToolkitAcceptance.app'
    macos = app / 'Contents/MacOS'
    macos.mkdir(parents=True)
    shutil.copy2(binary, macos / 'AdobeToolkit')
    with (app / 'Contents/Info.plist').open('wb') as output:
        plistlib.dump({'CFBundleExecutable': 'AdobeToolkit',
                      'CFBundleIdentifier': 'dev.adobe-toolkit.acceptance.' + root.name,
                      'CFBundleName': 'Adobe Toolkit Acceptance', 'CFBundlePackageType': 'APPL',
                      'LSMinimumSystemVersion': '12.0'}, output)
    # Bundle.module prefers this exact bundle at Bundle.main.bundleURL. Never
    # copy the production resource bundle or modify a build/source resource.
    backend = app / 'AdobeToolkit_ToolkitCore.bundle/Backend'
    backend.mkdir(parents=True)
    shutil.copy2(package / 'tools/acceptance_backend.py', backend / 'adobe-toolkit-backend-v1')
    (backend / 'adobe-toolkit-backend-v1').chmod(0o755)
    for folder in ['sources', 'valid backup', 'invalid backup', 'destination', 'backups']:
        (root / folder).mkdir()
    for name, data in [('preset.txt', b'preset\n'), ('extension.txt', b'extension!\n')]:
        (root / 'sources' / name).write_bytes(data)
        (root / 'valid backup' / name).write_bytes(data)
    (root / 'destination/unrelated.txt').write_text('preserve me\n')
    (root / 'scenario.json').write_text(json.dumps({'status': 'success', 'delay': 0}))
    print(json.dumps({'root': str(root), 'app': str(app),
                      'source': str(root / 'valid backup'),
                      'scenario': str(root / 'scenario.json')}, indent=2))


if __name__ == '__main__':
    main()
