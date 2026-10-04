# Adobe Toolkit for macOS

Phase 02 delivered a native SwiftUI shell hosted in one AppKit window, typed v1 adapter, and bundled non-interactive macOS backend. Requires macOS 12+, Swift 5.9+ for development, system `/usr/bin/python3` version 3.9+, and `/usr/bin/rsync` for backend operations. No third-party package dependencies.

From the repository root:

```sh
python3 gui/adobe-toolkit/macos/tools/stage_backend.py --check
swift build --package-path gui/adobe-toolkit/macos
swift test --package-path gui/adobe-toolkit/macos
swift run --package-path gui/adobe-toolkit/macos AdobeToolkit
```

Normal launch discovers the bundled v1 backend. Backup Scan/Create, Restore Validate/Safe copy, Cleanup Preview, and Diagnose require advertised capability. Missing/incompatible resources or runtime dependencies leave operations Unavailable. Full Cleanup and Repair remain unavailable and request no authorization.

The adapter invokes only `Backend/adobe-toolkit-backend-v1` below its resource bundle, using argument arrays. It rejects escaping executable symlinks and does not search CWD/PATH, accept a backend path override, parse legacy stdout, or open another Terminal. Managed launches discard shell/Python startup injection variables and use a fixed system PATH. Existing CLI workflows remain independently usable.

Canonical backend code lives in `macos/ui-json/`, reusing the legacy Backup enumerator/exclusions and Restore manifest allowlist through a static internal Bash bridge. Only `--ui-json` delegates to this backend from `macos/AdobeBackuper.command` or `macos/clean/AdobeCleaner.command`. Existing menus, prompts, headless arguments, and output are unchanged. Bundled backend/helper/manifest copies are versioned, generated resources. After changing a canonical source, run:

```sh
python3 gui/adobe-toolkit/macos/tools/stage_backend.py
python3 gui/adobe-toolkit/macos/tools/stage_backend.py --check
```

The complete interface is specified in `shared/contracts/macos-gui-adapter-v1.md`. Capabilities use `summary.operations`; Backup Scan items use `id`, `category`, `displayPath`, `fileCount`, and `bytes`. The native Backup screen selects only rows from the latest successful scan and displays selected location/file/size totals and the backend backup root. Create uses a typed request with IDs; callers cannot supply a selection-file path. The adapter creates an exclusive 0600 UTF-8 file inside a new 0700 temporary directory and removes the directory after success, partial/error output, launch failure, or cancellation. The backend rechecks current scope before writing. Every Create attempt requires a new scan before retry; only successful results expose the created folder.

Restore uses a native single-folder picker attached as a modal sheet to the main window, preventing concurrent pickers or operations while choosing a source. Choosing/changing a folder does not restore and clears validation. The adapter canonicalizes the folder and requires a successful Validate of that same source before Apply; each Apply consumes validation. Failed/partial/cancelled attempts retain the source and copy report while requiring another Validate. Backend Apply revalidates the manifest independently. A new scan/validation does not hide the retained copy report for that module.

Restore validates the whole manifest before copying and revalidates every Apply. Safe copy preserves unrelated destination files and compares checksums so changed content is restored even when file size and modification time match. GUI v1 rejects symlink/special-file copy scopes, stale selections, unsafe or mismatched paths, duplicate/overlapping destinations, and privileged/system items; legacy CLI behavior is retained. Partial/cancelled backup folders and destination copies may remain. Reports include actual exit status, counters, warnings/errors, and current destination rather than implying rollback.

Cleanup Preview and Diagnose use separate read-only paths; they never invoke legacy cleanup/logging, process termination, service changes, registrations, database transactions, or Dock/DNS changes. Preview reports manifest scope, target counts/logical sizes, missing targets, warnings, and timestamp. Missing diagnostic dependencies/schema produce explicit skipped observations; an active Launchpad WAL produces a freshness warning. Launchpad reads are immutable and create no SQLite sidecars.

The backend supervises children in separate worker process groups. Cancellation sends SIGTERM, waits up to 0.3 seconds, escalates to SIGKILL, and reaps the direct child before reporting cancellation. Temporary fake-worker tests include grandchildren that ignore SIGTERM and continue writing. Swift cancellation retains raw backend output, prevents success, unlocks retry, and uses a two-second forced supervisor-stop fallback. Its existing 30-second operation deadline also requests cancellation. Window close and Quit wait for cancellation, backend completion, and selection-file cleanup; new operations are blocked during shutdown. Force termination or a crash cannot guarantee host cleanup.

