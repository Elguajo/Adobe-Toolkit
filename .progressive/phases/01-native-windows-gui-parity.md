# Phase 01 — Native Windows GUI parity specification

## Goal

Produce an implementation-ready, safety-first specification for one WinUI application at `gui/adobe-toolkit/windows/`. It preserves the independent Windows cmd/PowerShell workflows, shares the macOS GUI v1 result-envelope semantics and fixture safety properties, and does not implement a UI, a backend, or privileged operations.

## Planning depth

FULL: this phase defines a platform-specific contract around local destructive tooling and a shared result schema. The native-UI choice is already accepted in ADR-002; no new architecture or privilege-elevation decision is made here.

## Context

- `run-windows.cmd`, `windows/run-backup.cmd`, and `windows/run-restore.cmd` remain supported independent CLI workflows. They are not managed GUI backends.
- `windows/adobe-backup.ps1` supports backup and safe-copy restore, but emits human-readable output only and has no capability discovery or structured result envelope.
- `windows/clean/AdobeCleaner.ps1 -Mode DryRunFull` stops processes/services and writes a cleaner log before reporting paths. Despite its name, it is not a non-mutating cleanup preview and must not be invoked by GUI v1.
- Windows has no Diagnose or Repair backend. README marks both unavailable on Windows.

## In scope

- Define one-window WinUI navigation, module states, reports, and unavailable explanations that preserve visual and result-state parity with the macOS specification without sharing UI code.
- Define the Windows adapter v1 allowlist, capability discovery, typed inputs, result envelope, exit mapping, and managed-resource resolution requirements.
- Specify the required non-mutating Windows cleanup-preview semantics and fixture cases before any backend/UI implementation.
- Define how unavailable, malformed, inconsistent, failed, cancelled, and partial results appear without false success.

## Out of scope

- Implementing a WinUI project, PowerShell `ui-json` mode, Windows backend hardening, packaging/signing, or Windows CI.
- Invoking or changing existing cmd/PowerShell workflows, cleanup targets, backup formats, or `shared/cleaner-manifest.json`.
- GUI UAC, Full Cleanup, Repair, generic process execution, passwords, confirmation phrases, registry cleanup, or any destructive GUI action.

## Required v1 boundary

The future Windows adapter resolves only managed Windows resources and sends typed argument arrays. It never selects a script from the current working directory, calls `run-windows.cmd`, parses legacy stdout, opens a second console workflow, or exposes a generic PowerShell executor.

The intended operation surface is `backup.scan`, `backup.create`, `restore.validate`, `restore.apply`, and `cleanup.preview`. Each remains unavailable until a managed backend advertises the v1 capability and returns exactly one valid structured result. `cleanup.apply`, `diagnose.run`, `repair.preview`, and `repair.apply` are unsupported in Windows GUI v1 and must not invoke a backend or request elevation.

`cleanup.preview` must be strictly non-mutating: no files, processes, services, registry state, logs, or system registrations may change. The current `DryRunFull` implementation fails this rule; a future backend-hardening phase must provide a new managed preview capability before the GUI can expose it.

## Tasks

- [ ] Specify WinUI navigation, global operation states, module screens, unavailable copy, and report/retry behavior in `gui/adobe-toolkit/windows/INTERACTION_SPEC.md`.
- [ ] Specify `shared/contracts/windows-gui-adapter-v1.md`, retaining the compatible v1 envelope/status/exit semantics while defining Windows-specific typed operations and resource rules.
- [ ] Define safe fake-backend fixtures for unavailable capability, unsupported operations, failure, cancellation, malformed/inconsistent JSON, and cleanup-preview immutability without executing PowerShell or touching Adobe data.
- [ ] Record the Windows backend-hardening precondition as the follow-up required before a WinUI adapter can execute any v1 operation.

## Acceptance criteria

- [ ] The specification identifies exactly one planned Windows GUI location and retains every existing Windows CLI entry point/workflow.
- [ ] No GUI v1 operation falls back to a cmd/PowerShell menu, incidental stdout, or an arbitrary working-directory script.
- [ ] Full Cleanup, Diagnose, and Repair are visibly unavailable and never request UAC or invoke a backend.
- [ ] Cleanup Preview remains unavailable until a future backend proves it is non-mutating; the present `DryRunFull` path is explicitly prohibited.
- [ ] A malformed, inconsistent, cancelled, partial, failed, unavailable, or unsupported result cannot yield a success notification.
- [ ] The resulting contract and fixtures are sufficient to implement Windows backend hardening and WinUI separately without reopening privilege or cleanup-scope decisions.

## Negative / security cases

- GUI launch from an arbitrary working directory cannot select an unintended `.cmd` or `.ps1` file.
- A backend that reports `success` with a non-zero exit code, omits required fields, or reports a mutating preview is a failed GUI result.
- Unsupported Full Cleanup, Diagnose, and Repair cause neither backend invocation nor an elevation request.
- Preview does not stop a process or service, write a cleaner log, modify a path, touch the registry, or change a system registration.

## Verification

- `python3 .progressive/tools/audit.py --root .`
- `python3 .progressive/tools/context_compile.py --root .`
- `python3 -m unittest discover -s tests -v`
- `git diff --check`

## Completion Record

Populate only when this phase becomes `[x]`.
