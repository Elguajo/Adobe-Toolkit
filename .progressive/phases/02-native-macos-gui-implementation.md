# Phase 02 — Native macOS GUI v1 implementation

## Goal

Deliver one native macOS 12+ SwiftUI application at `gui/adobe-toolkit/macos/` against the accepted interaction specification and typed adapter contract, preserving independent CLI workflows.

## Context

- Phase 00 completed the interaction specification, adapter contract, and fake-backend safety fixtures; it did not implement the new app or `--ui-json` backend modes.
- `macos/AdobeBackuperGUI/` is experimental reference code, not the delivery location.
- The user limited current work to macOS on 2026-10-03. Windows is deferred in Roadmap.
- Canonical behavior: `gui/adobe-toolkit/macos/INTERACTION_SPEC.md` and `shared/contracts/macos-gui-adapter-v1.md`.

## In scope

- One SwiftUI window with Overview, Backup, Restore, Cleanup, Diagnose, and unavailable Repair.
- A typed adapter with managed resource resolution, capability discovery, structured result validation, and one operation at a time.
- Optional non-interactive backend modes for Backup, Safe-copy Restore, non-mutating Cleanup Preview, and read-only Diagnose, preserving existing CLI behavior.
- Focused adapter/backend tests, local build/run evidence, and usage documentation.

## Out of scope

- Windows work, cleanup target expansion, backup format changes, and replacement of CLI workflows.
- Privilege elevation, passwords, GUI Full Cleanup or Repair, generic shell execution, signing/notarization, and production distribution.
- Running restore or destructive maintenance against actual user Adobe data as part of validation.

## Tasks

- [x] Implement a buildable SwiftUI shell and typed adapter, initially using safe fixtures; absent backend capability must display Unavailable.
- [x] Implement contract-backed non-interactive macOS modes and capability discovery without changing CLI behavior.
- [x] Connect module screens to supported operations with selection/source validation, cancellation, retained reports, and safe retry.
- [x] Verify acceptance with temporary data, adapter/backend tests, a local app build, and manual UI checks; update usage documentation and completion evidence.

## Acceptance criteria

- [x] The macOS 12+ app builds and runs from the canonical location with one window and all specified navigation items.
- [x] The adapter resolves managed resources independently of CWD and invokes only typed allowlisted operations using argument arrays.
- [x] Unsupported or absent capabilities disable operations; no legacy stdout parsing or second Terminal workflow occurs.
- [x] Backup selection uses current scan IDs and owner-only temporary files removed after completion; Restore requires validation and Safe copy preserves unrelated destination files.
- [x] Cleanup Preview and Diagnose do not modify files, processes, services, registrations, Launchpad, or cleaner logs.
- [x] Full Cleanup and Repair remain unavailable and never invoke a backend or request authorization.
- [x] Only a validated success envelope with actual exit zero produces success; failed, partial, cancelled, malformed, and inconsistent results retain an accurate report.
- [x] Existing CLI tests pass; focused runtime tests and manual GUI evidence establish the accepted behavior without touching real Adobe data.

## Negative / security cases

- Launch from an arbitrary CWD cannot select an unintended script.
- Invalid backup manifests, paths, scan IDs, schema versions, or result fields fail closed.
- Cancellation and window closing do not trigger cleanup or repair; interruption of a mutating operation cannot be reported as success or imply rollback.
- Unsupported privileged operations never reach process execution or authorization.

## Verification

- Focused tests for the delivered adapter and non-interactive backend modes, using fixtures and temporary directories only.
- Swift build and tests from `gui/adobe-toolkit/macos/` once its package exists.
- Manual GUI checks for navigation, operation locking, unavailable states, reports, cancellation, and safe retry.
- `python3 -m unittest discover -s tests -v`
- `python3 .progressive/tools/audit.py --root .`
- `python3 .progressive/tools/context_compile.py --root .`
- `git diff --check`

## Completion Record

Status: COMPLETED — 2026-10-05.

Final report: `.progressive/completions/02-native-macos-gui-implementation.md`.

