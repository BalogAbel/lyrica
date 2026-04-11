# Local-First Planning Create/Edit Spec

> Status: Implemented

> This spec extends the local-first planning direction established by [docs/specs/2026-04-03-local-first-planning-read.md](docs/specs/2026-04-03-local-first-planning-read.md). It adds the first local-first planning write slice for plan create/edit and session create/rename/delete while preserving the existing planning read projection and backend-owned authorization boundary.

## Goal

Deliver the first local-first planning write slice for Lyron Chords by allowing users to create and edit plans locally first and to create, rename, and delete sessions locally first, while preserving the existing local-first planning read architecture, backend-owned authorization, and repository-owned synchronization boundaries.

## Problem

The repository already proves local-first planning reads for the active organization:

- the app eagerly refreshes and persists the visible planning read model locally
- plan list, plan detail, ordered sessions, ordered session items, and plan-origin reader context remain readable offline after a successful refresh
- the planning architecture already uses a normalized local projection rather than online-only route fetches

What is still missing is the first executable planning write path. Today, planning remains read-only even though the documented product direction is explicitly local-first. That leaves a practical product gap:

- users can inspect plans offline but cannot prepare or adjust them offline
- the planning architecture has no write-side local state or sync semantics yet
- the repository does not yet define how local user intent should appear in the UI before backend synchronization succeeds

The next slice should close that gap without expanding into full planning editing. It should prove the smallest useful local-first planning mutation workflow that fits the current architecture and preserves room for richer online-coordinated editing later.

## Scope

- Allow users to create plans locally without requiring active connectivity.
- Allow users to edit existing plans locally for these fields only:
  - `name`
  - `description`
  - `scheduled_for`
- Allow users to create sessions locally within a plan.
- Allow users to rename sessions locally by editing the session `name`.
- Allow users to delete sessions locally when the session has no session items.
- Keep new plans in this slice organization-scoped with `group_id = null`.
- Keep the current planning read projection as the repository-owned local read model.
- Add separate persisted local planning mutation state rather than collapsing planning writes into the existing read projection rows.
- Serve planning list and plan detail through merged local-first planning views so the UI immediately reflects the user's latest local changes.
- Keep `session_items` read-only in this slice.
- Keep planning writes scoped to the active organization only.
- Keep authorization and canonical write acceptance backend-owned.
- Include TDD, local verification expectations, and repository documentation updates as part of the slice.

## Non-Goals

- No session item create, edit, delete, reorder, or drag-and-drop behavior.
- No plan delete flow in this slice.
- No session reorder flow in this slice.
- No editing of `group_id`, plan slug, or session slug in this slice.
- No mixed session item type editing.
- No multi-organization offline planning write archive.
- No background mutation sync requirement while the app is suspended or terminated.
- No lock acquisition, collaborative presence, or realtime multi-user editing in this slice.
- No silent client-owned authorization fallback when backend policy or visibility changes.
- No requirement to solve the full planning workflow beyond plan create/edit and session create/rename/delete.

## Product Slice Summary

This slice should prove one narrow but complete local-first planning write claim:

1. a signed-in user opens planning for the active organization
2. the user creates or edits a plan locally, or creates, renames, or deletes an eligible session locally
3. the UI immediately reflects that local change
4. the local change remains visible and usable offline
5. backend synchronization later accepts, rejects, or conflicts with that local change through repository-owned sync behavior
6. authorization remains owned by Supabase Auth identity and Postgres policy enforcement rather than by Flutter

This slice intentionally does not attempt to solve all planning editing. It proves the first coherent write-side path on top of the existing local-first planning read model.

## Current Architectural Context

The repository already establishes these relevant constraints:

- planning reads are local-first for the active organization through a normalized Drift-backed planning projection
- plan list, plan detail, sessions, session items, and plan-origin reader context are reconstructed from that local projection
- the projection is scoped to the authenticated user plus active organization boundary
- explicit sign-out clears authenticated planning access
- planning authorization remains backend-enforced

This slice must preserve those constraints rather than replacing them with a new planning architecture.

## Core Product Rules

- The user-visible planning UI must always show the user's latest local planning changes, even before backend synchronization completes.
- The UI must not require connectivity to keep showing a locally created or locally edited plan or session once the local mutation has been recorded.
- Planning reads remain repository-owned local-first views, not presentation-owned ad hoc caches.
- Planning writes in this slice are limited to `plan create/edit` and `session create/rename/delete`.
- New plans created in this slice are organization-scoped only and therefore use `group_id = null`.
- `session_items` remain unchanged by this slice and continue to come from the planning read projection.
- Backend synchronization remains the only source of canonical authorization and final write acceptance.
- The app may expose planning edit affordances based on the current visible capability model, but Flutter must not become the source of truth for write permission.
- Explicit sign-out must not silently preserve authenticated pending planning mutations on shared devices.

