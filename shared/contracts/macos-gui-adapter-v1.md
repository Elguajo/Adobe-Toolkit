# macOS GUI Adapter Contract v1

## Boundary

The SwiftUI app owns a typed adapter. It resolves managed script resources and invokes them with `Process` argument arrays; it never builds shell strings or exposes a generic process executor.

## Operations

| Operation | v1 backend mode | Mutates | Rule |
| --- | --- | :---: | --- |
| `backup.scan` | `--ui-json backup-scan` | No | Required before selection. |
| `backup.create` | `--ui-json backup-create --selection-file <host-file>` | Yes | Uses only IDs returned by `backup.scan`; remove the host-created UTF-8 file after completion. |
| `restore.validate` | `--ui-json restore-validate --source <folder>` | No | Required before Restore is enabled. |
| `restore.apply` | `--ui-json restore-apply --source <folder>` | Yes | Safe copy only; no mirror/delete option in v1. |
| `cleanup.preview` | `--ui-json cleanup-preview` | No | Fresh Full Cleanup dry run; no cleaner logs. |
| `diagnose.run` | `--ui-json diagnose` | No | No cleaner logs, Dock restart, or registration changes. |
| `cleanup.apply`, `repair.preview`, `repair.apply` | Not exposed | — | Return `unsupported`; UI stays Unavailable and requests no authorization. |

`--ui-json` is an optional non-interactive mode, implemented on macOS by `macos/ui-json/`. Both existing macOS command entry points delegate only when this flag is present. Legacy menus, prompts, arguments, and Terminal output remain independent. Until a managed backend advertises v1 capability, the adapter returns `unavailable`; it never parses human stdout as a fallback.

## Capability and result envelope

The adapter first requests `--ui-json capabilities`. A supported operation emits exactly one UTF-8 JSON object to stdout; diagnostics go only to stderr.

```json
{
  "schemaVersion": 1,
  "operation": "backup.scan",
  "status": "success",
  "exitCode": 0,
  "mutates": false,
  "summary": {},
  "items": [],
  "warnings": [],
  "errors": [],
  "logPath": null
}
```

- `status`: `success`, `cancelled`, `invalid`, `unavailable`, `unsupported`, `partial`, or `failed`.
- `success` requires exit `0`; every other status requires non-zero. Missing/malformed/inconsistent output is `failed` in the UI.
- Capability envelopes use `operation: "capabilities"`, `mutates: false`, empty `items`, and `summary.operations`: a unique array of the supported v1 operation names from the table. Privileged operations are never advertised. The current backend also advertises `summary.cancellation: "worker-process-groups"`.
- Backup Scan items use exactly `id`, `category`, `displayPath`, `fileCount`, and `bytes`; counters are non-negative integers. IDs are opaque SHA-256 identifiers, stable for an unchanged source/copy scope and fingerprinted with file metadata. The backend recomputes current IDs before accepting selection, so changed, missing, unknown, duplicate, or raw-path selections fail closed. No scan-state file is written.
- Other items use `id`, `category`, `state`, optional `displayPath`, and `message`. Preview filesystem items may additionally carry `fileCount` and `bytes`. Observation IDs distinguish separate paths and deduplicate identical observations.
- `summary` contains aggregates and operation facts only; never a shell command, password, or confirmation phrase. `logPath` is an optional absolute backend-returned display path.

## Input, exit, and compatibility

- Restore sources originate in the native single-folder picker, are canonicalized, and are passed as one argument. Choosing/changing a source clears UI validation; the adapter accepts Apply only after successful Validate of that canonical source. An Apply attempt consumes validation, and a Create attempt consumes the current scan, so retry requires fresh validation/scan. Copy reports retain source/output/destination while another check runs. The backend remains authoritative for manifest/allowlist validation.
- Selection files live in the app temporary directory with owner-only permissions and contain only current-scan IDs resolved by the adapter.
- Selection encoding is UTF-8, one scan ID per line, with an optional final newline. The backend opens an absolute, owner-owned regular file without following its final symlink, rejects group/other permissions and inputs larger than 1 MiB, and never removes the host's file. The adapter creates an exclusive 0600 file in a new 0700 app temporary directory and removes that directory after every returned result, preparation/launch failure, or cancellation; close/Quit wait for completion. A host crash/forced termination may leave the private temporary directory. Callers supply IDs, never host-file paths.
- GUI Restore requires `manifest.tsv`; valid legacy metadata may be absent. The backend validates again for each Apply. GUI v1 rejects privileged/system items, traversal, duplicate/overlapping destinations, source/destination overlap, mismatched source/destination pairs, special files, and symlinks in copy sources/destinations. Ordinary user Library/Documents and installed supported application customizations retain the existing backup format and allowlist. These stricter GUI rules do not change legacy CLI Restore.
- Safe copy uses archive copying without any delete/mirror option. Restore compares checksums to replace different contents even when size and modification time match. Unrelated destination files remain. Only successfully copied items are added to a new backup manifest; partial/cancelled folders are retained and reported without a rollback claim.
- Cleanup Preview uses only manifest expansion, process observation, Launch Services `-dump`, and immutable Launchpad planning. Diagnose uses only the latter two observations. Neither path enters legacy maintenance/logging. Active Launchpad WAL files produce a snapshot-freshness warning; immutable reads never create SQLite sidecars. Missing diagnostic resources/schema are visible skipped observations and warnings, not a health conclusion.
- Exit mapping: `0` success, `2` cancelled, `3` invalid input/validation, `4` unavailable dependency/resource, `5` authorization required/denied, `6` partial, `7` execution failure. Legacy CLI behavior is unchanged.
- Stale preview, unknown operation/version, malformed JSON, or non-zero status never enables mutation or a success notification.
- Compatible fields may be added to v1. Removing/changing a field requires v2; unsupported versions disable the operation.

## Cancellation

The backend supervises each child in a new worker process group. SIGTERM/SIGINT stop the entire active worker group, wait up to 0.3 seconds, escalate to SIGKILL, drain output, and reap the direct child before emitting `cancelled`/exit `2`. Cancellation between spawn and registration is latched and handled before waiting. Workers must not detach from their group; current managed helpers and rsync do not do so. No signal is sent to observed Adobe processes during preview or diagnosis.

The Swift transport requests SIGTERM on the supervisor and retains its result/output; its two-second SIGKILL deadline is a fallback for an unresponsive supervisor. Cancellation never reports success or implies rollback. Mutation reports retain counters, backup/source paths, and `summary.currentDestination` once a copy begins; interrupted destinations may contain partial files.

## Deferred privilege boundary

No v1 argument accepts a password or confirmation phrase for Full Cleanup/Repair. A privileged design is explicitly out of scope until the user authorizes a later phase; until then these operations must always return `unsupported`.
