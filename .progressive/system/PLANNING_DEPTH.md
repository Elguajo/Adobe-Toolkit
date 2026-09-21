# Adaptive Planning Depth

Use the **smallest sufficient planning depth** for the work. Planning depth controls how much durable specification is created or expanded before implementation; it never weakens correctness, safety, acceptance criteria, required validation, or project-state integrity.

Planning depth is independent from simple size labels such as `S / M / L`. Choose it from the combination of uncertainty, architectural reach, risk, reversibility, and contract impact.

## DIRECT

Use when the desired outcome is clear, the change is local or narrowly bounded, the approach is already established, and the work is low-risk and easily reversible.

- Reuse existing architecture and repository conventions; do not create speculative architecture analysis.
- For an existing project, update durable project state only when the change materially affects an existing canonical owner.
- For a new project, keep the canonical skeleton minimal: compact Brief, one Roadmap phase, and a compact current Phase. Populate Architecture only with decisions/boundaries that are actually needed; otherwise record that no material architecture decision is required yet.
- Omit optional sections, ADRs, extra phases, research, and readiness work unless evidence makes them necessary.

Typical examples: a small utility, a clear local feature, a bounded refactor, or a straightforward bug fix with an established pattern.

## FOCUSED

Use as the default for normal product work when implementation spans multiple files/components or needs meaningful planning, but major architectural uncertainty or high-risk boundaries are absent.

- Maintain Brief, Architecture, Roadmap, and current Phase at the level needed to coordinate implementation.
- Create only necessary phases and only material architecture detail.
- Use ADRs, research, security procedures, or additional planning only when triggered by the actual work.

Typical examples: a normal feature, a small product, a multi-component change, or work with several acceptance criteria but a mostly known architecture.

## FULL

Use when uncertainty, architectural reach, risk, irreversibility, or public/system contract impact makes deeper planning materially useful.

Triggers include one or more of:

- unresolved architecture/technology choices with meaningful trade-offs;
- auth, payments, permissions, secrets, private data, migrations, destructive operations, or other high-risk boundaries;
- public APIs, compatibility guarantees, shared schemas, or externally consumed contracts;
- broad cross-system changes or expensive-to-reverse decisions;
- substantial ambiguity where premature implementation is likely to cause rework.

FULL does not mean "generate every document". It means deepen only the specification, decision records, research, readiness, security analysis, and phased execution that the risk/uncertainty actually requires.

### Risk-first sequencing

For FULL work, and for FOCUSED work with a material unresolved assumption, test an unknown before
building the work that depends on it when that assumption could invalidate architecture or scope
and a narrow research step, prototype, or spike is cheaper than proceeding blindly. Sequence the
work as: critical unknown → narrow evidence → architecture decision when needed → dependent
implementation. Do not create a prototype by default or impose a fixed number of options; DIRECT
work remains lightweight.

## Selection rule

Silently classify planning depth before creating or materially expanding project specifications:

1. If FULL triggers are present, use `FULL` even when the task is small.
2. Otherwise, if the outcome/approach is clear and narrowly bounded, use `DIRECT`.
3. Otherwise use `FOCUSED`.

Escalate depth when new evidence increases uncertainty/risk/reach. De-escalate only when the stronger planning is no longer needed and doing so does not discard already-durable project truth.

## Persistence

Record the selected depth in the Project Brief when initializing a project. For change requests, do not rewrite the project's durable classification just because one task uses a different depth; apply the task-appropriate depth and update canonical owners only when the change materially affects them.
