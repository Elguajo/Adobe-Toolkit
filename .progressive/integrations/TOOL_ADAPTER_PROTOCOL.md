# Tool Adapter Protocol

Progressive Context treats branded development tools as **replaceable implementations behind stable capabilities**. Project truth, workflow state, acceptance criteria, and correctness must never depend on one vendor being installed.

## Core rule

> Stable capability, replaceable adapter.

`.progressive/integrations/TOOL_REGISTRY.json` is the machine-readable adapter registry. Do not create a second registry or duplicate tool-routing truth elsewhere.

Every adapter entry must declare:

- `brand` — human-readable implementation name;
- `capability` — stable capability supplied by the adapter;
- `preferred_for` — concrete task conditions where this adapter materially helps;
- `avoid_when` — conditions where native tools, another capability, or no extra tool is preferable;
- `official` — current primary/official source used to verify setup guidance;
- `probe_commands` — safe local detection commands when such probes exist; an empty list is valid;
- `fallback` — usable degraded path when the adapter is absent, declined, unavailable, or fails;
- `profiles` — Progressive tooling profiles that may select this adapter;
- `extra_approval_required_for` — adapter-specific actions that need approval beyond the registry-wide defaults; an empty list is valid.

Registry-wide `adapter_defaults` own common policy such as current-official installation guidance, on-demand context loading, material-use invocation, and approval for installation or user/global configuration. Do not repeat those defaults in every adapter.

## Selection and replacement

Route by **capability and task evidence first**, brand second. A preferred brand is not a project dependency. Another implementation may replace it when it provides the same needed capability and respects equivalent safety, approval, fallback, and validation boundaries.

When adding or replacing an adapter:

1. identify the stable capability;
2. state when the adapter helps and when it should not be used;
3. provide a safe fallback that keeps project work possible without the adapter;
4. link the current official source instead of embedding stale install commands as durable truth;
5. declare any extra approval-sensitive behavior;
6. keep the adapter on demand — **installed does not mean loaded or invoked**;
7. validate the registry with `python3 .progressive/tools/tool_adapter_protocol.py`.

## Context and execution cost

Do not assign invented universal token or runtime costs to an adapter. Use the registry-wide cost policy instead:

- load adapter/tool detail only when the task routes to that capability;
- invoke only when expected benefit is material;
- prefer the smallest sufficient output/evidence surface;
- if a tool produces noisy or lossy output, fall back or widen only as correctness requires.

Measured tool-specific cost claims belong in evaluation evidence, not in this protocol unless supported by reproducible measurements.

## Boundaries

- Tool adapters do not own Brief, Architecture, Roadmap, Phase, handoff, or acceptance truth.
- Adapter absence never justifies skipping required engineering, security, acceptance, or validation work.
- Installation/configuration guidance must be re-verified against the current official source when needed.
- User/global configuration, installation, hooks, credentials, or similarly sensitive changes remain approval-gated according to existing Progressive policy.
- Project Runtime carries this protocol and registry on demand; it does not make them always-loaded context.
