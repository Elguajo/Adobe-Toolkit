# Adopt Existing Project

Adopt Progressive Context Spec Kit into an existing repository **without treating it as a blank project**.

1. Inspect Git/worktree state and preserve unrelated edits.
2. Inventory runtime/framework/package manager/dependencies, source layout, tests/CI, DB/schema/migrations, auth/permissions, integrations, deployment/config, existing docs/instructions, and observable product capabilities.
3. Run the framework installer in `--adopt-existing --dry-run` mode from a trusted Framework Source checkout. Review collisions before writing.
4. Install/adopt without deleting existing project files. Preserve pre-existing `AGENTS.md`/`CLAUDE.md` instructions as project-specific material and reconcile conflicts instead of blindly stacking duplicate universal rules.
5. Reconstruct `PROJECT_BRIEF.md` from observed product behavior and reliable existing docs. Mark uncertainty explicitly. When project-specific terminology is materially ambiguous or repeatedly used, apply `.progressive/system/UBIQUITOUS_LANGUAGE.md`: infer only evidence-backed meanings and keep them in the Brief rather than inventing a separate glossary.
6. Document current architecture from repository evidence; keep desired future architecture separate.
7. Reconstruct Roadmap: distinguish already-completed capabilities from remaining work; create exactly one `[>]` phase for the next meaningful outcome.
8. Populate `CONTEXT_MANIFEST.json` only for non-obvious context/Skill hints that improve deterministic routing; do not list every file.
9. Run `tooling-bootstrap` for the selected project tier. Missing materially useful preferred tools should be offered for installation/configuration; tiny optional gaps must not block adoption.
10. Run framework contracts/audit and safe project validation. Classify failures truthfully.
11. Finish with `session-handoff` and a ready next-session prompt.

Do not rewrite the product merely to match the kit. The kit must describe and govern the real repository first.
