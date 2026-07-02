# AI Development Workflow

## Objective

Use AI to accelerate delivery while keeping the repository, not the toolchain, as the durable source of truth.

## Required Loop

1. Spec in `docs/specs/`
2. Plan in `docs/plans/`
3. Review any relevant deferred items in `docs/deferred/`
4. Branch from `main`
   Use the Conventional Branch pattern `<type>/<description>`, for example `feat/offline-song-reader` or `chore/update-docs`.
5. Implement
6. Test
7. Document
8. Merge through a pull request

Each step must leave an artifact in the repository when it changes durable project knowledge.

## Rules

- No tool lock-in for critical knowledge.
- Do not rely on tool-local prompts as the only place a decision exists.
- Do not rely on tool-named repository folders as the only durable record of product or architecture decisions.
- If architecture, product scope, testing rules, or workflow changes, update the repository documents in the same change.
- Keep a status note directly under every `docs/specs/` and `docs/plans/` title, and update it whenever a later repository document partially or fully supersedes that artifact.
- Review relevant deferred entries before finalizing a new slice plan, and treat deferred correctness or sync-consistency work as priority when a slice re-enters the same area.
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

## Knowledge-Graph-First Context Gathering

`graphify-out/` is a committed repository artifact (query engine, not a tool-local cache) and is the first stop for codebase context in every phase below, before falling back to a manual file/grep sweep:

- **Spec**: `graphify query "<topic/feature>"` to pull existing architecture and related components before drafting `docs/specs/`.
- **Plan**: `graphify path "<component A>" "<component B>"` to trace dependency/impact paths between the pieces the plan touches.
- **Implementation**: `graphify explain "<Symbol/Module>"` to locate and understand a symbol before opening files; fall back to Explore/Grep only for what the graph doesn't cover (very recent, uncommitted, or non-code content).
- **Review**: `graphify query "what depends on <changed component>"` to check blast radius before/instead of a full-repo scan.
- **Keep it fresh**: run `graphify . --update` after a merge that changes file/module structure, and before starting a spec for a slice touching an area that has drifted since the last graph build. A stale graph gives wrong answers cheaper, which costs more tokens than it saves.

## Library Docs: Context7-First

Before writing or reviewing code against a third-party package (`pub.dev`, Supabase client libs, Flutter/Dart SDK surfaces, CLI tools), resolve and pull docs through the `context7` MCP server instead of relying on training-data memory or a general web search:

- **Spec / Plan**: when a slice depends on a specific package capability or version constraint, `resolve-library-id` then `query-docs` to confirm the API exists and behaves as assumed before it goes in the plan.
- **Implementation**: pull the exact API/config docs for the package version in use before writing code against it, especially for fast-moving deps (Riverpod, Supabase Flutter client, Drift).
- **Review**: when a diff calls an unfamiliar or recently-changed library API, verify signature/behavior via `context7` instead of trusting memory.
- Do not use it for refactoring, business-logic debugging, or code review of this repo's own code — that's `graphify` territory, not `context7`.
