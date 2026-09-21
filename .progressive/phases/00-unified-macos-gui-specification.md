# Phase 00 — Unified macOS GUI specification

## Goal

Produce an implementation-ready, safety-first specification for one native macOS interface that exposes the existing Backup, Restore, Cleanup, Diagnose, and Repair flows without a second Terminal window.

## Context

- The current SwiftUI executable supports backup/restore through `BackupEngine`.
- The current launcher opens `AdobeBackuper.command` in a separate Terminal window.
- Cleanup can be destructive and currently depends on a Terminal confirmation phrase plus `sudo`.

## Context hints

- `macos/AdobeBackuperGUI/Sources/AdobeBackuperGUI/BackupEngine.swift`
- `macos/AdobeBackuper.command`
- `macos/clean/lib/adobe-cleaner-macos.sh`

## In scope

- Define one-window navigation, screen states, preview/report presentation, and error handling for the five macOS modules.
- Define explicit headless backend contracts required by the GUI, including structured result/exit behavior.
- Decide how a GUI requests macOS authorization for destructive cleanup without collecting passwords or bypassing confirmation.
- Preserve CLI entry points as supported independent execution paths.

## Out of scope

- Implementing the GUI screens or changing cleanup targets.
- Replacing scripts with a new backend, Windows GUI work, or a SwiftUI redesign unrelated to the unified flow.
- Weakening confirmation, safe-copy, manifest validation, or administrator boundaries.

## Approved interaction specification — navigation and states

### Entry points and navigation

- The native app is the single GUI entry point. Its primary sidebar order is **Overview**, **Backup**, **Restore**, **Cleanup**, **Diagnose**, and **Repair**.
- `run-macos.command`, `AdobeBackuper.command`, and `AdobeCleaner.command` remain supported CLI entry points. The GUI must not launch any of them in a second Terminal window.
- Only one module operation may execute at a time. While an operation is running, switching sections remains possible for reading, but every action that starts a backend process is disabled and the active operation remains visible in the window toolbar.
- A packaged app resolves only its bundled backend resources. Development builds may use an explicitly configured development path; an arbitrary current working directory must never choose a script.
- The sidebar labels are actions, not independent data stores: every displayed item, size, preview, and report comes from the backend result for the current run. The GUI must not invent a green validation or success state.

### Shared operation state model

Every module uses the following presentation states; the actual backend contract is defined by the next task in this phase.

| State | UI behavior | Transition rule |
| --- | --- | --- |
| Unavailable | Explain that the managed backend/resource cannot be found; show a copyable diagnostic. | No execution action is enabled. |
| Ready | Show the last valid data or an empty-state explanation and one primary next action. | User starts a scan, selection, or preview. |
| Preparing | Show progress and a Cancel control when the backend supports cancellation. | Backend returns a preview/result, is cancelled, or fails. |
| Preview ready | Show exact scope, warnings, estimated counts/sizes when available, and time of generation. | A destructive action may proceed only from a fresh preview. |
| Confirmation required | Require an explicit user decision; Full Cleanup also requires the exact confirmation phrase. | Cancel returns to preview without invoking a mutating backend command. |
| Authorizing | Reserved for a macOS system authorization request. | Approval continues; denial/cancellation is non-success. |
| Running | Show an indeterminate/progress indicator, current action, and a copyable live log. | Backend returns a terminal result. |
| Completed | Use only when backend exit status and structured result both indicate success. | A new operation returns to Ready/Preparing. |
| Partial / failed / cancelled | Never show a success banner. Preserve preview, backend output, failed targets, and a retry-safe next action. | Retry starts at the required safe stage (usually preview). |

No transition from Preview ready, Confirmation required, or Cancelled may modify files, processes, services, Launch Services, Launchpad, or cleaner logs. Closing the window does not turn a pending operation into success.

### Overview

- The initial screen summarizes the most recent successful backend observations: detected Adobe locations, available backup information, cleanup preview freshness, and the latest operation outcome.
- Until an observation exists, cards use an explicit “Not scanned” state rather than sample numbers. A primary action takes the user to Backup; secondary actions open Diagnose and Cleanup Preview.
- A red/amber status is reserved for an observed backend failure, partial result, stale preview, or unavailable resource. “Healthy” is not inferred merely because the app launched.

### Backup