## Local-First View Model Requirements

### Projection Plus Mutation Model

This slice must preserve the existing normalized planning read projection as the local planning read foundation.

Planning writes must be modeled separately as persisted local mutation state rather than by reusing the read projection rows as the only write-state carrier.

Reason:

- the existing planning read slice is already projection-oriented
- planning is a hierarchical aggregate, not a single flat entity
- future planning views and clients need a stable read model boundary
- later online-coordinated editing should be able to change synchronization strategy without redefining the entire local read model

### Merged Local-First Views

The repository or application layer must expose merged local-first planning views to presentation.

That merged view must combine:

- the last synchronized planning read projection for the active organization
- the current persisted local planning mutations for the same active organization

The UI must not be responsible for merging projection rows and mutation rows directly.

Required visible outcomes:

- a newly created local plan appears immediately in the plan list
- a locally edited plan appears immediately with its updated fields in list and detail contexts
- a newly created local session appears immediately in the owning plan detail
- a locally renamed session appears immediately with its updated name
- a locally deleted eligible session disappears immediately from the normal plan detail view

## Aggregate And Field Rules

### Plan Create

Local plan creation in this slice must capture at least:

- `id`
- `organization_id`
- `group_id`
- `slug`
- `name`
- `description`
- `scheduled_for`

Rules:

- new local plans use locally generated stable identifiers
- new local plans in this slice are always organization-scoped and therefore use `group_id = null`
- new local plans also allocate a locally unique provisional slug within the active organization view before backend sync succeeds
- the local create is immediately visible in the plan list and plan detail entry path
- a newly created plan starts with zero or more locally created sessions and no local session items
- the locally generated slug is not yet the canonical shareable slug until the backend accepts the create
- the merged plan list must order locally created and locally edited plans using the same deterministic rule already defined for synchronized planning reads: `scheduled_for` ascending with nulls last, then `updated_at` descending, then `id` ascending

### Plan Edit

Local plan edit in this slice is restricted to:

- `name`
- `description`
- `scheduled_for`

Rules:

- plan slug remains stable after creation in this slice
- plan `group_id` is not editable in this slice
- local plan edits must appear immediately in merged local-first views
- the planning write model must preserve the synchronized base version needed for later backend acceptance

### Session Create

Local session creation in this slice must capture at least:

- `id`
- `plan_id`
- `organization_id`
- `group_id`
- `slug`
- `name`
- `position`

Rules:

- a new local session belongs to exactly one plan
- a new local session uses a locally generated stable identifier
- a new local session inherits the owning plan's `group_id`
- a new local session allocates a locally unique provisional slug within the plan before backend sync succeeds
- a new local session is appended deterministically to the end of the current local session ordering within the plan
- a new local session starts empty in this slice
- the locally generated slug is not yet the canonical shareable slug until the backend accepts the create

### Session Rename

Local session edit in this slice is restricted to renaming the session `name`.

Rules:

- session slug remains stable after creation in this slice
- session position is not editable in this slice
- local session rename appears immediately in merged local-first views
- the write model must preserve the synchronized base version needed for later backend acceptance

### Session Delete

Session delete is intentionally narrow in this slice.

Rules:

- a session may be deleted only when it has no session items in the current local planning view
- this rule applies to synchronized sessions and to locally created sessions
- deleting a non-empty session is out of scope because this slice does not yet define session item editing or destructive cascade UX
- once an eligible local session delete is recorded, that session disappears immediately from the normal merged local-first plan detail view
- backend synchronization must re-check the delete precondition so stale local data cannot delete a session that became non-empty elsewhere
- if the backend later rejects the delete, the synchronized session must reappear in the normal merged plan detail view and the failed delete remains inspectable in an explicit mutation-status or error-review surface

### Slug Reconciliation

Plans and sessions already use slugs as public route identifiers elsewhere in the repository. This slice must therefore define explicit local-create slug reconciliation.

Rules:

- locally generated plan and session slugs are provisional until the backend accepts the create
- the app may use provisional slugs for same-device local navigation before sync succeeds
- the app must not present provisional slugs as canonical shareable URLs
- when the backend accepts a create and returns a different canonical slug, the local planning state must reconcile to that backend slug even if the immediate follow-up full refresh fails, but only while the same authenticated planning boundary remains active
- after reconciliation, subsequent route generation and slug lookup must use the backend-accepted canonical slug
- if the backend rejects a create because the proposed slug cannot be accepted, the mutation must remain visible as a failed local mutation rather than silently creating a duplicate-looking second entity

## Mutation Persistence Requirements

### Persisted Planning Mutation State

Planning mutations must be stored durably on device rather than only in memory.

