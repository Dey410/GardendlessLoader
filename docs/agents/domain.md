# Domain Docs

Engineering skills should consume this repository’s domain documentation before exploring related code.

## Before exploring, read these

- `CONTEXT.md` at the repository root.
- Relevant ADRs under `docs/adr/`.

If these files do not exist, proceed silently. Domain-modeling workflows create them lazily when terminology or decisions are resolved.

## File structure

This is a single-context repository:

/
├── CONTEXT.md
├── docs/adr/
└── lib/

## Use the glossary’s vocabulary

Use terms defined in `CONTEXT.md` when naming domain concepts in issues, proposals, tests, and implementation work. Avoid drifting to synonyms the glossary explicitly rejects.

## Flag ADR conflicts

Explicitly identify output that conflicts with an existing ADR instead of silently overriding the recorded decision.
