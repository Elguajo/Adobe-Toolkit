# Start New Project

Use for a new/greenfield product idea. Existing product repositories must use `ADOPT_EXISTING_PROJECT.md`.

Before creating or expanding project specifications, use the smallest sufficient planning depth from `.progressive/system/PLANNING_DEPTH.md`: `DIRECT`, `FOCUSED`, or `FULL`. Select it from uncertainty, architectural reach, risk, reversibility, and contract impact — not project size alone — and record it in the Project Brief.

Then:

1. frame durable product outcome/users/scope/constraints/success in Project Brief at the selected depth; when project-specific domain terms are materially ambiguous or repeatedly needed, use `.progressive/system/UBIQUITOUS_LANGUAGE.md` and keep a compact optional `## Ubiquitous Language` section in the Brief;
2. verify current primary docs only for architecture choices whose freshness matters;
3. choose one pragmatic architecture and record only material decisions/boundaries; in `DIRECT`, do not invent architecture work when repository/default conventions are sufficient;
4. create a Roadmap with exactly one `[>]` phase and only as many phases as the selected depth and actual work require;
5. create phase files without copying Brief/Architecture prose; in `DIRECT`, keep the current Phase compact and omit irrelevant optional sections;
6. add non-obvious context/Skill hints to `CONTEXT_MANIFEST.json` only when useful;
7. classify project Complexity/Risk separately from planning depth and run `tooling-bootstrap` when Recommended/Advanced tooling materially helps;
8. for `FULL`, deepen only the research, ADRs, readiness/security analysis, and phased planning actually triggered by uncertainty/risk/contract impact — never generate documents merely because the mode is FULL;
9. begin the current phase unless blocked by a user-only decision/approval;
10. verify evidence; when a phase completes, persist its Completion Record before advancing the Roadmap;
11. overwrite NEXT_SESSION with compact current-state handoff.

Escalate planning depth if new evidence increases uncertainty, reach, risk, irreversibility, or contract impact. Do not use a lower depth to bypass required architecture, security, approval, acceptance, or validation work.

Ask only when product input is absent or a choice materially belongs to the user.
