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

`--ui-json` is a future optional non-interactive mode. It must not change legacy menus, prompts, arguments, or Terminal output. Until a backend advertises v1 capability, the adapter returns `unavailable`; it never parses human stdout as a fallback.

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
- `items` are typed operation data. Backup items include stable ID, category, display paths, file count, and bytes. Other items include stable ID, category, state, optional display path, and message.
- `summary` contains aggregates and operation facts only; never a shell command, password, or confirmation phrase. `logPath` is an optional absolute backend-returned display path.

## Input, exit, and compatibility

- Restore sources originate in the native folder picker, are canonicalized, and are passed as one argument. The backend remains authoritative for manifest/allowlist validation.
- Selection files live in the app temporary directory with owner-only permissions and contain only current-scan IDs resolved by the adapter.
- Exit mapping: `0` success, `2` cancelled, `3` invalid input/validation, `4` unavailable dependency/resource, `5` authorization required/denied, `6` partial, `7` execution failure. Legacy CLI behavior is unchanged.
- Stale preview, unknown operation/version, malformed JSON, or non-zero status never enables mutation or a success notification.
- Compatible fields may be added to v1. Removing/changing a field requires v2; unsupported versions disable the operation.

## Deferred privilege boundary

No v1 argument accepts a password or confirmation phrase for Full Cleanup/Repair. A privileged design is explicitly out of scope until the user authorizes a later phase; until then these operations must always return `unsupported`.
