# Progressive Context Kit — Personal Repository Router

Universal engineering behavior is supplied by the user-global layer. Standalone composes it; router owns context, workflow/tool routing, project state.

## Context routing

- **Tiny/local task:** target file + nearby evidence/tests only; project docs only when product/architecture constraints matter.
- **Normal product work:** prefer `python3 .progressive/tools/context_compile.py`; otherwise read `.progressive/project/PROJECT_BRIEF.md` → `ARCHITECTURE.md` → `ROADMAP.md` → `NEXT_SESSION.md` when present → `[>]` phase → prior phase's `Completion Record` when present, then only relevant ADR/source/tests/schemas/current docs.
- Never warm up by reading full completed phases, all ADRs, `.progressive/system/*`, `.progressive/system/LINEAGE.md`, full chat history, or large manuals.
- `ROADMAP.md` is canonical for current phase. All `[x]` means new work is a change request.
- If Git is unavailable, continue without treating that as an error.

## Workflow routing

Load only matching Skills/protocols:
- Routed `.agents/...` paths are repository-root-relative: project Skills win; missing is an error, no global fallback. Other global Skills work.
- new product initialization → `project-bootstrap`
- existing repository adoption → `existing-project-adoption`
- missing materially useful preferred tooling → `tooling-bootstrap`
- non-trivial implementation after direction is clear → `implementation-execution`
- material architecture/technology fork → `architecture-decision`
- auth/payments/permissions/secrets/private data/untrusted input/SQL/CSRF/redirects/webhooks/migrations/destructive work → `security-sensitive-change`
- unclear/intermittent/stateful root cause → `systematic-debugging`
- code/diff/PR review or pasted code without a specific question → `code-review`
- material durable-governance documentation edit → `documentation-governance`
- session ending or user-only decision/blocker → `session-handoff`
- unclear/inconsistent project state → `project-doctor`

For implementation completion use `.progressive/system/QUALITY_PROTOCOL.md`. Installed Skills are not warm-up context.

## Preferred tooling

Preferred implementations are explicit: **Semble** for intent/semantic discovery, **Serena** for known-symbol navigation/refactor, **RTK** for compact shell output, **Superpowers** for implementation/TDD/debug discipline, **gstack** for challenge/review/browser QA/release checks, **Context7** for fresh library/API docs, and **GitHub Spec Kit** for optional Advanced Spec Mode. Read `.progressive/integrations/TOOL_REGISTRY.json` / `PROFILES.md` only when selecting, checking, installing, or routing tools.

If a preferred tool is absent and materially useful, use `tooling-bootstrap`: verify current official installation docs, explain the benefit/permissions, and request one focused approval before installing or modifying user/global agent configuration. Do not interrupt a tiny task just to install tooling. Installed ≠ loaded ≠ invoked. One discovery question gets one primary route; a second tool must answer a different question, resolve ambiguity, or be fallback.

## Canonical project state

Brief owns product outcome/scope; Architecture owns system shape/boundaries; Roadmap owns phase order/status; current Phase owns execution/acceptance/verification; completed Phase owns its compact Completion Record; `CONTEXT_MANIFEST.json` owns optional phase hints; ADR owns consequential rationale; NEXT_SESSION is overwriteable hot navigation; `TOOLING_STATUS.json` is tooling cache. Use `.progressive/system/LAYER_OWNERSHIP.md` when placement is ambiguous.
