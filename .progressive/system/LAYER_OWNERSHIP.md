# Layer Ownership

Each durable rule/fact gets one canonical owner.

- Global agent contract → universal engineering behavior, classification, grounding, safety, completion.
- Personal repo router → project context/workflow/tool routing.
- Brief → product outcome/users/scope/constraints/success. Compact project-domain Ubiquitous Language also lives here when materially useful.
- Architecture → current stack/system shape/trust boundaries/operational assumptions.
- Roadmap → phase order/status/current pointer.
- Current Phase → execution tasks/acceptance/verification plus compact task-completion notes when later work needs them.
- Completed Phase `Completion Record` → compact cross-phase bridge and pointer to the final report; remains normal warm-up context.
- Phase Completion Report (`.progressive/completions/`) → detailed durable human-readable result/evidence/implementation notes/debt for one completed phase; read on demand, not normal warm-up.
- `CONTEXT_MANIFEST.json` → optional non-obvious phase-specific context/Skill hints; never duplicate full docs.
- ADR → one consequential decision rationale.
- `TOOL_REGISTRY.json` → preferred branded capability mapping/install policy.
- `TOOLING_STATUS.json` → project-local persisted tooling availability/configuration cache.
- Skill/protocol → conditional detailed procedure.
- NEXT_SESSION → volatile continuation navigation, overwritten in place.
- LINEAGE → framework-maintenance evidence only, never normal task warm-up.

Project-domain vocabulary must not become a parallel glossary layer: current meaning stays in the Brief, while deeper Architecture/ADR/schema/public-contract sources may be referenced rather than copied.

References/routing are allowed; copying the same long policy into multiple always-loaded layers is not.

Backward compatibility: a legacy completed phase whose durable history exists only in its `Completion Record` remains valid. The separate completion-report layer is additive and does not require retroactive migration.

## Agent adapters

Codex Personal uses `global/AGENTS.codex.md`; Claude Personal uses `global/CLAUDE.md`. Both share the same vendor-neutral repository router. Root `CLAUDE.md` imports `@AGENTS.md`; it must not import the Standalone profile directly because Personal Claude already receives universal behavior from `~/.claude/CLAUDE.md`.
