# Architecture — Adobe Environment Toolkit

## Recommended stack

- Runtime/framework: Bash on macOS, PowerShell on Windows, Swift 5.9 / SwiftUI for the experimental macOS GUI, Python 3 standard-library helpers/tests.
- Data/storage: user-selected backup directories containing `manifest.tsv` and `meta.tsv`; shared JSON cleanup manifest; local cleaner logs.
- Deployment/hosting: local scripts and a Swift Package executable; no service, database, cloud, or telemetry component.
- Important providers/dependencies: macOS `rsync`, `osascript`, `launchctl`, `lsregister`, `sqlite3`; PowerShell on Windows.

## Why this fits

The project is a local machine-maintenance toolkit. Keeping platform scripts as the execution boundary makes cleanup and restore behavior testable without adding a service or cross-platform runtime.

## System shape

```text
run-macos.command / run-windows.cmd
        │
        ├── platform backup/restore backend ── backup manifest + metadata
        ├── platform cleaner backend ───────── shared/cleaner-manifest.json
        └── macOS SwiftUI GUI ──────────────── headless script contracts
```

## Sources of truth

- Cleanup targets and process/service lists → `shared/cleaner-manifest.json`.
- macOS backup/restore behavior and allowlist validation → `macos/AdobeBackuper.command`.
- macOS cleanup execution/reporting → `macos/clean/lib/adobe-cleaner-macos.sh`.
- macOS GUI process integration → `macos/AdobeBackuperGUI/Sources/AdobeBackuperGUI/BackupEngine.swift`.
- Cross-platform support claims → `README.md`.

## Security/trust boundaries

- A backup folder and its manifest are untrusted input until validation accepts only approved restore destinations.
- Full cleanup and UI reconciliation modify local user/system state; they require preview, explicit confirmation, and privilege checks.
- A future GUI must pass confirmation through a controlled backend contract and invoke macOS authorization without handling passwords.

## Operational assumptions

- The CLI remains independently usable if the GUI cannot resolve a backend or cannot obtain authorization.
- A non-zero backend exit status is surfaced as a failure, never as successful completion.

## Architecture-change triggers

- Choosing a macOS privilege-elevation mechanism for GUI cleanup.
- Packaging backend scripts as app resources rather than development-relative files.
- Any change to cleanup scope, backup format compatibility, or Windows/macOS behavior parity.