Minimum mutation coverage:

- pending plan create
- pending plan edit
- pending session create
- pending session rename
- pending session delete
- the organization and aggregate ownership needed to keep mutations within the active organization boundary
- the synchronized base version needed for later backend acceptance on updates and deletes
- enough local metadata to reconstruct merged local-first planning views after app restart

The persisted planning mutation state may use a queue, mutation log, or other repository-owned structure, but it must keep write intent distinct from the normalized read projection.

### Mutation Compaction And Dependency Rules

The persisted mutation model must define deterministic local compaction and parent-child dependency handling.

Required rules:

- create-then-edit of the same local plan or session collapses into one pending create with the latest local fields
- create-then-delete of the same local plan or session annihilates the local mutation instead of emitting backend work for an entity the backend never accepted
- multiple local edits to the same synchronized plan or session collapse into one pending update against the same synchronized base version until sync succeeds or conflict resolution intervenes
- session mutations belonging to a locally created plan must remain tied to that local plan identity and must not be synchronized ahead of the parent plan create
- if a local plan create is discarded or rejected permanently, its dependent local session mutations must be discarded with it rather than left orphaned
- a session delete supersedes earlier pending session rename mutations for that same session
- the sync layer must emit backend operations in parent-before-child order for creates and child-before-parent order for destructive operations when both aggregates are involved

### Mutation Visibility Rules

- The user-visible planning surface must reflect persisted local mutations immediately after they are recorded.
- A pending local mutation remains visible after app restart until it is synchronized, explicitly discarded, or cleared by sign-out.
- Failed or conflicted mutations must remain inspectable enough that the user can understand why the visible local state differs from the last synchronized backend state.
- Non-retryable failed mutations must not continue to masquerade as accepted current planning state in the normal merged plan list or plan detail views.

### Sync Trigger Rules

This slice must define one deterministic foreground sync path for planning mutations.

Required behavior:

- recording a local planning mutation schedules an automatic sync attempt when the user is signed in, the active organization is available, and the app can attempt authenticated planning writes in the foreground
- the app must also provide an explicit user-triggered retry path for pending or failed planning mutations
- automatic retry while the app is suspended or terminated is not required in this slice
- the write-side sync trigger must not depend on background execution that the repository does not currently guarantee

## Synchronization And Authorization Requirements

### Backend-Owned Authorization

Planning create, edit, and delete synchronization must remain backend-authorized work.

- Flutter may expose planning write affordances only when the signed-in user appears capable of planning edits, but the client is never the source of truth for authorization.
- The exact backend capability name may evolve, but enforcement must remain in Supabase/Postgres rather than in Flutter.
- If the backend rejects a planning mutation because the user no longer has the required write permission, the client must surface a non-retryable authorization failure for that mutation rather than silently dropping it or pretending the write succeeded.
- Once a planning mutation is rejected for authorization, dependency, or remote-delete reasons, that mutation must leave the normal merged plan list and plan detail views and remain visible only through explicit mutation-status or error-review surfaces.

### Canonical Write Boundary

The backend remains the canonical source of accepted planning writes.

Required write-side direction:

- local create/edit/delete is recorded first on device
- a repository-owned sync path attempts the corresponding backend mutation
- the backend returns the accepted canonical state or an explicit failure outcome
- the local planning state converges by updating the read projection and clearing or revising the corresponding mutation state

For updates and deletes against synchronized plans or sessions, backend acceptance in this slice must use version-aware concurrency checks rather than silent last-write-wins.

This slice does not require a particular transport shape such as RPC-only or direct table writes, but the enforcement point must remain backend-owned.

### Sync Semantics

The write path in this slice must preserve room for later richer behavior such as:

- explicit conflict resolution
- targeted plan-level refresh after mutation success
- lock-aware online editing
- realtime fan-out of accepted planning changes to other clients

This slice does not need to implement those behaviors yet, but it must not foreclose them by collapsing planning write intent into presentation-only state.

### Remote Delete And Conflict Handling

This slice does not need to ship a full conflict-resolution UI, but it must define durable failure semantics when synchronized base rows diverge remotely before the local mutation syncs.

Required rules:

- if a synchronized plan or session was deleted remotely before a pending local edit or delete syncs, the local mutation must transition to an explicit remote-delete conflict or failure state
- a remote-delete conflict must not resurrect the deleted aggregate back into the normal merged plan list or plan detail view as if it were still accepted current data
- the failed local intent must remain inspectable in an explicit mutation-status or error-review surface until the user discards it or a later slice adds richer recovery
- if the backend reports a version conflict for a synchronized plan or session, the client must preserve the local mutation state for later explicit conflict handling rather than silently overwriting server state

## Offline Behavior

