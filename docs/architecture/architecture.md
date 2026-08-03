# Architecture

## System Summary

Lyron Chords uses a monorepo with a Flutter client and a Supabase backend. The product is online-preferred, offline-safe, and local-first: online availability should improve freshness and collaboration, while the client must remain operational offline for at least one week through local projections, durable local write intent, and explicit synchronization. The current executable product slices are a tablet-first ChordPro song reader with authenticated local-first song reads through a repository boundary and a local-first planning read flow for plans, sessions, song-backed session items, and plan-origin reader context scoped to the active organization.

## Architectural Layers

### Client

Flutter app targeting Android, iOS, and Web from the beginning.

Primary libraries:

- Riverpod for state management and dependency wiring
- go_router for navigation
- Drift for local persistence and sync queue state

Client layers:

- `domain`: entities, value objects, repository contracts, capability vocabulary
- `application`: use cases, orchestration, sync coordination. Riverpod provider
  wiring is organized into domain-scoped files —
  `core_providers.dart` (infra + shared DB lifecycle), `auth_providers.dart`,
  `song_catalog_providers.dart`, `planning_providers.dart` — re-exported through
  a single `providers.dart` barrel so existing import call sites are unaffected
  ([ADR-021](decisions/ADR-021-provider-domain-split.md)). Active-organization
  resolution is owned by a single `ActiveOrganizationResolver` in this layer,
  with the `activeOrganizationResolutionProvider`,
  `membershipResolutionProvider`, and `activeOrganizationReaderProvider` seams
  delegating to it ([ADR-022](decisions/ADR-022-active-organization-resolver.md))
- `infrastructure`: Supabase adapters, Drift repositories, auth integration
- `offline`: local database, sync queue, conflict handling
- `presentation`: routes, screens, controllers, UX state. Each area keeps its
  screen thin and its components in a `widgets/` subdirectory: the screen owns
  state lifecycle, provider resolution and orchestration, while `widgets/` holds
  components that take data and callbacks and can be built directly in a test.
  Behaviour that is neither widget tree nor lifecycle — the reader's immersive
  mode, zoom persistence, song actions, command dispatch and scoped navigation —
  lives in plain classes beside the screen. Extracted components keep the
  provider scope they had (ADR-021 domain-split providers, aggregate-scoped
  planning invalidation) and resolve organization identity only through the
  active-context providers, never by re-deriving an organization id
  ([ADR-022](decisions/ADR-022-active-organization-resolver.md)). Optimistic UI
  state is owned by the widget that owns the interaction producing it, and has an
  explicit end condition
  ([ADR-023](decisions/ADR-023-optimistic-reorder-overlay-lifecycle.md))

The current Flutter shell intentionally implements only the smallest executable subset of these boundaries. Domain vocabulary, application wiring, offline policy contracts, routing, and presentation are present today; the song-library slice adds a repository contract, a Drift-backed authenticated song-catalog cache, Supabase-backed refresh reads, a ChordPro parser, and reader projection without moving parsing into the backend. The current planning slice adds a Drift-backed normalized planning projection for reads, a separate persisted planning mutation store for local writes, a Supabase-backed full-refresh path, a planning write sync controller, and signed-in plan list/detail route surfaces with inline session-name editing and add-song entry points. That local-first planning write boundary now covers plan create/edit, session create/rename/delete/reorder, and song-backed session-item add/delete/reorder while keeping the projection and mutation store separate. Planning mutation rows also retain an origin snapshot of the pre-edit state so rebase, discard, and canonical reconciliation can reason about the current local baseline without exposing raw write churn to presentation code. The slug-routing slice adds route-bound slug resolution at the navigation edge, but repositories, local projections, and reader context remain id-based after resolution.

### Backend

Supabase provides:

- Authentication identity
- Postgres data store
- Row Level Security
- SQL functions for capability resolution and policy helpers
- Migrations via the repository-managed Supabase CLI wrapper

Authorization is backend-enforced. The Flutter client consumes capability results only for UX affordances.

The authentication boundary is split into two concerns: provider-managed identity (Supabase Auth: Google, Apple, magic link) and database-enforced membership (the `invitations` + `memberships` tables and `redeem_invitation` RPC). A Supabase Auth session is necessary but not sufficient to access application data; the client must hold an active membership row obtained through `redeem_invitation`. The Flutter client cannot bypass this gate because the RPC runs as `security definer` in Postgres.

Redemption itself is fully backend-enforced and returns a `jsonb` status envelope (`{"status", "organization_id"}`) rather than raising for business outcomes. It is email-bound when the invitation carries an address — the caller's own confirmed account email must match, case- and whitespace-insensitively — and stays a bearer link when it does not; either way the caller is rate limited (suspicious outcomes only, keyed on `auth.uid()`), and attempts are recorded in `public.invitation_redemption_attempts` with only a token digest retained, never the raw token — with repeats of the same terminal outcome for the same caller and token collapsed to one row per 15-minute window, so the audit trail cannot be inflated by a client loop. See [ADR-025](decisions/ADR-025-invitation-redemption-model.md).

