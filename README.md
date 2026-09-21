# Adobe Environment Toolkit

**Backup · Restore · Diagnose · Clean**

Cross-platform utilities for preserving and safely managing an Adobe Creative Cloud environment on **macOS** and **Windows**.

[![GitHub stars](https://img.shields.io/github/stars/Elguajo/Adobe-Toolkit?style=flat-square)](https://github.com/Elguajo/Adobe-Toolkit/stargazers)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)](LICENSE)
![macOS](https://img.shields.io/badge/macOS-supported-black?style=flat-square&logo=apple)
![Windows](https://img.shields.io/badge/Windows-supported-0078D4?style=flat-square&logo=windows)

Use it before reinstalling Adobe apps, moving to a new machine, repairing a damaged Adobe environment, or removing leftover Adobe files after uninstalling.

> [!IMPORTANT]
> Create a backup before using destructive cleanup actions. Full cleanup permanently removes paths defined in [`shared/cleaner-manifest.json`](shared/cleaner-manifest.json).

## Why use it?

Adobe installations can accumulate more than just applications. A working setup may also depend on preferences, workspaces, presets, plugins, ScriptUI panels, CEP extensions, and system registrations.

Adobe Environment Toolkit gives you one place to:

- **Back up** user Adobe settings and third-party extensions.
- **Restore** a previous backup without deleting unrelated files by default.
- **Diagnose** stale Adobe registrations before changing anything.
- **Preview cleanup** before deleting files.
- **Repair stale UI registrations** on macOS.
- **Perform full cleanup** only after explicit confirmation.

## Feature support

| Feature | macOS | Windows |
| --- | --- | --- |
| Backup | Yes | Yes |
| Restore | Yes | Yes |
| Cleanup preview | Yes | Yes |
| Full cleanup | Yes | Yes |
| Diagnose stale UI | Yes | No |
| Repair stale UI | Yes | No |
| GUI | Experimental | No |
| Automated tests | Yes | No |

## Common use cases

| Situation | Recommended workflow |
| --- | --- |
| Moving to a new computer | Backup → move backup → Restore |
| Reinstalling Creative Cloud | Backup → uninstall/reinstall → Restore |
| Checking a broken Adobe setup | Diagnose |
| Removing leftover Adobe files | Backup → Cleanup Preview → Full Cleanup |
| Stale Adobe entries in macOS UI | Diagnose → Repair UI Preview → Repair UI |

## Safety first

The toolkit separates inspection from destructive actions.

### macOS

| Action | Changes system | Deletes Adobe files |
| --- | :---: | :---: |
| `diagnose` | No | No |
| `--dry-run full` | No | No |
| `--dry-run repair-ui` | No | No |
| `repair-ui` | Yes | Only confirmed stale UI records |
| Full cleanup | Yes | Yes |

Full cleanup requires the confirmation phrase:

```text
YES DELETE ADOBE
```

Administrator privileges are requested when system locations need to be modified.

### Windows

| Action | Changes system | Deletes Adobe files |
| --- | :---: | :---: |
| `clean` | Stops Adobe processes/services | No |
| `clean-preview` | No | No |
| `clean-full` | Yes | Yes |

`clean-full` requires administrator privileges and explicit PowerShell confirmation.

> [!NOTE]
> For removing Adobe applications themselves, prefer Adobe's normal uninstallers or the official Adobe Creative Cloud Cleaner Tool first. This repository does **not** contain or distribute Adobe applications or DMG installers.

`Full Cleanup` means only the cleanup paths defined in this toolkit's manifest. It does not claim to remove registry data, Adobe licensing state, installer databases, credentials, or every Adobe system component. Use Adobe's official Creative Cloud Cleaner Tool for its supported uninstall and repair workflow.

## Quick start

Clone the repository:

```bash
git clone https://github.com/Elguajo/Adobe-Toolkit.git
cd Adobe-Toolkit
```

### macOS

The easiest option is to double-click:

```text
run-macos.command
```

Then choose the action from the menu.

You can also run commands from Terminal:

```bash
./run-macos.command backup
./run-macos.command clean

# Always inspect cleanup before full deletion
./macos/clean/AdobeCleaner.command --dry-run full
./macos/clean/AdobeCleaner.command kill

# Inspect and repair stale UI registrations
./macos/clean/AdobeCleaner.command diagnose
./macos/clean/AdobeCleaner.command --dry-run repair-ui
./macos/clean/AdobeCleaner.command repair-ui
```

### Windows

Run:

```text
run-windows.cmd
```

Or pass a command directly:

```cmd
run-windows.cmd backup
run-windows.cmd restore "C:\path\to\backup"
run-windows.cmd clean
run-windows.cmd clean-preview
run-windows.cmd clean-full
```

## What gets backed up?

The backup module is designed to preserve the parts of an Adobe environment that are difficult or annoying to recreate manually.

| Data | macOS | Windows |
| --- | :---: | :---: |
| Adobe user preferences | ✓ | ✓ |
| Workspaces | ✓ | ✓ |
| User presets | ✓ | ✓ |
| Third-party plugins | ✓ | ✓ |
| ScriptUI Panels | ✓ | ✓ |
| CEP extensions | ✓ | ✓ |

Where possible, caches, logs, and standard Adobe components are excluded.

Direct backup/restore entry points remain available:

- macOS: `macos/AdobeBackuper.command`
- Windows: `windows/run-backup.cmd`
- Windows restore: `windows/run-restore.cmd`

Restore is non-destructive by default and does not remove extra unrelated files.

## How cleanup works

Cleanup actions use a shared manifest:

[`shared/cleaner-manifest.json`](shared/cleaner-manifest.json)

It defines Adobe-related processes, services, and filesystem paths for macOS and Windows.

The manifest is checked against [`shared/cleaner-manifest.schema.json`](shared/cleaner-manifest.schema.json) before macOS cleanup. Validate it locally with:

```bash
python3 shared/validate_cleaner_manifest.py shared/cleaner-manifest.json shared/cleaner-manifest.schema.json
```

> [!WARNING]
> Full cleanup follows this manifest. Review changes to the manifest carefully because destructive cleanup uses it as the source of truth.

### Exit codes

The macOS cleaner uses a stable result contract: `0` for success, `1` for partial operation failure, `2` for a cancelled or invalid confirmation, `3` for an invalid manifest or backup structure, and `4` for a required unsupported dependency. A dry run returns `0` when its validation succeeds.

### macOS cleanup details

<details>
<summary>Launch Services, Launchpad and stale UI registration handling</summary>

After file cleanup, the macOS cleaner can remove stale registrations for deleted Adobe applications from Launch Services.

A registration is handled only when:

- the corresponding bundle no longer exists on disk; and
- Adobe identity is confirmed through a bundle ID or canonical ID.

This also allows stale registrations from external volumes, home-directory locations, or archived folders to be considered without removing live applications merely because their names look Adobe-related.

The cleaner can also inspect the current user's Launchpad database.

Before the first write:

1. a timestamped backup of the Launchpad database is created;
2. the backup is verified;
3. only confirmed orphan records are changed inside a single SQLite transaction.

Adobe bundle IDs are removed only when no live registration exists.

A non-Adobe record is removed only when the cleaner previously recorded the corresponding bundle before deleting it itself. Otherwise, it remains a diagnostic finding.

The Launchpad database is **not** reset wholesale. Unrelated apps, folders, page layout, and ordering are preserved.

The Dock is restarted only after a relevant change.

</details>

<details>
<summary>What happens when macOS tooling or schema checks fail?</summary>

`diagnose` does not modify the system. It reports registrations and records that would be handled or intentionally preserved.

`--dry-run full` and `--dry-run repair-ui` also leave Launch Services and Launchpad unchanged. They show the planned actions, future backup path, and whether a Dock restart would be required.

If `lsregister`, `sqlite3`, the Launchpad database, or an expected database schema is unavailable, cleanup continues without UI reconciliation and logs the skipped step.

The cleaner only operates on a Launchpad schema after validating it first. Future macOS schemas are not assumed to be compatible automatically.

</details>

## Project structure

```text
Adobe Environment Toolkit/
├── run-macos.command
├── run-windows.cmd
├── macos/
│   ├── AdobeBackuper.command
│   └── clean/
├── windows/
│   ├── adobe-backup.ps1
│   ├── run-backup.cmd
│   ├── run-restore.cmd
│   └── clean/
└── shared/
    └── cleaner-manifest.json
```

## Recommended workflow

For any machine where the Adobe environment matters:

```text
1. Backup
2. Verify the backup exists
3. Diagnose / preview
4. Perform repair or cleanup only if needed
5. Restore after reinstalling or migrating
```

## License

MIT. See [LICENSE](LICENSE).

---

If this toolkit saves you time when migrating, repairing, or rebuilding an Adobe setup, consider giving the repository a ⭐.
