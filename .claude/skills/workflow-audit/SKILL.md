---
name: workflow-audit
description: Verify Progressive Context integrity at the appropriate layer without loading framework maintenance evidence into normal product work.
activation: explicit
---

# Workflow Audit

First determine whether the current repository is the **Framework Source** itself or an installed **Project Runtime**.

- In Framework Source, run `python3 .progressive/tools/gate.py`. This is the canonical aggregate verification entrypoint; use individual child validators only to diagnose a failed gate or when the task explicitly targets one validator.
- In Project Runtime, run only the local runtime audit and task-relevant project validation. Do not load migration/evaluation/framework-development evidence because it is intentionally absent from Runtime.

Report actual commands and results. Do not claim a gate passed unless the canonical gate ran and passed. A Framework Source gate pass is static/integrity evidence, not empirical proof that an agent follows Progressive behavior.
