# Tooling Profiles

Progressive Context Spec Kit is the canonical project workflow. Branded tools are **preferred implementations** behind stable capabilities: keep the concrete advantage of strong tools without making project truth depend on them. Adapter requirements, route boundaries, fallbacks, approval constraints, and replacement rules are canonical in `.progressive/integrations/TOOL_ADAPTER_PROTOCOL.md` + `.progressive/integrations/TOOL_REGISTRY.json`.

## Minimal

```text
Progressive Context Spec Kit + native agent tools
```

Use for Tier S / Low Risk tasks where extra tooling adds little value.

## Recommended — default for production-oriented Tier M/L work

```text
Progressive Context Spec Kit
+ Superpowers
+ Semble
+ Serena
+ RTK
+ gstack
+ Context7
```

Responsibilities:

- **Progressive Context Spec Kit — CORE:** intent, Brief, Architecture, Roadmap, phases, acceptance, context/tool routing, quality gates, handoff.
- **Superpowers — HOW:** implementation/TDD/debug/verification discipline. It may provide a richer procedure; this kit remains the minimum behavior contract and project source of truth.
- **Semble — CODE DISCOVERY:** first route for intent-based discovery / “where is logic X?” in unfamiliar medium/large repos.
- **Serena — SYMBOL / REFACTOR:** known symbol, references, implementations, diagnostics, semantic rename/edit. Do not repeat Semble's broad discovery.
- **RTK — TOOL OUTPUT:** compact supported shell/test/build/git output when filtering preserves critical diagnostics. Global hooks require explicit approval.
- **gstack — CHALLENGE / QA / RELEASE:** selective engineering/design challenge, review, browser QA, release/ship checks. Never a second canonical planner or roadmap.
- **Context7 — FRESH DOCS:** version-sensitive library/API documentation on demand; for security-critical claims, verify primary official docs when needed.

**Installed ≠ loaded ≠ invoked.** A later session may use zero or one of these tools.

## Advanced Spec — conditional

```text
Recommended profile
+ GitHub Spec Kit
```

Enable only when formal deep specification clearly pays for itself: complex payments/auth, multi-tenant isolation, critical migrations, public contracts, or large ambiguous cross-system work. GitHub Spec Kit may deepen a phase but never replaces project Brief/Architecture/Roadmap/handoff.

## Bootstrap policy

```text
Tier S + Low Risk → Minimal unless evidence justifies more
Tier M → Recommended
Tier L / High Risk → Recommended + stronger gates
                    → Advanced Spec only when formal specification adds value
```

If a preferred tool selected for the project is absent or unconfigured, do not silently erase the preference. Use `tooling-bootstrap`: check `.progressive/project/TOOLING_STATUS.json`, verify current official installation guidance, ask once before user/global configuration or installation, verify the result, then persist status. A tiny task must not be blocked solely to install optional tooling.
