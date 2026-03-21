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

### Backend

Supabase provides:

- Authentication identity
- Postgres data store
- Row Level Security
- SQL functions for capability resolution and policy helpers
- Migrations via Supabase CLI

Authorization is backend-enforced. The Flutter client consumes capability results only for UX affordances.

## Data Flow

1. UI reads from local Drift-backed projections.
2. Application services mutate local state first.
3. Changes are recorded in the sync queue with version metadata.
4. Sync workers push mutations to Supabase when connectivity exists.
5. Supabase applies RLS and function-based authorization.
6. Conflicts are detected via `version` and `base_version`.
7. MVP conflict handling is manual and explicit.

## Multi-Tenancy

- Organization is the top-level tenant boundary.
- Group membership narrows access within an organization.
- Queries and writes must always include organization scoping.
- No client-side bypass of authorization assumptions is allowed.

## Offline Strategy

- Local-first reads by default
- Durable sync queue in Drift
- Manual conflict resolution in MVP
- Explicit sync status on offline-managed records
- Web support uses the same domain/application contracts even if storage implementation evolves

## Simplicity Rules

- Do not expose the raw domain graph directly in basic UX flows.
- Do not over-engineer sync into CRDTs for the MVP.
- Do not place authorization policy in Flutter.
- Do not treat PDF as editable song source.

## Delivery Constraints

- TDD for implementation behavior
- Green tests before merge
- Documentation updates in the same change as architectural or product decisions
- ADRs for durable technical choices
