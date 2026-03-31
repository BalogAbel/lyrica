# AI Development Workflow

## Objective

Use AI to accelerate delivery while keeping the repository, not the toolchain, as the durable source of truth.

## Required Loop

1. Spec in `docs/specs/`
2. Plan in `docs/plans/`
3. Branch from `main`
   Use the Conventional Branch pattern `<type>/<description>`, for example `feat/offline-song-reader` or `chore/update-docs`.
4. Implement
5. Test
6. Document
7. Merge through a pull request

Each step must leave an artifact in the repository when it changes durable project knowledge.

## Rules

- No tool lock-in for critical knowledge.
- Do not rely on tool-local prompts as the only place a decision exists.
- Do not rely on tool-named repository folders as the only durable record of product or architecture decisions.
- If architecture, product scope, testing rules, or workflow changes, update the repository documents in the same change.
- Keep a status note directly under every `docs/specs/` and `docs/plans/` title, and update it whenever a later repository document partially or fully supersedes that artifact.
- Prefer small commits that preserve traceability between decisions and implementation.
- Do not implement directly on `main`; AI-assisted work must happen on a branch and return through a pull request.
- Name AI-created branches with the Conventional Branch pattern `<type>/<description>` and lowercase, hyphenated descriptions.

## AI Session Expectations

- Start from repository context before implementing.
- Create or switch to a non-`main` branch before editing implementation files, and name it with the Conventional Branch pattern.
- Respect backend-enforced authorization boundaries.
- Prefer TDD for implementation work.
- Verify before claiming completion.
- Treat ADRs and docs as first-class artifacts.
