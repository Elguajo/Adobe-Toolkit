# Quality Protocol

Use after implementation and whenever completion claims depend on verification.

## Validation order

Validate from narrowest to broadest, skipping only checks irrelevant to the change:
1. targeted tests / focused reproduction;
2. type check or equivalent static checks;
3. lint and formatting checks;
4. build / compile / package;
5. broader suites when shared code or public interfaces changed;
6. e2e/manual/runtime verification when required by the behavior.

## Review evidence

When a change warrants independent review, check requirement compliance separately from code
quality. Requirement compliance verifies the acceptance criteria and scope against the actual
diff/evidence; code quality evaluates correctness, regression safety, maintainability, and tests.
After a narrow fix, use a scoped re-review of the original finding and the fix unless new evidence
widens the risk. These checks complement, rather than replace, the validation order above.

## Convergence

Required evidence is the applicable validation above plus the current acceptance criteria.
Once those checks pass and no new material uncertainty remains, stop validating: do not add
redundant re-runs, extra harnesses, or broader checks only for reassurance. Convergence never
justifies skipping a required check, acceptance criterion, security gate, or relevant
regression test.

## On failure

Classify each relevant failure as **caused by the change**, **pre-existing**, or
**environmental**. Fix what the change broke, re-run the relevant checks, and do not stop at
the first failure when a safe diagnosable fix is in scope. Do not silently "fix" unrelated
pre-existing failures. When repeated failure indicates the current hypothesis or approach is
wrong, route to `systematic-debugging` rather than continuing symptom patches.

## If validation cannot run

State all four explicitly:
- the exact reason it could not run;
- what was inspected or verified instead;
- the exact command/check the user should run;
- the remaining uncertainty.

A validation claim is supported only by evidence actually observed in the current work.
Never report a check as passed unless it actually ran and passed.
