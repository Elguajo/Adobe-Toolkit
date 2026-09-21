# Phase 00 — Native macOS GUI specification

## Goal

Produce an implementation-ready, safety-first specification for one macOS 12+ interface at `gui/adobe-toolkit/macos/`. GUI v1 exposes Backup, Restore, Cleanup Preview, and Diagnose without changing or opening a second Terminal workflow; Full Cleanup/Repair remain CLI-only. A later Windows WinUI application shares backend-contract semantics and fixtures, not this UI code.

## Context

- `macos/AdobeBackuperGUI/` is an experimental macOS-only Backup/Restore GUI and a reference, not the target for the new application.
- Existing macOS launchers own their independent Terminal workflows.
- Backup/Restore are changing independently; the GUI must follow their versioned machine-readable contracts rather than duplicate their logic.
- Cleanup can be destructive and currently depends on a Terminal confirmation phrase plus `sudo`.

## Context hints

- `macos/AdobeBackuper.command`
- `macos/clean/lib/adobe-cleaner-macos.sh`

## In scope

- Define one-window navigation, screen states, preview/report presentation, and error handling for the five macOS modules.
- Define an explicit versioned macOS-adapter contract required by the GUI, including structured result/exit behavior.
- Preserve macOS CLI entry points and their Terminal workflows as supported independent execution paths.

## Out of scope

- Implementing the new SwiftUI screens/app or changing cleanup targets.
- Replacing scripts with a new backend, changing existing Terminal interaction, or creating a macOS GUI outside `gui/adobe-toolkit/macos/`.
- Implementing Windows UI code; it follows in Phase 01 after this phase is accepted.
- Designing or implementing GUI privilege elevation, Full Cleanup, or Repair. That scope requires future explicit user authorization.
- Weakening confirmation, safe-copy, manifest validation, or administrator boundaries.

## Interaction and v1 delivery boundary

The canonical [macOS interaction specification](../../gui/adobe-toolkit/macos/INTERACTION_SPEC.md) defines navigation, operation states, reports, and all module screens.

macOS GUI v1 includes Backup, Safe-copy Restore, Cleanup Preview, and Diagnose. Full Cleanup and Repair stay Unavailable and do not request authorization. Windows later shares result-schema semantics and fixtures, not SwiftUI code.

## macOS adapter contract v1

The canonical [adapter contract](../../shared/contracts/macos-gui-adapter-v1.md) defines the typed allowlist, result envelope, and v1 compatibility rules. The SwiftUI app never constructs shell strings. Full Cleanup and Repair remain outside v1 until explicit future user authorization.

## Tasks

- [x] Specify the unified navigation and per-module states from the approved visual concept.
- [x] Choose the native macOS-first boundary: SwiftUI in `gui/adobe-toolkit/macos/`, then WinUI in `gui/adobe-toolkit/windows/`, with shared contracts/fixtures and preserved CLI workflows (`ADR-002`).
- [x] Specify the versioned macOS-adapter invocation/result contract for Backup, Restore, Cleanup Preview, and Diagnose; defer Full Cleanup/Repair until future explicit user authorization.
- [x] Define fixture tests for failure propagation, cancellation, preview immutability, and privileged-operation refusal.

## Acceptance criteria

- [x] The specification identifies one supported macOS GUI entry point and retains all current macOS CLI entry points/workflows.
- [x] GUI v1 has no privileged or destructive-cleanup action; Full Cleanup/Repair display an unavailable explanation.
- [x] Backend failures have a defined GUI state and cannot produce a success notification.
- [x] macOS GUI v1 supports Backup, Restore, Cleanup Preview, and Diagnose only through the adapter contract; Full Cleanup and Repair remain unavailable.
- [x] Implementation scope is bounded enough to start work without reopening product or security decisions.

## Negative / security cases

- GUI launch from an arbitrary working directory cannot select an unintended backend script.
- Missing backend, malformed backup manifest, unavailable Full Cleanup/Repair, and partial cleanup each produce a non-success result.
- Preview does not alter filesystem, processes, services, Launch Services, Launchpad, or logs.

## Verification

- `python3 .progressive/tools/audit.py --root .`
- `python3 .progressive/tools/context_compile.py --root .`
- Existing `python3 -m unittest discover -s tests -v`
- Fixture tests proving Full Cleanup/Repair cannot be invoked by GUI v1.

## Completion Record

Status: COMPLETED

### Outcome

Specified the macOS 12+ GUI v1 boundary and verified its safety semantics with fake-backend fixtures; no SwiftUI application or privileged GUI operation was implemented.

### Delivered

- Canonical interaction and adapter-contract specifications for Backup, Safe-copy Restore, Cleanup Preview, and Diagnose.
- Fixture tests for preview immutability, typed refusal of Full Cleanup/Repair, backend failure, cancellation, and malformed or inconsistent JSON results.

### Decisions made

- GUI v1 exposes no privileged operation: `cleanup.apply`, `repair.preview`, and `repair.apply` return `unsupported` without backend invocation or authorization.
- Fixtures use only temporary directories and an in-memory fake backend; they do not invoke real cleanup, Launch Services, Launchpad, `sudo`, or Adobe-data operations.

### Verification evidence

- `python3 .progressive/tools/audit.py --root .` → PASS (0 errors; expected Skill-collision warnings only).
- `python3 .progressive/tools/context_compile.py --root .` → PASS.
- `python3 -m unittest discover -s tests -v` → 32/32 passed.
- `git diff --check` → PASS.

### Architectural impact

Later native GUI work may rely on the v1 adapter allowlist, result-envelope rules, and shared fixture semantics. Privileged Full Cleanup and Repair remain outside scope pending explicit user authorization.

### Follow-up

- Select and scope Phase 01 — Native Windows GUI parity; do not begin privileged GUI operations.