- Delivered native macOS GUI v1, typed managed backend, selection/validated Safe copy, retained reports, cancellation and shutdown cleanup. Tasks 1–4 and applicable acceptance gates complete.
- Validation: final Swift 38/38, Python 53/53, release build/minimum macOS 12.0, staged parity/syntax/whitespace. Native temporary-data/fake-resource acceptance observed on macOS 15.8.1, including picker, locking, outcomes/retry, Close/Quit cleanup.
- Restore uses checksums for changed contents with equal size/mtime; native source picker is an attached sheet. No legacy CLI change in task 4.
- Later work can rely on the v1 contract and disposable acceptance harness. Monterey execution and production distribution remain unverified; partial copies/crash cleanup remain bounded limitations. Windows and privileges require renewed authorization.
- Final Progressive audit → PASS (0 errors; 12 existing Skill-collision warnings); context compiler and final whitespace check → PASS.

## Task 1 result — 2026-10-03

- Delivered the Swift Package, six-section SwiftUI shell hosted in one AppKit window, actor-isolated typed adapter, managed-resource transport, and explicit `--fixtures` mode at the canonical macOS location. No third-party dependencies or CLI/backend changes.
- Normal launch stays Unavailable: no v1 backend is bundled. The adapter never probes legacy scripts, resolves from CWD/PATH, or accepts an environment override. The managed executable path is `Backend/adobe-toolkit-backend-v1` within the app's resource bundle; escaping symlinks are rejected.
- Only Backup Scan, Cleanup Preview, and Diagnose are connected in this shell. Backup creation and restore remain unavailable until their validated inputs are implemented. Privileged operations are rejected before capability discovery or process execution.
- The scaffold capability payload uses `summary.operations`; scan items use `displayPath`, `fileCount`, and `bytes`. Align these additive conventions with the task 2 backend and test both ends. Cancellation of backend child processes must be designed/tested before any mutation is connected; current fixtures and temporary executable tests perform no real Adobe operation.
- `swift test --package-path gui/adobe-toolkit/macos` → 20/20 passed, including malformed/inconsistent envelopes, actual exits/signals, capabilities, adapter/model locking, navigation/cancellation/retry, CWD/environment isolation, symlink escapes, and concurrent pipe draining.
- `swift build --package-path gui/adobe-toolkit/macos -c release` → PASS. Mach-O deployment target observed as macOS 12.0; runtime validation uses macOS 15.8.1, not Monterey hardware.
- `python3 -m unittest discover -s tests -v` → 32/32 passed. Bundled Phase 00 fixture copies match their originals byte-for-byte.
- Native UI checks use a local unsigned test wrapper under ignored `.build/`, not production packaging. Normal-mode navigation and Unavailable states, fixture preview/cancellation/failure, retained raw output, disabled privileged controls, and explicit Escape cancellation were observed. Closing the window during a fixture preview ended that app process with exit 0; the UI inspection tool subsequently reopened normal mode. Operation locking and retry after navigation/cancellation are covered by adapter/model tests. Task-scoped requirement and code-quality checks were performed separately; whole-phase acceptance remains open.
- Progressive audit → PASS (0 errors; 12 existing local/global Skill collision warnings). Context compiler and whitespace checks are required at each handoff.

## Task 2 result — 2026-10-04

