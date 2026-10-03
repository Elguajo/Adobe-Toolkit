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
- [ ] Implement contract-backed non-interactive macOS modes and capability discovery without changing CLI behavior.
- [ ] Connect module screens to supported operations with selection/source validation, cancellation, retained reports, and safe retry.
- [ ] Verify acceptance with temporary data, adapter/backend tests, a local app build, and manual UI checks; update usage documentation and completion evidence.

## Acceptance criteria

- [x] The macOS 12+ app builds and runs from the canonical location with one window and all specified navigation items.
- [x] The adapter resolves managed resources independently of CWD and invokes only typed allowlisted operations using argument arrays.
- [x] Unsupported or absent capabilities disable operations; no legacy stdout parsing or second Terminal workflow occurs.
- [ ] Backup selection uses current scan IDs and owner-only temporary files removed after completion; Restore requires validation and Safe copy preserves unrelated destination files.
- [ ] Cleanup Preview and Diagnose do not modify files, processes, services, registrations, Launchpad, or cleaner logs.
- [x] Full Cleanup and Repair remain unavailable and never invoke a backend or request authorization.
- [x] Only a validated success envelope with actual exit zero produces success; failed, partial, cancelled, malformed, and inconsistent results retain an accurate report.
- [ ] Existing CLI tests pass; focused runtime tests and manual GUI evidence establish the accepted behavior without touching real Adobe data.

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

Populate only when this phase becomes `[x]`.

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