The read boundary stays on RLS-protected table reads: the Flutter
repositories read `songs`, `plans`, and `sessions` directly through the
Supabase table API, with RLS enforcing tenant visibility on every row. There
are zero direct table writes — every mutation goes through a `security
definer` RPC, with RLS denying direct DML as a second layer. See
[ADR-026](decisions/ADR-026-rls-protected-read-boundary.md).

Song writes derive their shadow metadata (`title`, `artist`,
`key_signature`, `tempo_bpm`, `tags`) from canonical `chordpro_source` inside
the `create_song` / `song_write_update_common` `security definer` bodies,
using a small SQL reproduction of the ChordPro directive grammar
(`public.chordpro_scan_directives` and five per-field
`public.chordpro_derive_*` functions). Client-supplied values for those
fields are not accepted as RPC parameters at all; `p_title` is retained only
as a fallback for sources with no title directive. See
[ADR-027](decisions/ADR-027-backend-derived-song-metadata.md).

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
8. The current planning write slice records local mutations in the persisted planning mutation store with version metadata, origin snapshots, and backend-authorized capability checks before sync.
9. MVP conflict handling for writes remains manual and explicit.
10. Online freshness triggers such as foreground/resume, offline-to-online transition, manual sync, periodic refresh, and future subscription invalidation should call the same repository/application refresh and sync paths rather than bypassing local projections.

For the current planning slice, UI reads plan summaries and plan detail from a repository-owned merged local-first planning view. The repository combines the last synchronized Drift planning projection with the persisted planning mutation store for the active organization. A planning sync controller eagerly refreshes the full visible planning model for the active organization from Supabase, atomically replaces the local projection on success, preserves the previous local projection when refresh fails, clears authenticated planning data only on the destructive paths (explicit sign-out and authoritative verified-empty membership revocation), and discards stale refresh completions after organization-boundary changes. Session expiry is non-destructive: it keeps the projection and pending mutations and marks the access offline-authenticated rather than deleting (mirroring the catalog cache); see ADR-020. Destructive cleanup remains guarded by auth-generation ownership so stale cleanup work cannot delete data restored by a newer signed-in generation. A separate planning mutation sync controller employs single-flight coordination to coalesce concurrent sync triggers (manual sync, foreground-resume, offline-to-online transition, discard) into one in-flight run instead of overlapping sends. Mutations are emitted in repository-owned mutation order and the full planning refresh runs once per batch after all sends, not once per mutation. A successfully accepted mutation is durably marked with an `accepted` sync status before the batch refresh and persisted in the free-text mutation sync-status column without schema migration; a crash between backend acceptance and local clear cannot cause a resend because on the next run an already-`accepted` mutation is reconciled into the local projection and cleared rather than re-sent, making sync exactly-once instead of at-least-once. The accepted-mutation reconciliation switch is now an injected, independently testable `PlanningMutationReconciler` unit rather than inline provider logic. Discard and retry of stuck mutations no longer require a successful refresh first; they update local write intent unconditionally and then sync best-effort, so a user can clear or requeue a stuck mutation while offline. The controller classifies failed authorization, dependency, remote-missing, conflict, and connectivity outcomes and supports explicit retry of failed mutations without moving authorization or optimistic-concurrency ownership into Flutter. Retry is not offline-capable — it genuinely needs the backend — and a user-initiated retry now surfaces a connectivity failure to the caller when it cannot run, instead of returning normally with only a changed error code to show for it; background syncing keeps swallowing connectivity failures because finding no network there is routine. Plan-scoped session reorder captures plan `base_version`, while session-item add/delete/reorder capture session `base_version`; both mutation families remain local-first in the merged read path, compact redundant collection edits in the mutation store, and preserve dependency ordering relative to parent pending creates. The merged local-first read overlays all actionable mutations (pending, accepted, failed-authorization, failed-dependency, failed-remote-delete, conflict), not just pending ones, so failed and conflicted edits stay visible for review instead of silently reverting to the last server state; a visible `planEdit` overlay no longer blanks description or scheduledFor when the edit record leaves those fields unset. When a write RPC succeeds but the immediate full refresh still fails, the accepted canonical plan, session, or session-item data is reconciled directly into the local projection before the mutation row is cleared so the successful write does not disappear locally, but only if the same active planning boundary still owns that projection. Cached-organization fallback is limited to signed-in cold-start recovery when no current planning boundary exists yet; once an active planning boundary is established in memory, transient organization-resolution failures keep that boundary until a new explicit organization boundary is observed. Ordering rules, provisional slug overlay, and song-backed session expansion remain repository-owned, while authorization remains fully backend-enforced through Supabase Auth identity and Postgres RLS.