For safe interface checks:

```sh
swift run --package-path gui/adobe-toolkit/macos AdobeToolkit --fixtures
```

Fixture mode is explicitly labelled. Cleanup Preview returns a simulated success and warning; Backup Scan returns cancellation; Diagnose returns failure. The responses are copies of Phase 00 fixtures from `tests/fixtures/macos_gui_v1/`. No real Adobe locations, processes, registrations, databases, or cleaner logs are accessed.

Manual fixture checks:

1. Visit all six sections and verify that Full Cleanup and Repair remain disabled. Original fixture mode advertises only Scan/Preview/Diagnose, so its Create/Restore controls also stay disabled.
2. Run Cleanup Preview and inspect the simulated target, counters, warning, timestamp, and retained raw report.
3. Run Backup Scan and Diagnose; check Cancelled/Failed reports without a completion notification.
4. Navigate during preparation; another operation must stay disabled. Cancel and retry, or close the window during the fixture operation.

Focused backend checks use temporary HOME/application trees, fake managed resources, fake process/registration observations, and temporary databases only:

```sh
python3 -m unittest discover -s tests -p 'test_macos_ui_*.py' -v
swift test --package-path gui/adobe-toolkit/macos --filter ManagedBackendTests
```

They cover capability/item compatibility, arbitrary CWD, native scan/selection/source gating, literal input arguments, owner-only selection-file lifecycle, stale/invalid selection, manifest/path rejection, Safe copy preservation, non-mutation snapshots, mutating cancellation with resistant grandchildren, retained envelopes, retry, shutdown gating, and staged-source parity. Legacy Backup tests likewise redirect application enumeration to temporary fake directories.

Final native acceptance uses a disposable app containing **only fake managed resources**. Create it after a release build:

```sh
swift build --package-path gui/adobe-toolkit/macos -c release
python3 gui/adobe-toolkit/macos/tools/prepare_acceptance_app.py
```

The tool prints the temporary root, `.app`, valid source, and `scenario.json` paths. Open that returned `.app` using Finder. It copies the built executable and installs a fake resource bundle at the preferred `Bundle.module` location; it never copies the production backend or changes build/source resources. The fake backend scans two generated files (2 locations, 2 files, 18 bytes), copies only generated data, accepts only the generated `valid backup` source, and preserves `destination/unrelated.txt`. It records calls and selection-file permissions in `calls.jsonl` under its private temporary root. These fake reports test presentation; real backend semantics are covered by temporary-resource integration tests.

In the returned `scenario.json`, set `status` to `success`, `partial`, or `failed`, and `delay` to a number from 0 to 25 seconds. This controls Create/Apply only. A delay of 25 permits testing Cancel, window Close, and Quit while copying. Partial/cancelled temporary copies intentionally remain; no rollback is promised. Keep the fake app local and do not distribute it.

Acceptance checklist:

1. Visit all six sections; verify initial Not scanned, Full Cleanup disabled, and Repair Unavailable.
2. Scan, select both rows, check totals/root, Create, and inspect Success/exit 0 and the generated backup folder. Rescan must reset selection and retain the copy report.
3. Choose the generated `invalid backup` folder and Validate: Invalid must keep Apply disabled. Choose `valid backup`: choosing alone must not copy; successful Validate enables Safe copy. Each Apply consumes validation.
4. Exercise Partial/exit 6 and Failed/exit 7, retained source/destination/counters/raw output, and retry only after fresh Validate. Repeat with Success; verify unrelated destination content remains.
5. During delayed Create, navigate: another operation and selection edits stay disabled. Cancel must retain counters/destination and exit 2, require a fresh scan, and allow successful retry.
6. Run Preview/Diagnose and compare temporary data hashes before/after; no privileged operation may appear in the call audit.
7. Close and Quit during delayed Create. Inspect the audit to verify cancelled backend completion, process exit, and removal of its recorded private selection directory. Observe process state without reopening the app.

This checklist passed on macOS 15.8.1 on 2026-10-05; actual evidence and limitations are in `.progressive/completions/02-native-macos-gui-implementation.md`. Normal mode can enumerate real Adobe data; use the generated fake app for acceptance. Original `--fixtures` mode intentionally lacks Create/Restore capability.

The deployment target is macOS 12; execution on Monterey hardware remains unverified. Signing, notarization, production distribution, privilege elevation, real-data restore validation, and Windows GUI work are outside this task.
