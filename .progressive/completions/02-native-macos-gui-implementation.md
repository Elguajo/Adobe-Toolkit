# Phase 02 Completion — Native macOS GUI v1 implementation

Status: COMPLETED
Completed: 2026-10-05

## Outcome

Delivered the native SwiftUI macOS GUI at `gui/adobe-toolkit/macos/`. All four phase tasks and applicable acceptance gates are satisfied with temporary data and fake managed resources. Native runtime acceptance was observed on macOS 15.8.1; minimum deployment target 12.0 was observed in the release executable. Execution on Monterey hardware is not claimed.

## Delivered

- One window with Overview, Backup, Restore, Cleanup, Diagnose, and unavailable Repair.
- Typed managed-resource adapter, capability gating, structured envelopes, current-scan selection, native folder validation, and Safe-copy Restore.
- Optional non-interactive backend with supervised cancellation, read-only Preview/Diagnose, retained reports, and independent legacy CLI workflows.
- Reproducible disposable acceptance app generator and fake backend under `gui/adobe-toolkit/macos/tools/`; usage/checklist in its README.

## Implementation notes

The adapter never selects a backend through CWD/PATH or a runtime override. Backup selection uses exclusive 0600 files inside 0700 directories and is removed after terminal results or cancellation. Restore requires validation of the same source before each Apply. Closing or quitting waits for cancellation/backend completion and selection cleanup. Full Cleanup and Repair cannot reach execution or authorization.

The acceptance generator copies only the release executable and creates the preferred resource bundle containing one fake executable. It does not copy production backend resources, patch production binaries, or change staged/build resources. The fake backend reads generated files and fixed generated sources only. Copy outcomes and delay are controlled by a local `scenario.json`; its audit is confined to the temporary root. This validates native presentation/control flow; actual backend semantics are established by the temporary-resource integration suites.

## Decisions made

- Preserve the accepted GUI v1 allowlist and macOS-only scope. Privileges, production packaging, real-data validation, and Windows remain outside delivery.
- Restore now uses `rsync --checksum` with archive copying to replace different contents with identical size/mtime. Backup copying and legacy CLI semantics are unchanged; no delete/mirror flag is introduced. See `shared/contracts/macos-gui-adapter-v1.md`.
- The source picker is a modal sheet attached to the visible main window, preventing concurrent pickers and main-window operations while choosing a folder.
- Phase 01 remains planned/deferred in Roadmap, separate from the completed current delivery; no future phase is activated without renewed user direction.

## Deviations / technical debt

- Runtime acceptance uses macOS 15.8.1 with Swift 6.2.4, system Python 3.9.6, and test Python 3.12.10. Monterey execution, signing, notarization, and distribution remain unverified/out of scope.
- System Python 3.9+ and rsync are required. The existing 30-second deadline can cancel long copies; checksum comparison adds destination reading during Restore. Partial/cancelled copies may remain. Forced termination/crashes cannot guarantee selection cleanup.
- At phase acceptance, implementation changes were uncommitted. The subsequent delivery commit includes tasks 2–4; the pre-existing GUI image is intentionally excluded and preserved.

## Problems discovered

- Initial Swift integration failed because `rsync -a` skipped changed equal-size contents written within the same timestamp interval. Fixed GUI Restore checksum comparison; Swift regression now deliberately matches destination mtime to the saved file, and a Python regression explicitly matches size and nanosecond mtime while preserving an unrelated sentinel.
- Native picker could open multiple independent panels. Fixed with an attached sheet and verified Invalid/valid source selection and Apply gating. Parent resolution uses the visible main-capable window, including when the app is not currently key.
- Native observation after closing can relaunch a selected app. Close/Quit acceptance therefore checks the call audit, selection directory, backend PID, and app process without requesting another app snapshot.

## Verification evidence

Observed on 2026-10-05 using temporary trees/fake resources only:

- Focused Python backend suite after the checksum fix: `python3 -m unittest discover -s tests -p 'test_macos_ui_backend.py' -v` → 20/20 passed.
- Focused native Safe-copy integration → 1/1 passed; final `swift test --package-path gui/adobe-toolkit/macos` → 38/38 passed. Includes InputFlow 8, ManagedBackend 13, AppModel 5, Adapter 12.
- `swift build --package-path gui/adobe-toolkit/macos -c release` → PASS; `xcrun vtool -show-build .../AdobeToolkit` → minimum macOS 12.0.
- Final `python3 -m unittest discover -s tests -v` → 53/53 passed, including legacy CLI tests and the new equal-size/mtime regression.
- Python syntax, Bash syntax for affected entry points/bridge/launchers, `stage_backend.py --check`, and `git diff --check` → PASS.
- Requirement compliance and code quality were assessed separately against the phase/spec/contract and scoped final changes. No unrelated production/CLI behavior was changed in task 4.

### Native manual acceptance

App: disposable `AdobeToolkitAcceptance.app`, generated temporary root `adobe-toolkit-acceptance-4yn3go6p`. Native actions and AX/screenshot observations used the computer-use tool. The app was closed at the end.

| Check | Observed evidence |
| --- | --- |
| Navigation / initial state | One main window; all six sections; Overview initially Not scanned. |
| Selection totals | Empty selection disables Create; selecting both generated rows shows 2 locations, 2 files, 18 bytes and the temporary backup root. |
| Backup success / freshness | Success, exit 0, completed 2, failed 0, actual generated folder; Create then disabled until rescan. Rescan resets selection and retains the prior copy report. |
| Picker / validation | Native folder-only picker observed as an attached sheet. Choosing a source alone leaves Apply disabled. Invalid generated folder gives Invalid; valid source Validate enables Safe copy. |
| Partial | Restore Partial, exit 6, source/currentDestination/completed/failed/errors/raw output retained; no Restore-complete claim. Fresh Validate enables retry while retaining Partial. |
| Failure / retry | Restore Failed, exit 7, stderr and destination/counters retained; Apply disabled. Fresh Validate retains Failed; subsequent Safe copy returns Success, exit 0. |
| Destination preservation | Temporary `destination/unrelated.txt` remains `preserve me\n`; generated source contents appear at the destination. Actual checksum replacement is verified by real-backend temporary integration tests. |
| Operation locking | During delayed Backup Create, checkboxes/Scan/Create are disabled; navigation to Cleanup works while Run fresh preview stays disabled. |
| Cancellation / retry | Native Cancel produces Cancelled, exit 2, completed counters and destination/raw output; no rollback claim. New scan retains Cancelled; reselect/Create succeeds. |
| Read-only / unavailable | Fake Cleanup Preview/Diagnose produce labelled observations. Temporary data hashes before/after are identical. Full Cleanup stays disabled; Repair Unavailable; call audit contains no privileged operation. |
| Selection lifecycle | Captured selection permissions 0600 and directory permissions 0700; all recorded selection directories absent after completion/cancellation. |
| Window Close while copying | Selection file and running backend verified before Close. Afterwards audit records Cancelled/exit 2, backend PID is gone, selection directory absent, app process exited. |
| Quit while copying | Repeated the active-selection setup and used Cmd-Q. Afterwards Cancelled/exit 2, backend PID gone, all selection directories absent, app process exited. |

Progressive audit and context compilation are recorded in the compact Completion Record after final project-state reconciliation.

## Architectural impact

System shape remains as documented in Architecture/ADR-002. Later authorized work can rely on the v1 contract and temporary-data acceptance harness. The unsigned fake-resource wrapper is a development artifact, not production packaging.

## Follow-up

- No queued work in the current macOS delivery. Future Monterey runtime validation/distribution or deferred Windows work requires explicit scope selection; privileges require separate authorization.
