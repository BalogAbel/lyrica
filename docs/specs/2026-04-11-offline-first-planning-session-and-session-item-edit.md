# Offline-First Planning Session And Session Item Edit Spec

> Status: Proposed

> This spec extends [docs/specs/2026-04-10-offline-first-planning-create-edit.md](docs/specs/2026-04-10-offline-first-planning-create-edit.md) and depends on the local-first planning read and planning create/edit slices that already established the normalized planning projection, the separate planning mutation store, foreground mutation sync, backend-enforced authorization, and provisional-to-canonical reconciliation for plan and session writes.

## Goal

Deliver the next local-first planning write slice by allowing users to reorder sessions within a plan and to add, delete, and reorder song-backed session items locally first, while preserving the current planning read/write/sync architecture, backend-owned authorization, and repository-owned reconciliation rules.

## Problem

The repository already proves these planning foundations:

- local-first planning reads for the active organization
- local-first plan create/edit
- local-first session create, rename, and delete for eligible empty sessions
- a separate persisted planning mutation store overlaid on the synchronized planning projection
- foreground planning mutation sync with backend-owned authorization and conflict classification

That still leaves a material workflow gap. A user can create the plan shell and its sessions locally, but cannot finish the most important preparation steps:

- arranging sessions into the intended service order
- adding songs to a session while offline
- removing songs from a session
- reordering session items into the intended running order

Without those capabilities, the current planning write slice proves local-first structure editing but not practical plan preparation.

## Scope

- Allow users to reorder sessions within one plan locally first.
- Allow users to add a `song` session item to one session locally first.
- Allow users to delete a session item locally first.
- Allow users to reorder session items within one session locally first.
- Keep all four mutation types persisted locally and immediately reflected in merged planning reads.
- Keep writes scoped to the active authenticated user plus active organization boundary.
- Keep synchronization foreground-driven and repository-owned.
- Keep authorization and canonical write acceptance backend-enforced.
- Add OCC or version-aware reconciliation where collection mutations need it.
- Keep the implementation aligned with the existing planning read projection, planning mutation store, planning sync controller, and local-first song catalog read model.
- Keep documentation vendor-neutral and repository-owned.

## Non-Goals

- No UX polish or final visual redesign.
- No product-wide unified sync UX.
- No session item content editing such as notes, title override, or item-type conversion.
- No `attachment` or `note` session item editing in this slice.
- No cross-session move for session items; this slice only supports reorder within the current session.
- No cross-plan move for sessions; this slice only supports reorder within the current plan.
- No bulk multi-select editing.
- No lock acquisition, collaborative presence, realtime fan-out, or automatic background sync while the app is suspended or terminated.
- No feature expansion beyond session reorder plus session-item song add/delete/reorder.

## Product Slice Summary

This slice proves the next coherent local-first planning edit claim:

1. a signed-in user opens planning for the active organization
2. the user locally reorders sessions, or adds, deletes, or reorders song-backed session items
3. the planning UI immediately reflects that local change
4. the local change remains visible and usable offline after app restart
5. foreground sync later accepts, rejects, or conflicts with that change through repository-owned behavior
6. authorization remains owned by Supabase Auth identity plus Postgres policy and write-contract enforcement rather than by Flutter

## Current Architectural Context

This slice must preserve the boundaries already established in the repository:

- planning reads come from a normalized Drift-backed planning projection for the active organization
- planning writes are recorded in a separate persisted mutation store and overlaid into merged local-first reads
- pending local writes remain visible until synchronized, discarded, or cleared by auth-boundary cleanup
- failed non-overlaying mutations remain inspectable outside the normal merged planning view
- planning write sync is foreground-driven and repository-owned
- accepted writes reconcile through full refresh when possible and direct local projection patching when a same-boundary post-write refresh fails
- local-first authenticated song reads already provide the visible song catalog needed for offline song selection

This slice must extend those rules rather than introduce a second planning architecture.

## Core Product Rules

