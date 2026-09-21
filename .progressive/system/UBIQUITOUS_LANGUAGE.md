# Ubiquitous Language

Use this protocol only when project-specific domain terms would otherwise be ambiguous, repeatedly re-explained, or easy to misuse across sessions.

## Canonical owner

Project-domain vocabulary belongs in the **Project Brief**, under `## Ubiquitous Language`. Do not create a separate project glossary or duplicate the same definitions across Brief, Architecture, phases, Skills, or handoff files.

The Framework human glossary under `docs/human/` explains Progressive terminology; it is not the place for product-domain language.

## When to add a term

Add a term only when at least one is true:

- the project gives a common word a narrower or special meaning;
- an acronym/business/regulatory/domain term is necessary for correct implementation;
- two nearby concepts are easy to confuse;
- the same definition would otherwise be repeated across tasks or sessions;
- stable naming materially improves APIs, schemas, UX copy, tests, or acceptance criteria.

Do not define ordinary programming vocabulary, obvious product nouns, framework terminology, or implementation details that belong in Architecture.

## Entry format

Keep entries compact:

```text
- <Term> — <precise project meaning>. Source: <canonical pointer when useful>
```

A source pointer is optional when the Project Brief itself is the complete owner. Use one when the precise meaning depends on a deeper canonical artifact such as an ADR, public contract, schema, or external authoritative requirement.

## Budget and quality

- Prefer **0–12 terms**. Empty is valid.
- One term should normally be one line.
- If more than 12 terms seem necessary, first remove ordinary vocabulary, merge aliases, or move implementation detail to its proper owner.
- Do not invent definitions to fill the section.
- Prefer one canonical term over multiple synonyms. Record an alias only when the product already uses it and ambiguity would otherwise remain.
- Definitions must be operational enough that two agents should interpret the term the same way.

## Lifecycle

- **New project:** add only terms already material to the product framing. DIRECT may have zero entries.
- **Existing-project adoption:** infer terms only from repository behavior or reliable existing documentation; mark uncertainty explicitly instead of guessing.
- **Change request:** update the section only when the change materially changes domain meaning or introduces/removes an ambiguity-bearing term.
- **Architecture/implementation:** use the canonical term consistently; do not silently redefine it locally.
- **History:** completed phases may preserve historical wording, but current meaning remains owned by the Project Brief.

## Context boundary

The Project Brief is already part of normal project context, so a small domain vocabulary can reduce repeated explanation without adding another read. This protocol itself is on-demand Runtime knowledge and must not be copied into always-loaded routers.
