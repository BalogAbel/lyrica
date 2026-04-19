# Architecture

## System Summary

Lyron Chords uses a monorepo with a Flutter client and a Supabase backend. The product is cloud-first but must remain operational offline for at least one week, so the client is designed as local-first with explicit synchronization. The current executable product slices are a tablet-first ChordPro song reader with authenticated local-first song reads through a repository boundary and a local-first planning read flow for plans, sessions, song-backed session items, and plan-origin reader context scoped to the active organization.

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

The current Flutter shell intentionally implements only the smallest executable subset of these boundaries. Domain vocabulary, application wiring, offline policy contracts, routing, and presentation are present today; the song-library slice adds a repository contract, a Drift-backed authenticated song-catalog cache, Supabase-backed refresh reads, a ChordPro parser, and reader projection without moving parsing into the backend. The current planning slice adds a Drift-backed normalized planning projection for reads, a separate persisted planning mutation store for local writes, a Supabase-backed full-refresh path, a planning write sync controller, and signed-in plan list/detail routes with dialog-based local plan/session editing. That local-first planning write boundary now covers plan create/edit, session create/rename/delete/reorder, and song-backed session-item add/delete/reorder while keeping the projection and mutation store separate. The slug-routing slice adds route-bound slug resolution at the navigation edge, but repositories, local projections, and reader context remain id-based after resolution.

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
8. Future write slices will record local mutations in the sync queue with version metadata and backend-authorized capability checks.
9. MVP conflict handling for writes remains manual and explicit.

For the current planning slice, UI reads plan summaries and plan detail from a repository-owned merged local-first planning view. The repository combines the last synchronized Drift planning projection with the persisted planning mutation store for the active organization. A planning sync controller eagerly refreshes the full visible planning model for the active organization from Supabase, atomically replaces the local projection on success, preserves the previous local projection when refresh fails, clears authenticated planning data on explicit sign-out and session expiry, and discards stale refresh completions after organization-boundary changes. Session-expiry cleanup is guarded by auth-generation ownership so stale cleanup work cannot delete data restored by a newer signed-in generation. A separate planning mutation sync controller emits backend write RPCs in repository-owned mutation order, classifies failed authorization, dependency, remote-missing, conflict, and connectivity outcomes, and supports explicit retry of failed mutations without moving authorization or optimistic-concurrency ownership into Flutter. Plan-scoped session reorder captures plan `base_version`, while session-item add/delete/reorder capture session `base_version`; both mutation families remain local-first in the merged read path, compact redundant collection edits in the mutation store, and preserve dependency ordering relative to parent pending creates. When a write RPC succeeds but the immediate full refresh still fails, the accepted canonical plan, session, or session-item data is reconciled directly into the local projection before the mutation row is cleared so the successful write does not disappear locally, but only if the same active planning boundary still owns that projection. Cached-organization fallback is limited to signed-in cold-start recovery when no current planning boundary exists yet; once an active planning boundary is established in memory, transient organization-resolution failures keep that boundary until a new explicit organization boundary is observed. Ordering rules, provisional slug overlay, and song-backed session expansion remain repository-owned, while authorization remains fully backend-enforced through Supabase Auth identity and Postgres RLS.
Planning reads and planning writes are active-organization-scoped for the signed-in member's visible organizations, while write authorization, canonical slug allocation, and optimistic concurrency remain backend-owned RBAC decisions. This keeps the slice local-first without collapsing the longer-term authorization model into the Flutter client.

For the slug-routing slice, route entry points resolve public slugs against the already-available planning and song read models before instantiating the existing id-based screens. Missing slug matches surface explicit not-found UI instead of falling through to an arbitrary entity, and scoped reader routes continue to pass `planId`, `sessionId`, `sessionItemId`, and `songId` internally once resolution succeeds. The public scoped reader URL is `/plans/:planSlug/sessions/:sessionSlug/items/songs/:songSlug`, which relies on the product rule that a song can appear at most once within a session; route resolution maps that `songSlug` to the single matching session item before the reader screen mounts. When a canonical song slug is not yet available at the presentation boundary, the UI keeps the slug-based navigation disabled rather than generating an id-based public URL.

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
- Active-organization-scoped local planning projection in Drift for the current planning slice
- Durable sync queue in Drift for later write slices
- Manual conflict resolution in MVP
- Explicit sync status on offline-managed records
- Web support uses the same domain/application contracts, with the current reader cache backed by Drift wasm and a versioned `sqlite3.wasm` runtime asset, but authenticated offline relaunch remains a native-first manual-validation acceptance path rather than a browser-hard requirement in this slice

The current reader cache keeps only one active authenticated catalog snapshot per user for the currently active organization. It does not retain a historical local snapshot archive or parallel retained organization catalogs, and it removes cached authenticated access on explicit sign-out. The automated verification path proves persistent cache reopen behavior; true offline relaunch acceptance remains a native manual-validation concern.
The current planning slice keeps one authenticated planning projection plus one authenticated planning mutation set per user for the active organization, purges the previous active organization data when the active organization changes, removes authenticated planning access on explicit sign-out and session expiry, and preserves backend-accepted writes locally if the immediate post-write full refresh fails. The automated verification path proves persistent planning-cache reopen behavior, persisted local planning writes across reopen, offline reuse after refresh failure, mutation cleanup on explicit sign-out, and local-first session/session-item collection edits against the same projection-plus-mutation boundary.
The song CRUD slice keeps authorization backend-enforced through Supabase capability helpers and RLS, hides `pending_delete` rows from normal local reads immediately, and requires explicit user action for conflict overwrites instead of silent last-write-wins retries. The convergence-hardening follow-up keeps the same queue model, but adds durable remote-deletion classification on top of it: update-sourced remote deletion persists as an explicit conflict recovery state, update-sourced `keep mine` recreates the canonical song through a same-id backend write, delete-sourced remote deletion auto-converges as accepted deletion, and planning/session-scoped reader flows preserve planning-owned titles through tombstone-style deleted-song surfaces instead of falling back to a generic not-found state.

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