Planning read invalidation uses two Riverpod signals rather than one global counter (ARCH-2, arch-spine-phase0-1). `planningDataRevisionProvider` is the aggregate signal — bumped when the plan set or a plan summary changes, or a full sync/discard reconciles potentially many plans — and is watched by every planning read provider (plan list, plan-by-slug, plan-detail-by-slug, plan detail). `planningMutationRevisionProvider` is a pending-mutation signal bumped by the single write-service sync-scheduler choke point that every local write awaits; it is watched only by the two mutation-facing readers (the mutation entries list and the unsynced-mutations badge), so a within-plan session/item edit no longer rebuilds unrelated plans' details or by-slug summaries. Within-plan edit sites (session create/rename/delete/reorder, session-item add/delete/reorder) rely solely on this mutation bump plus their existing targeted `ref.invalidate` calls for the active plan; only plan-summary edits and aggregate events (sync completion, discard/retry) still bump the aggregate signal directly. The accepted trade-off is that another, currently unopened plan's reconciled fields may lag until its next interaction or the next aggregate refresh.
Planning reads and planning writes are active-organization-scoped for the signed-in member's visible organizations, while write authorization, canonical slug allocation, and optimistic concurrency remain backend-owned RBAC decisions. This keeps the slice local-first without collapsing the longer-term authorization model into the Flutter client.

A unified sync overview view-model now aggregates song catalog, song mutation, planning sync, and planning mutation state into one `UnifiedSyncOverview` snapshot. A header sync control rendered on authenticated non-reader workspaces (song library, song editor, plan list, plan detail) exposes a green `Synced` / yellow `Unsynced` / red `Conflict` aggregate plus a popup listing only non-synced song rows and plan-grouped planning rows with explicit `conflict`, `authorization_denied`, `dependency_blocked`, `remote_missing`, and `sync_failed` reason codes. A `UnifiedManualSyncController` orchestrates song mutation sync, song catalog refresh, planning mutation sync, and planning refresh under one single-flight `syncNow` command shared by the header popup, an offline-to-online transition trigger derived from catalog and planning state, and a foreground-resume listener that uses the existing `AppForegroundState` lifecycle boundary. Reader surfaces never mount the unified header control because they stay focused on reading; sync continues in the background through the same providers. The popup's per-row keep-mine, discard-mine, and apply-to-group recovery actions run on `UnifiedRowRecoveryController`, built the same way as `UnifiedDiscardController`: no stored `Ref`, closures over the provider's own `ref`, each holding `ref.keepAlive()` for the duration of its mutation, its invalidations, and (for apply-to-group) the `planningDataRevisionProvider` bump. The widget keeps only the failure snackbar, shown when it is still mounted; closing the popup mid-operation no longer skips the invalidations that keep other screens' sync state current.

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
- Dropping local write intent (discard) never requires the network, for songs and plans alike, and a discard never leaves a conflict status behind — being conflicted is a sync outcome, not something a user asks for by throwing an edit away. Retry deliberately stays online-only and reports a connectivity failure to the caller when it cannot run, instead of returning as if it had succeeded
- Online freshness triggers refresh local projections instead of becoming direct UI data sources
- Future realtime subscription events are invalidation signals only; missed events must be recoverable through reconnect, foreground refresh, periodic refresh, or manual sync
- Web support uses the same domain/application contracts, with the current reader cache backed by Drift wasm and a versioned `sqlite3.wasm` runtime asset, but authenticated offline relaunch remains a native-first manual-validation acceptance path rather than a browser-hard requirement in this slice

