# Architecture

## System Summary

Lyrica uses a monorepo with a Flutter client and a Supabase backend. The product is cloud-first but must remain operational offline for at least one week, so the client is designed as local-first with explicit synchronization.

## Architectural Layers

### Client

Flutter app targeting Android, iOS, and Web from the beginning.

Primary libraries:

- Riverpod for state management and dependency wiring
- go_router for navigation
- Drift for local persistence and sync queue state

Client layers:

- `domain`: entities, value objects, repository contracts, capability vocabulary
- `application`: use cases, orchestration, sync coordination
- `infrastructure`: Supabase adapters, Drift repositories, auth integration
- `offline`: local database, sync queue, conflict handling
- `presentation`: routes, screens, controllers, UX state

The current Flutter shell intentionally implements only the smallest executable subset of these boundaries. Domain vocabulary, application wiring, offline policy contracts, routing, and presentation are present today; concrete infrastructure adapters arrive with the first data-backed feature slice.

### Backend

Supabase provides:

- Authentication identity
- Postgres data store
- Row Level Security
- SQL functions for capability resolution and policy helpers
- Migrations via Supabase CLI

Authorization is backend-enforced. The Flutter client consumes capability results only for UX affordances.

Backend policy helpers are responsible for:

- deriving organization membership scope from `auth.uid()`
- mapping memberships and roles into capabilities
- preventing cross-organization references through foreign keys and RLS
- keeping membership management rules centralized instead of scattering role checks

## Data Flow

1. UI reads from local Drift-backed projections.
2. Application services mutate local state first.
3. Changes are recorded in the sync queue with version metadata.
4. Sync workers push mutations to Supabase when connectivity exists.
5. Supabase applies RLS and function-based authorization.
6. Conflicts are detected via `version` and `base_version`.
7. MVP conflict handling is manual and explicit.

The repository currently documents this flow and keeps the client-side policy surface executable, but it does not yet ship end-user sync execution screens.

## Multi-Tenancy

- Organization is the top-level tenant boundary.
- Group membership narrows access within an organization.
- Queries and writes must always include organization scoping.
- Cross-table references must preserve organization scope at the database level.
- No client-side bypass of authorization assumptions is allowed.

## Offline Strategy

- Local-first reads by default
- Durable sync queue in Drift
- Manual conflict resolution in MVP
- Explicit sync status on offline-managed records
- Web support uses the same domain/application contracts even if storage implementation evolves

Until full Drift tables are introduced, repository docs and client contracts must keep the offline metadata vocabulary stable.

## Simplicity Rules

- Do not expose the raw domain graph directly in basic UX flows.
- Do not over-engineer sync into CRDTs for the MVP.
- Do not place authorization policy in Flutter.
- Do not treat PDF as editable song source.
- Do not keep durable workflow knowledge only in tool-specific directories.

## Delivery Constraints

- TDD for implementation behavior
- Green tests before merge
- Documentation updates in the same change as architectural or product decisions
- ADRs for durable technical choices