### After Local Mutation Recording

Once a planning mutation is recorded locally:

- the corresponding change remains visible offline
- app restart must not discard that visible local change
- the user may continue reading planning through the merged local-first planning views even if the backend is unavailable

### Before Synchronization Success

Before the backend accepts the local change:

- the visible local state is still the user-facing truth
- the app must distinguish local pending state from canonical synchronized state where needed for status surfaces
- the app must not misrepresent pending local planning changes as already accepted by the backend

If the backend later rejects a mutation with a non-retryable outcome, the user's failed local intent remains inspectable but no longer overlays the normal accepted planning view.

## Failure Rules

- If local mutation recording fails, the visible planning state must remain unchanged and the user must receive an explicit failure.
- If backend synchronization fails because of connectivity, the locally visible planning change remains in place as pending local state.
- If backend synchronization fails because of authorization, the locally visible planning change remains inspectable, but the mutation must be marked as a non-retryable authorization failure rather than silently retried forever.
- If backend synchronization fails because a session delete precondition is no longer valid, the client must surface an explicit dependency-style failure rather than silently deleting the session locally and pretending the backend agreed.
- If backend synchronization detects a version conflict, the client must preserve enough mutation state to support later explicit conflict handling rather than discarding the user's local change.
- If backend synchronization reports that the synchronized base plan or session was deleted remotely, the client must move the mutation into an explicit remote-delete failure state instead of resurrecting that aggregate in the normal merged planning view.
- Explicit sign-out must not leave authenticated planning mutations readable on the device.

## Sign-Out Safety

Explicit sign-out remains a tenant-boundary operation.

Requirements:

- before sign-out completes, the app checks for unsynchronized planning mutations
- if unsynchronized planning mutations exist, the app warns that signing out will discard those local planning changes
- if the user confirms sign-out, authenticated planning mutations and authenticated planning projection data are removed together

This slice may share sign-out warning patterns with the song CRUD slice, but planning rules must be documented explicitly for this aggregate.

The same cleanup boundary also applies to any auth loss that invalidates the authenticated planning owner, including:

- session expiry
- revoked auth session
- authenticated account switch
- active-organization switch

When those boundaries change, the app must not keep showing or replaying the prior owner's pending planning mutations in the new authenticated context.

## Future Online-Coordinated Editing Compatibility

This slice is local-first, but its architecture must stay compatible with a later online-coordinated editing model where:

- an online client can acquire a write lock or other backend-owned edit claim
- edits may be sent immediately to the backend instead of waiting for deferred sync
- accepted changes may fan out quickly to other connected clients

To preserve that direction:

- the local read projection must remain a stable read-side boundary
- local write intent must remain explicit rather than implicit only inside rendered view state
- synchronization strategy must be replaceable without redefining the planning read model

This slice does not implement locks, collaborative presence, or realtime editing. It only preserves their architectural path.

## Testing Requirements

TDD is mandatory.

### Unit Tests

Cover:

- local planning mutation recording rules
- merged local-first plan list and plan detail behavior
- plan field edit restrictions
- session create append ordering
- session delete eligibility for empty vs non-empty sessions
- authorization-failure handling for planning mutations
- conflict or concurrency-failure state preservation
- sign-out discard decisions when unsynchronized planning mutations exist

### Widget Tests

Cover:

- plan create and edit surfaces
- session create, rename, and delete surfaces
- immediate visible local update after user action
- pending, failed, and authorization-denied status surfaces where exposed in UI
- sign-out warning behavior when unsynchronized planning mutations exist

### Integration Tests

Cover:

- offline plan creation and later synchronization
- offline plan edit and later synchronization
- offline session create, rename, and delete for empty sessions
- app restart preserving visible pending planning mutations
- merged local-first planning views after database reopen
- sign-out clearing authenticated planning projection plus pending planning mutations

### Backend Verification

Cover:

- planning write authorization enforcement through backend-owned policy helpers or other backend-owned enforcement
- active-organization scoping for planning writes
- canonical slug uniqueness for created plans and sessions
- update/delete concurrency enforcement for synchronized plan and session mutations in this slice
- rejection of session delete when the session still contains session items

## Documentation Impact

Implementation of this slice must update:

- `README.md` for repository-level slice status and verification wording
- `docs/domain/domain-model.md` for planning write invariants, mutation expectations, and delete rules
- `docs/architecture/architecture.md` for the durable planning projection-plus-mutation boundary
- `docs/architecture/decisions/` for any durable write-side planning sync or authorization decision that outlives this single slice
- `docs/testing/testing-strategy.md` for standing planning create/edit verification expectations
- `docs/workflows/ai-development.md` only if the planning write slice changes documented workflow rules
- `docs/plans/` for the concrete implementation plan before code changes begin
