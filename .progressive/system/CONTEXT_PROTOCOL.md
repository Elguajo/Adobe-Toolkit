# Context Protocol

Use the smallest evidence set that can preserve correctness.

Normal product work may use `python3 .progressive/tools/context_compile.py` to deterministically assemble a compact bundle from Brief, Architecture, Roadmap, current Phase, the immediate predecessor's `Completion Record` when present, and optional `CONTEXT_MANIFEST.json` hints. The compiler output is disposable; canonical files remain source of truth.

The previous-phase bridge is deliberately narrow: include only `## Completion Record`, never the full completed phase by default. Older completed phases remain retrievable when current evidence, an ADR, a regression, or an explicit historical dependency requires them.

Do not automatically read full completed phases, every ADR, all system docs, LINEAGE, migration evidence, eval corpora, or every installed Skill/tool adapter. Load a Skill/protocol/integration adapter only when its trigger matches.

Manifest hints are not authority over code reality. If a required path is stale/missing, report it and ground in repository evidence rather than hallucinating.

## Resume integrity

`NEXT_SESSION.md` is a navigation pointer, not authority over current project state. On a
cold-start continuation, first read the normal Default Read Set, resolve the current phase from
the Roadmap, then reconcile the handoff target against the current Phase, live worktree/repository
evidence, and only the verification or blocker evidence that determines whether the target remains
open. Continue it when those sources agree; when they contradict it, update the handoff from the
canonical/live state and select the nearest unresolved target instead.

This reconciliation is deliberately narrow: do not replay completed work merely to verify it from
scratch, and do not warm up full completed phases, completion reports, or chat/transcript history
unless the contradiction creates a specific historical ambiguity that those sources can resolve.