The current reader cache keeps only one active authenticated catalog snapshot per user for the currently active organization. It does not retain a historical local snapshot archive or parallel retained organization catalogs, and it removes cached authenticated access on explicit sign-out. The automated verification path proves persistent cache reopen behavior; true offline relaunch acceptance remains a native manual-validation concern.
Local storage growth is bounded by two policies, not by keeping "one active snapshot": a mutation budget (LF-T3) and a storage-pressure eviction policy (LF-T4), specified together because catalog eviction cannot relieve the mutation budget — pending mutations are never evictable, so the only remedy for a full mutation store is to sync or discard. `BudgetedPlanningMutationStore` measures the planning mutation store's content-derived byte footprint before every write that can grow it and refuses new writes past a hard threshold; storage pressure escalates through eviction of droppable catalog data before it refuses anything. The protection order never evicts pending planning or song mutations, the planning projection (offline it is the only readable view), cached catalog summaries (they back the browsable list), or the last-known identity store (ADR-020); the only thing eviction ever drops is cached catalog **sources** for songs with no pending song mutation, since a song's body is the largest cached payload and is re-fetchable on reconnect. Accounting is derived from row content (SQL `length(...)` over text columns) rather than a platform file-size or quota API, so the same logic runs on native and web; every threshold is verified against the native Drift/sqlite3 backend only, and the web/IndexedDB assumptions behind it remain unverified pending `docs/deferred/2026-06-29-web-offline-e2e.md`. See ADR-028.
The current planning slice keeps one authenticated planning projection plus one authenticated planning mutation set per user for the active organization, purges the previous active organization data when the active organization changes, removes authenticated planning access only on the destructive paths (explicit sign-out and authoritative verified-empty membership revocation), and preserves backend-accepted writes locally if the immediate post-write full refresh fails. The automated verification path proves persistent planning-cache reopen behavior, persisted local planning writes across reopen, offline reuse after refresh failure, mutation cleanup on explicit sign-out, and local-first session/session-item collection edits against the same projection-plus-mutation boundary. Planning mutation persistence also retains origin snapshots for edited rows so the local baseline can be restored or transformed during later sync and discard operations.
Local data access is decoupled from live auth-session validity (ADR-020). `AppAuthStatus.sessionExpired` is a first-class offline-authenticated / re-auth-required state: a previously authenticated user keeps reading cached songs and plans and keeps queueing writes while the session is not live, both for in-session expiry and for offline cold-start relaunch with a dead token. Cold start resolves which user to load from a durable `LastKnownIdentity { userId, email, organizationId, updatedAt }` Drift record written on every successful sign-in; a `null` restored session with a known identity maps to `sessionExpired` (carrying `lastKnownSession`), while `null` with no identity maps to `signedOut`. The router keeps offline-authenticated users in the app (membership resolves via the cached organization id) and surfaces a persistent re-auth banner. Outside the explicitly confirmed different-user path described below, local data and the identity record are wiped only on explicit sign-out and authoritative verified-empty membership revocation, never on connectivity-driven or unknown session loss. While offline, cached data may outlive a server-side revocation by design; authorization stays backend-enforced and converges on reconnect when `verifiedEmptyMembership` fires. The different-user re-auth resolution runs on the live `signedIn` edge (ADR-029): a same-user re-sign-in flushes; a different user with no user-wide pending local work is wiped and proceeds without a prompt; a different user with user-wide pending or unreadable-count work is confirmed first; and cancelling signs the new session out and returns the app to being offline-authenticated as the prior user with nothing deleted. The count and cleanup cover every locally retained organization for the prior user, without claiming an atomic transaction across the song and planning databases. Every signed-in notification synchronously claims a new generation and supersedes any pending prompt before queueing its captured session. Queued work remains current only while that generation and the live signed-in `userId`/`email` still match; currentness is rechecked after waits and immediately before deletion, backend sign-out, identity clear, and identity writes. A failed last-moment check produces the typed `ReauthSuperseded` outcome and no side effect rather than a stale wipe or cancellation. The root `ConsumerStatefulWidget` hosts the prompt through a single Riverpod 2.6 `listenManual(..., fireImmediately: true)` subscription, captures the current value immediately, and presents it post-frame exactly once per stable request id; answers carry that id so an obsolete dialog cannot answer a newer request. A confirmed different-user wipe is a fourth destructive trigger alongside explicit sign-out and authoritative revocation — it is not a relaxation of the non-destructive-on-uncertainty rule above, because it only fires after an explicit confirmation, never from an unknown or connectivity-failed session.
The song CRUD slice keeps authorization backend-enforced through Supabase capability helpers and RLS, hides `pending_delete` rows from normal local reads immediately, and requires explicit user action for conflict overwrites instead of silent last-write-wins retries. The convergence-hardening follow-up keeps the same queue model, but adds durable remote-deletion classification on top of it: update-sourced remote deletion persists as an explicit conflict recovery state, update-sourced `keep mine` recreates the canonical song through a same-id backend write, delete-sourced remote deletion auto-converges as accepted deletion, and planning/session-scoped reader flows preserve planning-owned titles through tombstone-style deleted-song surfaces instead of falling back to a generic not-found state. Discarding a song mutation is local-first, mirroring the planning side: a pending create or a remote-deleted conflict deletes the local song, and any other state (pending update, pending delete, conflict) clears the mutation row so reads fall back to the cached catalog snapshot, which still holds the last known server copy. Neither branch calls the backend, and neither ever writes `SongSyncStatus.conflict` — that status is a sync outcome, not a discard side effect. A best-effort catalog refresh follows the local discard to pick up server freshness; its failure is swallowed and never undoes the completed discard. The accepted trade-off is that discarding a pending **delete** clears the mutation without confirming the song is still live on the server, so if the server copy was in fact deleted and the cached snapshot is stale, the song can reappear locally until the next successful refresh removes it again — a bounded, self-healing window.

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
