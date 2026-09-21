---
name: code-review
description: Review code, a diff, pull request, or pasted implementation.
activation: automatic
---

# Code Review

Evaluate four dimensions, but report only real findings:
1. **Architecture** — boundaries, coupling, data flow, failure points, security boundaries.
2. **Code quality** — structure, error handling, edge cases, over/under-engineering, technical debt.
3. **Tests** — coverage gaps, weak assertions, untested failures.
4. **Performance** — inefficient I/O, N+1 queries, memory risks, hot paths only when evidence supports them.

For each significant issue provide: what it is; why it matters; 2–3 practical options
(including **do nothing** when reasonable); effort, risk, impact, and maintenance cost;
and one decisive recommendation.

Limit the main review to the top 3–4 significant issues. Mention minor findings in one concise line. Deliver the complete review in one response and end by asking which issues to address.
Never invent filler findings or silently rewrite pasted code.
