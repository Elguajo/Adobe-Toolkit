---
name: systematic-debugging
description: Bug or failure whose root cause is unclear, intermittent, stateful, or cross-boundary.
activation: automatic
---

# Systematic Debugging

Find root cause before patching. Reproduce the failure when practical, or gather the
smallest discriminating evidence. Trace the earliest incorrect state, form a leading
hypothesis, test it, then apply the smallest complete fix. Add a regression test when the
repository supports it and verify adjacent behavior.

Do not mask root causes with retries, broad exception handling, exception swallowing,
state resets, or fallback logic unless technically justified. If evidence disproves the
hypothesis, discard it rather than layering patches around it. If the same check fails twice
for the same underlying reason under the same hypothesis/approach, treat that as evidence
against the approach: choose one materially different hypothesis or corrective path before
another patch-and-retry cycle.
