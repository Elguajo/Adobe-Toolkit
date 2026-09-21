# Project Brief — Adobe Environment Toolkit

## Outcome

Provide reliable, cross-platform tools to back up, restore, diagnose, and clean an Adobe Creative Cloud environment while keeping destructive actions explicit, previewable, and verifiable.

## Users and jobs

- Primary user: a macOS or Windows Adobe user preparing to migrate, reinstall, repair, or remove leftovers.
- Core jobs: preserve custom settings/extensions; restore them without deleting unrelated files; inspect an Adobe environment; preview cleanup before applying it.

## Must-have scope

- Maintain the current macOS and Windows CLI entry points and backup workflows.
- Keep cleanup targets in the shared manifest and require preview/confirmation before destructive cleanup.
- Preserve safe-copy restore as the default.
- Build native desktop GUIs in `gui/adobe-toolkit/`: SwiftUI for macOS first, then WinUI for Windows, without duplicating backend behavior or changing existing Terminal workflows.

## Explicit constraints

- No new Adobe applications, cleanup paths, telemetry, cloud backup, credential/license cleanup, or registry cleanup without a separately approved scope change.
- Destructive operations must follow detect → validate → preview → confirm → apply → verify → report.
- GUI v1 must not request elevated privileges. A later privilege design may start only after explicit user authorization and must never collect or pass passwords.
- The macOS GUI supports macOS 12 Monterey and later.
- Prefer compact, task-routed project context over broad repository warm-up.

## Material assumptions

- macOS ships the OS tools used by the existing scripts; missing tools are reported rather than silently bypassed.
- Windows backend hardening and CI remain separate work; Windows GUI parity follows the macOS GUI after macOS acceptance evidence exists.

## Ubiquitous Language

- Safe copy — the default restore mode that copies backup content without deleting unrelated destination files. Source: `macos/AdobeBackuper.command`.
- Full Cleanup — removal only of paths defined by the toolkit manifest; it is not an Adobe Creative Cloud Cleaner Tool equivalent. Source: `README.md`.
- Dry run — planning/validation that does not change user or system state. Source: `README.md`.

## Out of scope — current phase

- Implementing privileged GUI operations before the user explicitly authorizes that scope.
- Replacing the existing CLI scripts or changing Windows behavior.
- Installing optional agent tools or configuring user-global agent settings.

## Success criteria

- A new agent can resume work from a compact default read set and identify one current phase.
- The active phase specifies a safe, implementation-ready direction for the macOS-native GUI and a contract boundary that the later Windows UI can share.
- Existing CLI behavior and tests remain the source of truth while GUI work is planned.

## Classification

- Planning depth: FULL
- Complexity: M
- Risk: High for destructive-cleanup privilege flow; otherwise Medium
