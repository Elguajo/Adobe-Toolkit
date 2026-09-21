# Architecture — Adobe Environment Toolkit

## Recommended stack

- Runtime/framework: Bash on macOS, PowerShell on Windows, Swift 5.9/SwiftUI for the planned macOS 12+ GUI, and WinUI for the later Windows GUI; Python 3 standard-library helpers/tests.
- Data/storage: user-selected backup directories containing `manifest.tsv` and `meta.tsv`; shared JSON cleanup manifest; local cleaner logs.
- Deployment/hosting: local scripts and a Swift Package executable; no service, database, cloud, or telemetry component.
- Important providers/dependencies: macOS `rsync`, `osascript`, `launchctl`, `lsregister`, `sqlite3`; PowerShell on Windows.

## Why this fits

The project is a local machine-maintenance toolkit. Keeping platform scripts as the execution boundary makes cleanup and restore behavior testable. Native UIs can preserve platform-specific interaction and authorization behavior without moving those rules into a cross-platform host.

## System shape

```text
run-macos.command / run-windows.cmd     (independent CLI workflows)
        │
        ├── macOS / Windows backup-restore backend ─ backup manifest + metadata
        └── macOS / Windows cleaner backend ───────── shared/cleaner-manifest.json

gui/adobe-toolkit/macos/                 (planned SwiftUI application; Phase 00)
        └── macOS adapter ──────────────────── existing macOS headless backend contracts

gui/adobe-toolkit/windows/               (planned WinUI application; Phase 01)
        └── Windows adapter ────────────────── existing Windows backend contracts

shared contracts + fixtures              (versioned result schemas; no shared UI code)
```

## Sources of truth

- Cleanup targets and process/service lists → `shared/cleaner-manifest.json`.
- macOS backup/restore behavior and allowlist validation → `macos/AdobeBackuper.command`.
- macOS cleanup execution/reporting → `macos/clean/lib/adobe-cleaner-macos.sh`.
- Native GUI placement and adapter boundary → `gui/adobe-toolkit/macos/`, then `gui/adobe-toolkit/windows/`, and `ADR-002`.
- macOS screen behavior and v1 delivery scope → `gui/adobe-toolkit/macos/INTERACTION_SPEC.md`.
- macOS adapter operation/result schema → `shared/contracts/macos-gui-adapter-v1.md`.
- `macos/AdobeBackuperGUI/` is an existing experimental implementation, retained as reference only; it is not the target location for the new desktop app.
- Cross-platform support claims → `README.md`.

## Security/trust boundaries

- A backup folder and its manifest are untrusted input until validation accepts only approved restore destinations.
- Full cleanup and UI reconciliation modify local user/system state; they require preview, explicit confirmation, and privilege checks.
- Each native UI may request only typed, allowlisted operations; it must not expose a generic shell/process executor.
- Each adapter invokes managed resources for its own OS. GUI v1 has no privileged operation; any later authorization design requires explicit user authorization and never handles passwords.

## Operational assumptions

- The CLI remains independently usable if the GUI cannot resolve a backend or cannot obtain authorization.
- A non-zero backend exit status is surfaced as a failure, never as successful completion.
- Changes to Backup/Restore are adopted by versioned adapter contracts shared by native apps; neither UI may parse incidental menu text or copy script business logic.

## Architecture-change triggers

- Explicit user authorization to begin a macOS privilege-elevation design for GUI cleanup.
- Choosing the Windows privilege-elevation mechanism for GUI cleanup.
- Packaging/signing/notarization for the macOS app, and packaging/signing for the later Windows app.
- Any change to cleanup scope, backup format compatibility, or Windows/macOS behavior parity.