- The user-visible planning surface must always show the latest persisted local session ordering and session-item ordering for the active organization.
- A locally recorded session reorder or session-item mutation must survive app restart and remain visible offline until it is synchronized, discarded, or cleared by auth-boundary cleanup.
- Session-item add in this slice is restricted to `item_type = 'song'`.
- The add flow must use songs that are already visible in the active organization's local-first song catalog; this slice does not introduce online-only song search as a requirement.
- The domain invariant that one song may appear at most once within one session remains in force and must be enforced by backend acceptance as well as by client-side preflight checks where practical.
- Flutter may expose affordances based on visible capability state, but Flutter is never the authority for authorization, duplicate prevention, or canonical acceptance.
- Explicit sign-out and other authenticated-owner boundary changes must remove both the planning projection and the planning mutation state for the prior owner.

## Domain Behavior

### Session Reorder

Session reorder is a plan-scoped collection mutation.

Rules:

- reorder applies only within one plan
- reorder accepts a permutation of the currently visible session ids for that plan
- reorder may include synchronized sessions and locally created sessions in the same final order
- reorder must not silently drop sessions from the permutation
- newly created sessions still append by default when first created, but the user may reorder them afterwards
- the merged local-first plan detail must immediately reflect the new local session order
- synchronized session reorder acceptance must use the owning plan's current synchronized `version` as the optimistic-concurrency boundary

### Session Item Song Add

Session-item add is a session-scoped collection mutation.

Rules:

- add creates a new `session_item` with `item_type = 'song'`
- the added song must already be visible in the active organization's local-first song catalog
- the added song must belong to the same organization as the owning session
- the same song must not appear more than once within the same session
- add appends to the end of the current local item ordering by default
- the user may later reorder the added item within the same session
- the merged local-first plan detail must immediately reflect the new local item
- synchronized add acceptance must use the owning session's current synchronized `version` as the optimistic-concurrency boundary

### Session Item Delete

Session-item delete is a session-scoped destructive mutation.

Rules:

- delete applies to one session item within one session
- once recorded locally, the deleted item disappears immediately from the normal merged plan detail view
- if backend synchronization later rejects that delete, the synchronized item reappears in the normal merged view and the failed local intent remains inspectable in mutation-status UI
- synchronized delete acceptance must use the owning session's current synchronized `version` as the optimistic-concurrency boundary

### Session Item Reorder

Session-item reorder is a session-scoped collection mutation.

Rules:

- reorder applies only within one session
- reorder accepts a permutation of the currently visible session-item ids for that session
- reorder may include synchronized items and locally created items in the same final order
- reorder must not silently drop items from the permutation
- the merged local-first plan detail must immediately reflect the new local session-item order
- synchronized reorder acceptance must use the owning session's current synchronized `version` as the optimistic-concurrency boundary

## Ordering Semantics

This slice preserves the repository-owned deterministic ordering model.

- plans continue to sort by `scheduled_for` ascending with nulls last, then `updated_at` descending, then `id` ascending
- sessions continue to sort by `position` ascending within a plan, then `id` ascending
- session items continue to sort by `position` ascending within a session, then `id` ascending

For local-first writes:

- new session create still appends by allocating the next local `position`
- new session-item add appends by allocating the next local `position`
- session reorder and session-item reorder are represented as an explicit local final sibling order, not as a presentation-only drag state
- the backend remains free to canonicalize stored `position` values, but the accepted visible order must match the submitted logical order
- when a reorder mutation is accepted, the local projection must reconcile to the backend-accepted canonical order even if the immediate follow-up full refresh fails, as long as the same authenticated planning boundary still owns that projection

## Local-First Expectations

### Projection Plus Mutation Model

This slice must continue the projection-plus-mutation architecture introduced by the planning create/edit slice.

- the synchronized planning projection remains the repository-owned read model
- local session reorder and local session-item add/delete/reorder are recorded in the persisted planning mutation store
- presentation reads only merged local-first planning views exposed by the repository or application layer
- the UI must not merge raw projection rows with raw mutation rows itself

### Song Catalog Dependency

Offline session-item add depends on the already synchronized local song catalog for the active organization.

Required behavior:

