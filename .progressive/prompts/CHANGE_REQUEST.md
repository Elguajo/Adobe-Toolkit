# Change Request

Before materially expanding durable specifications, apply the smallest sufficient task planning depth from `.progressive/system/PLANNING_DEPTH.md`: `DIRECT`, `FOCUSED`, or `FULL`. Re-evaluate depth from the change's uncertainty, architectural reach, risk, reversibility, and contract impact; do not assume the project's original depth applies to every later change.

Classify whether the request changes only implementation, current-phase acceptance,
roadmap, architecture/security/data/public contracts, or the project's domain semantics. Update only canonical owners. When the change introduces, removes, or materially redefines an ambiguity-bearing domain term, apply `.progressive/system/UBIQUITOUS_LANGUAGE.md` and update the Project Brief's `## Ubiquitous Language`; do not create a separate glossary or silently redefine the term inside implementation/phase files.
For a completed project, normally add a new phase rather than rewriting completed history.
Load decision/security skills when triggered; implement after project state is coherent.

`DIRECT` implementation-only changes should not create speculative durable documentation. `FULL` deepens only the planning, decisions, research, readiness, or security analysis materially required by the change. Planning depth never bypasses required approval, acceptance, validation, or durable canonical updates.