- Implemented optional `--ui-json capabilities`, Backup Scan/Create, Restore Validate/Apply, Cleanup Preview, and Diagnose in `macos/ui-json/`. Existing command entry points delegate only for the new flag; legacy menus/prompts/headless arguments/output remain independent. Backup enumeration/exclusions and legacy manifest allowlist checks are reused through a static NUL-delimited bridge; GUI validation additionally rejects unsafe/mismatched/overlapping paths, special files, symlinks, and privileged/system items.
- Managed Swift Package resources are generated from canonical backend/helpers/manifest sources by `tools/stage_backend.py`, checked byte-for-byte, and resolved inside the resource bundle independently of CWD. Backend requires system Python 3.9+ and rsync; absent/incompatible resources disable discovery. `summary.operations` and scan `id/category/displayPath/fileCount/bytes` are documented in the v1 contract and validated end-to-end by Swift tests. Managed launches remove shell/Python startup injection variables and use the system PATH.
- Selection is owner-only UTF-8 IDs, rechecked against the current scope before writes; the backend does not remove host input. Safe copy preserves unrelated destination files and retains partial folders/reports. Adapter selection-file creation/removal and source/selection UI flows remain task 3; no input-bearing GUI operation was enabled.
- Established/tested child cancellation before implementing mutation: workers use isolated process groups, SIGTERM then bounded SIGKILL, output draining, and direct-child reaping. Cancellation during spawn is latched. Runtime tests stop a TERM-resistant writing grandchild, retain cancelled exit 2, counters/current destination/stderr, and verify native adapter retry. System Python 3.9 lost already-read stderr when `communicate()` was reentered from a signal handler; cleanup now runs after unwinding in `finally`, with a regression assertion. No rollback is claimed.
- Preview and Diagnose use separate read-only manifest/process/registration observation and immutable Launchpad planning paths. Temporary HOME/database/resource snapshots verify no file/log/database/sidecar changes. Missing resources/schema are explicit skips/warnings; active WAL has a freshness warning. No cleanup/repair, authorization, or observed Adobe-process signal path is reachable.
- Focused/backend tests: `python3 -m unittest discover -s tests -p 'test_macos_ui_*.py' -v` → 20/20 passed. Native managed integration was also exercised in the focused Swift transport suite; final `swift test --package-path gui/adobe-toolkit/macos` → 23/23 passed.
- `swift build --package-path gui/adobe-toolkit/macos -c release` → PASS; `xcrun vtool -show-build` observes Mach-O minimum macOS 12.0. `/usr/bin/python3` runtime used by fake-resource integration is 3.9.6; test runner Python is 3.12.10; Swift is 6.2.4. Execution on Monterey remains unverified.
- `python3 -m unittest discover -s tests -v` → 52/52 passed. Existing Backup tests now redirect application enumeration to temporary fake directories, preventing real installed Adobe data from entering the mandated full suite. All new runtime verification used temporary data/fake managed resources; no real Adobe mutation/maintenance or new manual GUI acceptance was performed.
- Requirement compliance and code quality were checked separately against the final implementation, with scoped re-review of cancellation/output and dependency failure handling. Bash syntax, managed-source parity, and `git diff --check` → PASS. Progressive audit → PASS (0 errors; 12 existing Skill collision warnings). Phase 02 remains active; task 3 and final manual GUI acceptance remain open.
- Context compiler → PASS. Updated the stale Phase 02 manifest hint to task 3; it retains only the active macOS phase/specification/contract and prior completion bridge, without loading the deferred Windows phase.

## Task 3 result — 2026-10-05

- Delivered typed native Backup selection/Create and folder-picker Restore Validate/Safe copy. Current-scan IDs/same canonical validated source gate copying; retry requires fresh scan/validation. Backend remains authoritative; CLI/backend behavior and scope are preserved.
- Adapter owns exclusive 0600 selection files in 0700 temporary directories, removes them on results/errors/cancellation, and reports cleanup failure. Close/Quit wait for completion/cleanup and block new operations; crashes/forced termination can leave private directories.
- Screens show selected totals/root, successful folder, source and reports. Cancellation retains exit/counters/destination/output through completion races, without success/rollback claims. README/contract updated.
- Final Swift suite → 38/38; focused InputFlowTests → 8/8. Temporary-data integration verifies Safe copy, stale scan/changed manifest rejection, literal arguments, resistant-grandchild cancellation and retry. NSWindow close-handler cleanup tested.
- Progressive audit → PASS (0 errors; 12 existing Skill-collision warnings); context compiler → PASS.
- Release build → PASS; `vtool` minimum macOS 12.0. Focused backend → 20/20; full Python → 52/52. Bash syntax, staged parity and whitespace → PASS. Separate scope/code-quality checks → PASS.
- Temporary data/fake resources only. Task 4 manual GUI acceptance, Monterey and production distribution remain unverified.

## Task 4 result — 2026-10-05

- Final native acceptance completed using generated temporary data/fake managed resources only. Reproducible local app generator and checklist added; durable manual evidence in the final report.
- Discovered/fixed equal-size/mtime Restore skipping with GUI-only checksum comparison and deterministic Swift/Python regression coverage. Fixed concurrent native pickers with a main-window modal sheet; verified source/Apply gating.
- Observed selection totals/root, successful Create/Safe copy, Invalid/Partial/Failed/Cancelled reports, retained reports/fresh retry, navigation/operation locking, unavailable privileged controls, immutable temporary observations, and Close/Quit cancellation with process/selection cleanup.
- Final Swift 38/38; Python 53/53; release build/minimum macOS 12.0; staged-source parity, Python/Bash syntax and whitespace passed. Scoped requirement and code-quality reviews performed separately.
- All applicable phase gates satisfied. Phase complete; Windows remains planned/deferred. No real Adobe operations, privileges, production packaging, or external writes.
