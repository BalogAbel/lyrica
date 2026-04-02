# Architecture

## System Summary

Lyron Chords uses a monorepo with a Flutter client and a Supabase backend. The product is cloud-first but must remain operational offline for at least one week, so the client is designed as local-first with explicit synchronization. The current executable product slices are a tablet-first ChordPro song reader with authenticated local-first song reads through a repository boundary and a minimal online-only planning read flow for plans, sessions, and song-backed session items.

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

The current Flutter shell intentionally implements only the smallest executable subset of these boundaries. Domain vocabulary, application wiring, offline policy contracts, routing, and presentation are present today; the song-library slice adds a repository contract, a Drift-backed authenticated song-catalog cache, Supabase-backed refresh reads, a ChordPro parser, and reader projection without moving parsing into the backend. The first planning slice adds read-only planning domain models, a Supabase-backed planning repository, and signed-in plan list/detail routes without introducing planning writes or a Drift planning cache.

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
4. The signed-in song-library subtree owns the catalog controller lifetime through Riverpod `autoDispose`; when that subtree unmounts, periodic polling stops with it.
5. While the app is foregrounded and the signed-in song-library subtree remains mounted, the controller polls on a fixed 5-minute cadence and manual refresh uses the same guarded refresh path.
6. Only a completed full summary-plus-source refresh replaces the active local snapshot.
7. Supabase applies RLS and function-based authorization on every online refresh.
8. Future write slices will record local mutations in the sync queue with version metadata.
9. MVP conflict handling for writes remains manual and explicit.

For the current planning slice, UI reads visible plan summaries and plan detail directly from Supabase through repository boundaries. Ordering rules and song-backed session expansion are repository-owned, while authorization remains fully backend-enforced through Supabase Auth identity and Postgres RLS.
Planning reads are organization-scoped for the signed-in member's visible organizations, while planning writes remain capability-based backend RBAC decisions. This keeps the current read slice simple without collapsing the longer-term authorization model into the Flutter client.

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
- Online-only planning reads through repository boundaries for the current planning slice
- Durable sync queue in Drift for later write slices
- Manual conflict resolution in MVP
- Explicit sync status on offline-managed records
- Web support uses the same domain/application contracts, with the current reader cache backed by Drift wasm and a versioned `sqlite3.wasm` runtime asset, but authenticated offline relaunch remains a native-first manual-validation acceptance path rather than a browser-hard requirement in this slice

The current reader cache keeps only one active authenticated catalog snapshot per user for the currently active organization. It does not retain a historical local snapshot archive or parallel retained organization catalogs, and it removes cached authenticated access on explicit sign-out. The automated verification path proves persistent cache reopen behavior; true offline relaunch acceptance remains a native manual-validation concern.
The current planning slice does not introduce a local planning cache or offline planning projection yet; plan list and detail reads remain online-only behind the planning repository boundary.

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
