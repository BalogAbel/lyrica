# Architecture

## System Summary

Lyrica uses a monorepo with a Flutter client and a Supabase backend. The product is cloud-first but must remain operational offline for at least one week, so the client is designed as local-first with explicit synchronization. The current executable product slice is a tablet-first ChordPro song reader with authenticated local-first song reads through a repository boundary.

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

The current Flutter shell intentionally implements only the smallest executable subset of these boundaries. Domain vocabulary, application wiring, offline policy contracts, routing, and presentation are present today; the song-library slice adds a repository contract, a Drift-backed authenticated song-catalog cache, Supabase-backed refresh reads, a ChordPro parser, and reader projection without moving parsing into the backend.

### Backend

Supabase provides:

- Authentication identity
- Postgres data store
- Row Level Security
- SQL functions for capability resolution and policy helpers
- Migrations via the repository-managed Supabase CLI wrapper

Authorization is backend-enforced. The Flutter client consumes capability results only for UX affordances.

Backend policy helpers are responsible for:

- deriving organization membership scope from `auth.uid()`
- mapping memberships and roles into capabilities
- preventing cross-organization references through foreign keys and RLS
- keeping membership management rules centralized instead of scattering role checks

## Data Flow

1. UI reads from local Drift-backed projections.
2. For the current authenticated reader slice, UI reads from one active cached full song-catalog snapshot owned by the current authenticated user for the currently active organization.
3. A catalog controller verifies session state when possible and refreshes the full visible catalog from Supabase.
4. Only a completed full summary-plus-source refresh replaces the active local snapshot.
5. Supabase applies RLS and function-based authorization on every online refresh.
6. Future write slices will record local mutations in the sync queue with version metadata.
7. MVP conflict handling for writes remains manual and explicit.

The repository currently documents the broader local-first flow and already ships the first executable read-side subset.
For the current song-reader slice, UI reads song summaries and raw ChordPro source from the active local snapshot and projects them into reader state locally. Authorization stays fully backend-enforced through Supabase Auth identity and Postgres RLS because Supabase remains the session-verification and refresh boundary.

## Multi-Tenancy

- Organization is the top-level tenant boundary.
- Group membership narrows access within an organization.
- Queries and writes must always include organization scoping.
- Cross-table references must preserve organization scope at the database level.
- No client-side bypass of authorization assumptions is allowed.

## Offline Strategy

- Local-first reads by default
- Active authenticated song-catalog snapshot cache in Drift for the current reader slice
- Durable sync queue in Drift for later write slices
- Manual conflict resolution in MVP
- Explicit sync status on offline-managed records
- Web support uses the same domain/application contracts, with the current reader cache backed by Drift wasm and a versioned `sqlite3.wasm` runtime asset, but authenticated offline relaunch remains a native-first guarantee rather than a browser-hard requirement in this slice

The current reader cache keeps only one active authenticated catalog snapshot per user for the currently active organization. It does not retain a historical local snapshot archive or parallel retained organization catalogs, and it removes cached authenticated access on explicit sign-out.

## Simplicity Rules

- Do not expose the raw domain graph directly in basic UX flows.
- Do not expose the raw ChordPro source directly in the reader UI.
- Do not over-engineer sync into CRDTs for the MVP.
- Do not place authorization policy in Flutter.
- Do not treat PDF as editable song source.
- Do not persist reader preferences in the first song-reader slice.
- Do not keep durable workflow knowledge only in tool-specific directories.

## Delivery Constraints

- TDD for implementation behavior
- Green tests before merge
- Documentation updates in the same change as architectural or product decisions
- ADRs for durable technical choices