- **Ready / preparing:** request the current backup scan and display only locations returned by `--scan-backup-tsv`; each row shows category, source, destination, file count, and size.
- **Preview ready:** allow selecting one or more scanned locations, show the selected count/files/estimated size, and state the backend-selected backup root. The GUI does not offer a destination chooser until the backend contract supports it.
- **Running:** create the temporary selection file only for the current operation, remove it after completion, and display `--backup-headless` output.
- **Completed:** show the actual created backup folder and offer “Open in Finder” only after a successful result. Any non-zero result is Failed and retains the output.

### Restore

- **Ready:** choose exactly one backup directory; no restore starts merely by choosing it.
- **Preview / confirmation:** show the selected folder and the Safe copy guarantee: existing unrelated destination files are not deleted. Display validation only after the backend has accepted the manifest and allowed destinations; the current UI must not pre-label an unvalidated folder as valid.
- **Running:** invoke the headless restore once after confirmation. If an administrator action is needed, transition through Authorizing; cancelled/denied authorization is non-success.
- **Completed / partial / failed:** show the source folder, copyable output, and any failed destination. Partial or failed restore never reports “Restore complete.”

### Cleanup

- Cleanup opens in **Preparing** and always obtains a fresh Full Cleanup dry run before the destructive action is enabled. The preview is manifest-scoped; the GUI cannot add arbitrary paths or silently narrow the shown scope.
- **Preview ready:** display categories/targets returned by the backend, warnings, and any skipped/not-found items. The preview is explicitly labelled non-mutating.
- **Confirmation required:** “Remove Files” stays disabled until the preview is fresh and the user enters `YES DELETE ADOBE` exactly. Choosing Dry Run can only refresh the preview.
- **Authorizing / running:** Full Cleanup may begin only after the later authorization decision and backend contract are implemented. Until then, the app may present the preview but must explain that Apply Cleanup is unavailable; it must not fall back to Terminal `sudo` or ask for a password.
- **Result:** render success, failed, skipped, and not-found counts separately. Any failed target is Partial, uses a non-success visual treatment, and keeps the report/log available.

### Diagnose and Repair

- **Diagnose** is read-only and maps to the cleaner’s `diagnose` mode. It shows availability of Launch Services/Launchpad checks, stale records found, skipped checks, and diagnostic output. It never restarts Dock, writes cleaner logs, or changes registrations.
- **Repair** is a separate mutating module mapped to `repair-ui`. It must first obtain a dry-run repair preview, display the exact registrations/UI records that would change, require explicit confirmation, and use the same authorization/error model as Cleanup when privilege is required.
- Until the backend exposes a structured preview/result and confirmation-safe repair invocation, Repair presents an unavailable explanatory state rather than calling `repair-ui` directly.

### Reports and recovery

- Each terminal state keeps a timestamp, selected module, backend command identifier, exit status, summary counters, warnings/errors, and copyable raw output. Paths are shown as text, never executed as shell input.
- “Retry” always re-runs validation/preview where state may have changed; it never reuses a stale destructive approval.
- “Open log” is enabled only for a path returned by the managed backend. The GUI never treats a log write as proof that a dry run or failed operation succeeded.

## Tasks

- [x] Specify the unified navigation and per-module states from the approved visual concept.
- [ ] Specify the backend invocation/result contract for Backup, Restore, Preview Cleanup, Full Cleanup, Diagnose, and Repair UI.
- [ ] Record the macOS authorization decision after a narrow evidence-gathering step.
- [ ] Define acceptance and fixture tests for failure propagation, cancellation, preview immutability, and privileged-cleanup refusal.

## Acceptance criteria

- [ ] The specification identifies one supported GUI entry point and retains all current CLI entry points.
- [ ] Every destructive GUI action has a preview, explicit confirmation, and an authorization/error path.
- [ ] The chosen authorization approach never transfers a password into application code or environment variables.
- [ ] Backend failures have a defined GUI state and cannot produce a success notification.
- [ ] Implementation scope is bounded enough to start work without reopening product or security decisions.

## Negative / security cases

- GUI launch from an arbitrary working directory cannot select an unintended backend script.
- Missing backend, malformed backup manifest, invalid confirmation, privilege denial, and partial cleanup each produce a non-success result.
- Preview does not alter filesystem, processes, services, Launch Services, Launchpad, or logs.

## Verification

- `python3 .progressive/tools/audit.py --root .`
- `python3 .progressive/tools/context_compile.py --root .`
- Existing `python3 -m unittest discover -s tests -v`
- A reviewed architecture/security decision before destructive GUI implementation.

## Completion Record

Populate only when this phase becomes `[x]`.
