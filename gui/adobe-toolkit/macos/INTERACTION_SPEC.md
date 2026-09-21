# macOS GUI Interaction Specification

## Entry and global states

- `gui/adobe-toolkit/macos/` is the sole planned macOS GUI. Sidebar: **Overview**, **Backup**, **Restore**, **Cleanup**, **Diagnose**, **Repair**.
- Existing CLI entry points remain independent; the GUI neither opens a second Terminal nor changes their interaction.
- One operation runs at once. Navigation remains readable, but new operations are disabled while one runs.
- Resolve only managed macOS resources; never select a script from CWD. Display only backend-returned data; never infer success/health.

| State | Rule |
| --- | --- |
| Unavailable | Explain missing/unsupported managed resource; execution disabled. |
| Ready / Preparing | Show valid prior data or empty state; show progress and supported cancellation. |
| Preview ready | Show exact scope, warnings, counts/sizes, timestamp; destructive apply requires fresh preview. |
| Confirmation | Reserved for non-privileged future actions; GUI v1 does not request macOS authorization. |
| Running | Show current action and copyable log. |
| Completed / Partial / failed / cancelled | Success only for backend `success` + exit `0`; retain report and safe retry. |

Preview, cancellation, and closing the window must not modify files, processes, services, Launch Services, Launchpad, or cleaner logs.

## Screens

### Overview

Show only successful backend observations: detected locations, backup information, preview freshness, and latest result. Before a scan, show “Not scanned”; amber/red requires observed failure, partial result, stale preview, or missing resource.

### Backup

Scan contract-backed locations, select rows, and show selected count/files/size and backend backup root. Create a temporary selection file for the operation, delete it afterward, show the created folder only after success, and retain output on failure.

### Restore

Choose one folder without restoring. Enable after backend validation; Safe copy never deletes unrelated destination files. Failure/partial result retains source, output, and failed destination; never display “Restore complete.”

### Cleanup

Start with a fresh manifest-scoped dry run. Show targets/warnings/skips as non-mutating. Full Cleanup remains unavailable in v1; it never falls back to Terminal `sudo`, accepts a password, or requests authorization.

### Diagnose and Repair

Diagnose is read-only: no logs, Dock restart, or registrations changed. Repair displays an unavailable state in v1 and requests no authorization.

## Reports and recovery

Terminal results retain timestamp, module, backend operation, exit status, counters, warnings/errors, and raw output. Retry re-runs validation/preview; “Open log” is enabled only for a backend-returned path.
