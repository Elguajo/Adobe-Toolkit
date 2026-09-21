# Handoff Protocol

Classify the session `IN PROGRESS`, `PHASE COMPLETE`, or `PROJECT COMPLETE`.
Roadmap stays canonical for phase status.

## Phase completion transaction

When a phase satisfies its acceptance criteria:

1. update Architecture/ADR/other canonical owners first when system shape or a consequential decision changed;
2. write the durable phase report under `.progressive/completions/<phase-name>.md` using `.progressive/templates/PHASE_COMPLETION.template.md`;
3. persist a compact `## Completion Record` in the completed phase **before moving the Roadmap marker**. It should point to the final report and keep only the small cross-phase bridge needed for progressive context;
4. mark the completed phase `[x]` and exactly one next phase `[>]` when one exists;
5. overwrite `NEXT_SESSION.md` in place with only the hot state needed to continue.

The phase completion report is durable human-readable history. Capture evidence-bounded detail that would otherwise bloat hot context:
- **Outcome / Delivered** — capabilities and artifacts that now exist;
- **Implementation notes** — durable technical facts worth preserving, not a diff diary;
- **Decisions made** — consequences plus ADR/canonical references when applicable;
- **Deviations / technical debt** — gaps surviving completion;
- **Problems discovered** — durable issues/workarounds worth remembering;
- **Verification evidence** — checks actually observed and results;
- **Architectural impact / Follow-up** — what later phases may rely on and explicit later work.

A Completion Record remains compact durable routing history. Capture only:
- **Status / Completed** — completion state/date when useful;
- **Final report** — relative path to the phase completion report when one exists;
- **Outcome** — one concise result;
- **Validation summary** — only the evidence needed to trust the transition;
- **Decisions / Technical Debt affecting later phases** — concise consequences;
- **Handoff to Next Phase** — assumptions/capabilities the next phase may safely rely on.

Do not duplicate the full completion report inside the Completion Record. Normal warm-up reads only the compact Completion Record; the detailed report is read on demand when investigation, audit, or historical context requires it.

Backward compatibility: completed phases created before phase completion reports existed remain valid with only their existing `## Completion Record`. Do not force migrations merely to satisfy the new convention. Add a report retroactively only when its durable detail is materially useful.

For non-trivial tasks inside an active phase, keep a compact Task Completion note in the phase file when the result/evidence/decision matters later. Do not create one completion file per routine task.

If the session remains `IN PROGRESS`, keep the phase active and do not fabricate a phase completion report or completion record.

On project completion every phase is `[x]` and none is `[>]`.

## Safe pause transaction

A safe pause is an `IN PROGRESS` handoff, never a fourth session outcome. Before pausing, finish
the current atomic unit or return it to a known recoverable state; do not begin another queued
unit. Record only facts actually present on disk or in canonical project state, verification
actually observed, and one of these working states:

- `RUNNABLE / GREEN`;
- `KNOWN BROKEN / RECOVERABLE` with the exact observed issue and first recovery action; or
- `BLOCKED` with the exact external dependency or decision.

For either non-runnable state, use these exact `NEXT_SESSION` fields so a Runtime Audit can catch
a dangerous false handoff: `- Why: <non-empty fact>` and `- First recovery action: <one concrete
action>`. This lint checks declared state only; it does not decide whether an agent's semantic
claim of completion is true.

Persist an Architecture, current-Phase, or ADR update only when its canonical fact actually
changed. Then overwrite `NEXT_SESSION.md` with one resume target and its first concrete action.
Do not fabricate a completion record/report, create another durable execution ledger, or require
a WIP Git commit: Git may help where a project convention already uses it, but safe pause also
works without Git.

## NEXT_SESSION semantics

`NEXT_SESSION.md` is volatile hot navigation, not project history. Overwrite it on each meaningful handoff; do not create an accumulating chain of `NEXT_SESSION_001.md`, `NEXT_SESSION_002.md`, etc. It contains only current phase, completed work from the just-ended session, verification, blockers/uncertainty, next action, and a ready-to-copy prompt. Durable completed-phase detail belongs in `.progressive/completions/`; the phase keeps only its compact Completion Record; full source history remains in version control when available.

On resume, treat that handoff as a pointer. Reconcile its target with the Roadmap/current Phase,
the live worktree/repository, and the evidence that establishes whether the target or blocker is
still open before acting. A stale handoff must not override canonical state. This is a bounded
check, not a request to reconstruct work from chat history or re-audit completed work.

### Single-focus continuation

One handoff prompt = one unresolved execution target.

Select the nearest unfinished target from canonical project state in this order:

1. unresolved blocker, manual verification, acceptance criterion, or other gate on the current work;
2. otherwise, the unfinished current task;
3. only after that target is complete and its evidence/state is persisted, the next task may become the new target;
4. only after the phase completion transaction is complete may work from the next phase become the new target.

If a current target is unresolved, `## Next action` and `## NEXT SESSION PROMPT` must focus only on closing it. Do not name, describe, preview, or preload later queued tasks or phases in the handoff prompt. In particular, do not write transitions such as `then continue Task N+1`, `after that start ...`, or equivalent wording while the current target remains open.

Several concrete substeps are allowed only when they share one acceptance boundary and are all necessary to finish the same target, for example `apply fix → run targeted verification → persist evidence`. That is still one execution target. `finish current task → start next task` is two targets and must be split across state transitions.

Once the current target is genuinely complete and evidence is persisted, normal workflow may select the next target from the Phase/Roadmap. The previous handoff must not pre-plan or bundle that future target merely because it is already visible in canonical planning documents.
