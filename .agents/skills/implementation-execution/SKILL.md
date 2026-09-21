---
name: implementation-execution
description: Non-trivial implementation after direction is clear, including feature work and complete bug-fix execution.
activation: automatic
requires: [".progressive/system/QUALITY_PROTOCOL.md"]
may_delegate: ["systematic-debugging"]
---

# Implementation Execution

Once direction is clear, implement end-to-end in one cohesive pass. Approval is for the chosen
direction, not incomplete core-logic fragments.

A complete change includes required integration, imports, types, schemas, configuration,
critical edge cases/error handling, backward compatibility unless approved otherwise, and
relevant tests. Leave no debug output, dead code, placeholders, pseudo-code, or unnecessary
dependencies. Follow repository conventions and avoid unrelated changes.

## Testing

Tests follow behavior. Behavior changes and bug fixes require relevant tests when meaningfully
testable. Prefer a regression test reproducing the original defect. Do not add a test framework
for trivial/mechanical work. For substantial functionality, critical behavior, regression-prone
logic, or a growing project, a lightweight development-only framework may be added autonomously
when repository evidence supports it and it does not materially expand scope, complexity,
maintenance, or production dependencies; otherwise route the choice through the decision
workflow. If automated testing is impractical, verify the strongest available evidence and
state the remaining uncertainty.

Before the first execution/build step, when several required runtime, dependency, compiler, or
tool prerequisites are already knowable, check them in one grouped probe instead of discovering
them one failure at a time. Resolve only confirmed missing prerequisites and respect existing
dependency/approval policy; do not install speculative packages or turn a small task into
environment setup. A later probe is justified only by new evidence from the first execution.

Treat polling as a costed execution step. If a command is still running and the harness returns
control, wait in coarse intervals appropriate to expected duration — normally at least 30
seconds for builds/test suites — instead of repeated short polls. Do not send empty/no-op input
only to peek, and do not poll when the execution call already blocks until completion. Poll
sooner only when the command is expected to finish quickly or new evidence makes it useful.

## Task-scoped coordination

When an approved implementation plan contains genuinely independent tasks and the active harness
explicitly permits child work, an isolated task context may be used only when the essential task
context can be captured in a minimal file-based brief. Give the worker the relevant interfaces and
acceptance criteria, and a path for its concise evidence report. Keep task artifacts transient:
they are not canonical project state.

For substantial tasks, independently assess requirement compliance and code quality after fresh
verification. A narrow fix gets a scoped re-review of the finding and its fix; it does not require
repeating a whole-task review without new risk. Batch only independent same-shape microtasks that
share one clear implementation and review surface. Do not mandate a particular worktree,
workspace, ledger, model, or subagent implementation when native project workflow is sufficient.

For bug fixes: root cause → reproduce when practical → smallest complete fix → regression test
when supported → adjacent-behavior verification. Use `systematic-debugging` when cause is
unclear rather than guessing.

After implementation, apply `.progressive/system/QUALITY_PROTOCOL.md` exactly. Do not mark work complete
before required evidence is reconciled with acceptance criteria.