- if the active organization has no local song catalog available yet, the app must not pretend that offline song add is fully available
- if a song is not locally visible to the active organization, the app must not fabricate enough metadata to add it anyway
- when a song is locally visible, the session-item add flow must be able to create and render the pending local item without requiring an online lookup

## Mutation Persistence And Compaction

The persisted planning mutation store must extend its current compaction and dependency rules to cover collection edits.

Required rules:

- multiple local session reorders for the same plan collapse into one pending reorder with the latest sibling order and the earliest still-relevant synchronized base version
- multiple local session-item reorders for the same session collapse into one pending reorder with the latest sibling order and the earliest still-relevant synchronized base version
- session delete supersedes any earlier pending session reorder participation for that session
- deleting a session from a pending plan-level reorder must remove that session from the final reordered sibling set
- session-item add followed by delete of the same locally created item annihilates both local mutations instead of emitting backend work
- session-item add followed by reorder remains one pending create plus, if needed, one pending reorder for the owning session
- session-item delete supersedes any earlier pending reorder participation for that item
- deleting an item from a pending reorder must remove that item from the final reordered sibling set
- reordering sessions or items must preserve parent-child dependency ordering for later synchronization
- session-item mutations belonging to a locally created session must not synchronize ahead of the parent session create
- session reorder involving a locally created session must not synchronize ahead of the session create on which it depends

## Synchronization And Reconciliation Expectations

### Backend-Enforced Authorization

- session reorder must be authorized by the same backend-enforced plan-management capability boundary that already governs plan-scoped planning writes
- session-item add, delete, and reorder must be authorized by backend-enforced session-write capability checks
- authorization enforcement must remain in Supabase/Postgres write contracts, not in Flutter
- authorization loss after local recording must produce explicit non-retryable failure state rather than silent drop or silent success

### OCC And Collection Versioning

This slice needs version-aware write acceptance because the new mutations modify ordered collections.

Required rules:

- synchronized session reorder must send the owning plan's synchronized `base_version`
- synchronized session-item add, delete, and reorder must send the owning session's synchronized `base_version`
- a stale synchronized parent version must yield explicit conflict rather than silent last-write-wins
- accepted collection mutations must advance the canonical server version of the owning collection aggregate

This slice does not require Flutter to implement rich conflict resolution. It only requires preserving enough mutation state for later explicit conflict handling.

### Canonical Response Shape

The backend write contract for this slice must return enough canonical data to support deterministic local reconciliation when immediate refresh fails inside the same active planning boundary.

Minimum response requirements:

- session reorder returns the owning plan id, the plan's new canonical `version`, and the accepted canonical ordered session ids with canonical positions
- session-item add returns the owning session id, the session's new canonical `version`, the accepted canonical session-item row for the created item, and the canonical ordered session-item ids with canonical positions
- session-item delete returns the owning session id, the session's new canonical `version`, the deleted session-item id, and the canonical ordered remaining session-item ids with canonical positions
- session-item reorder returns the owning session id, the session's new canonical `version`, and the accepted canonical ordered session-item ids with canonical positions

The sync layer may use richer response payloads, but it must not rely on hidden server state that the repository does not receive.

### Accepted-Write Reconciliation

The planning sync layer must continue the current accepted-write reconciliation rule.

- after backend success, the client attempts the normal planning refresh path
- if that refresh succeeds, the accepted mutation may clear normally
- if that refresh fails but the same active planning boundary still owns the projection, the accepted canonical session or session-item state must reconcile directly into the local projection before the mutation row clears
- reconciliation must update canonical ordering and canonical versions, not just clear the mutation row

### Remote Delete And Missing-Parent Handling

- if a synchronized plan or session was deleted remotely before a pending reorder or session-item mutation syncs, the local mutation must transition to explicit remote-missing failure
- a remote-missing failure must not resurrect an aggregate back into the normal merged plan detail view as if the backend still accepted it
- if a synchronized session item was deleted remotely before a pending local delete or reorder syncs, the client must keep the failed local intent inspectable rather than silently discarding it

## Offline-First Behavior

- after local recording, session reorder and session-item add/delete/reorder remain visible offline
- app restart must not discard those visible local changes
- connectivity failure keeps the local mutation pending and the merged local-first planning view intact
- the app must distinguish pending local state from backend-synchronized state where status surfaces require it
- this slice does not require background retry while the app is suspended or terminated

