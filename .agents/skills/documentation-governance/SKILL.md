---
name: documentation-governance
description: Material edits to durable governance, architecture, ownership, project-policy, or decision documentation.
activation: automatic
---

# Documentation Governance

Keep implementation-coupled documentation accurate without creating an approval gate.

Update automatically when required by the approved implementation:
- README usage/setup affected by the change;
- API examples and configuration docs;
- narrowly affected developer docs;
- comments and docstrings.

Stop and ask before materially changing durable governance or project-policy documents unless
the user explicitly requested that document:
- `AGENTS.md` / `AGENTS.override.md`;
- architecture or ownership policy;
- project-wide process rules;
- durable planning/decision logs such as `TASKS.md`, `AI_CHANGELOG.md`, or equivalent.

Before asking, state what should change, why, what implementation/validation already occurred,
and whether the update is required or recommended. An explicit request to edit a named durable
document is approval within that scope; ask again only if the edit materially exceeds it.

After approval, update only the canonical owner of each fact/rule. Reference other docs instead
of duplicating project truth.
