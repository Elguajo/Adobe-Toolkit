# Setup Preferred Tooling

Use only when tooling setup materially improves the project or the selected profile requires it.

1. Read `.progressive/integrations/TOOL_ADAPTER_PROTOCOL.md`, `.progressive/integrations/TOOL_REGISTRY.json`, `.progressive/integrations/PROFILES.md`, and `.progressive/project/TOOLING_STATUS.json`.
2. Determine Tier/Risk from Project Brief/Architecture/current phase; choose Minimal, Recommended, or Advanced Spec profile.
3. Route by the stable capability needed for the task before selecting a preferred brand. Respect each adapter's `preferred_for`, `avoid_when`, documented fallback, and extra approval constraints.
4. Probe what can be safely detected locally and inspect active agent capabilities/configuration without exposing secrets.
5. For each materially useful preferred adapter that is absent/unconfigured, consult its **current official source** before proposing installation. Do not trust stale commands embedded in old docs.
6. Group compatible installation/configuration changes into one concise approval request. Explain user/global files, hooks, credentials/API keys, downloads, or external services involved. Respect registry-wide approval defaults plus any adapter-specific `extra_approval_required_for` entries.
7. After approval, install/configure only the approved tools, verify them, and persist status/evidence/version when available.
8. If declined/unavailable, record `declined`/`degraded` and use the documented fallback. Do not repeatedly ask in every session.
9. Never block a tiny local task merely because optional tooling is absent. Installed does not mean loaded or invoked.
