---
name: architecture-decision
description: Material architecture/technology fork with genuinely different strategies.
activation: automatic
---

# Architecture Decision

Use only for Decision-worthy work after task classification. Silently weigh architecture,
correctness, effort, testing, security, compatibility, reversibility, maintenance, and product
impact. Do not expose full internal analysis.

Present:

**Diagnosis:** core problem, key repository constraint, and main risk in 1–3 sentences.

**Options:** list all materially different viable strategies worth considering as **A**, **B**,
**C**, etc. Use no fixed count and never invent filler. Render as a bullet list; start each
bullet with the label and a short name in bold, separated by an em dash (e.g. **A — Fast:**),
followed by concise prose — not a nested sub-bullet per attribute. Cover scope, effort, main
risk/limitation, maintenance impact, and compatibility when appropriate, compressed into one to
two flowing sentences per option. Wrap package names, file paths, flags, and other technical
identifiers in inline code spans.

**My Recommendation:** choose exactly one option based on repository maturity, risk,
reversibility, product impact, and maintenance cost.

Ask: **“Which path should I implement? Choose an option above, or describe your own direction.”**
Then stop. Do not implement until direction is chosen unless classification already exempts the
task (Directed/Trivial).

A custom user direction overrides the recommendation unless it creates material security,
integrity, compatibility, data-loss, operational, or irreversible risk; then name the risk,
offer the nearest safe alternative, and confirm only the material decision.

## Pivot rule

- Core strategy rejected → abandon it and return to viable alternatives.
- Local detail rejected → preserve approved architecture and revise that detail.
- Never pile compatibility patches onto a fundamentally rejected strategy.

Create an ADR only for a consequential, hard-to-reverse decision future maintainers need.