## Auth Boundary Rules

- explicit sign-out must warn when unsynchronized planning mutations exist and the app is about to discard them
- if the user confirms sign-out, the planning projection and planning mutation rows for that authenticated owner are removed together
- session expiry, revoked auth session, authenticated account switch, and active-organization switch must also prevent prior-owner planning mutations from remaining visible or replayable in the new boundary

## Failure Handling

- if local mutation recording fails, the visible planning state remains unchanged and the user receives explicit failure
- if local song selection is unavailable because the song catalog is not locally available for the active organization, session-item add must remain unavailable rather than pretending to work offline
- if backend sync fails because of connectivity, the local mutation remains pending and visible in merged reads
- if backend sync fails because of authorization, the mutation moves out of the normal merged view and remains inspectable as a non-retryable authorization failure
- if backend sync fails because the selected song is no longer visible, no longer belongs to the organization, or would violate the one-song-per-session invariant, the mutation becomes an explicit `failedDependency` outcome and leaves the normal merged view
- if backend sync fails because of stale parent version, the mutation remains inspectable in conflict state for later explicit handling
- if backend sync reports that the synchronized parent aggregate or synchronized item was deleted remotely, the mutation moves to explicit remote-missing failure instead of silently disappearing

## Out-Of-Scope Follow-Ups To Preserve

- session-item note and attachment editing
- cross-session move for session items
- session-item field editing beyond add/delete/reorder
- richer conflict-resolution UX
- product-wide sync-status consistency work
- collaborative or lock-based planning editing

## Testing Requirements

TDD is mandatory.

### Unit Tests

Cover:

- session reorder compaction and merged ordering
- session-item add, delete, and reorder compaction
- duplicate-song prevention in one session
- session-scoped and item-scoped reconciliation behavior
- parent-version capture for reorder and item collection mutations
- authorization, dependency, remote-missing, and conflict classification

### Widget Tests

Cover:

- minimal session reorder affordance
- song add affordance from the locally visible song catalog
- session-item delete affordance
- session-item reorder affordance
- immediate local view updates and failure-status surfaces

### Integration Tests

Cover:

- offline session reorder followed by later sync
- offline session-item add/delete/reorder followed by later sync
- app restart preserving pending collection mutations
- merged local-first planning detail after reopen
- auth-boundary cleanup for projection plus mutations

### Backend Verification

Cover:

- backend-enforced authorization for session reorder and session-item add/delete/reorder
- plan-version and session-version OCC enforcement for collection mutations
- duplicate-song rejection within one session
- organization-scope enforcement for added songs
- accepted canonical ordering after reorder writes

## Documentation Impact

Implementation of this slice must update:

- `README.md`
- `docs/domain/domain-model.md`
- `docs/architecture/architecture.md`
- `docs/testing/testing-strategy.md`
- `docs/specs/`
- `docs/plans/`
- `docs/architecture/decisions/` if implementation introduces a durable technical choice beyond the current accepted planning write boundary

## Acceptance Criteria

- A signed-in user can reorder sessions within one plan locally, and the new order appears immediately in merged planning reads.
- A signed-in user can add a visible organization song to one session locally, and the new item appears immediately in merged planning reads.
- A signed-in user can delete a session item locally, and the item disappears immediately from the normal merged planning view.
- A signed-in user can reorder session items within one session locally, and the new order appears immediately in merged planning reads.
- Pending session reorder and session-item mutations survive app restart and remain visible offline.
- The planning sync layer preserves the current projection-plus-mutation architecture and foreground-driven mutation sync model.
- Backend-owned authorization remains the source of truth for all accepted writes.
- Session reorder uses plan-level OCC, and session-item add/delete/reorder use session-level OCC.
- Accepted writes reconcile canonical ordering and versions back into the local projection even if the immediate post-write refresh fails inside the same active planning boundary.
- Non-retryable authorization, dependency, and remote-missing failures stop overlaying the normal merged planning view and remain inspectable separately.
