# Local-First Planning Read Spec

> Status: Implemented

## Goal

Extend the current authenticated planning read slice so that planning becomes local-first for the active organization. After a successful signed-in refresh, the client must keep the full visible planning read model for the active organization available offline, including the planning context needed to enter the song reader from a plan session item.

## Problem

The repository already proves two adjacent slices:

- authenticated local-first song catalog reads
- authenticated online-only planning reads

That leaves a product and architecture gap. The application currently claims local-first thinking as a core product strength, but planning is still intentionally online-only. This weakens the planning workflow in exactly the situations the product is supposed to handle well, such as poor connectivity before or during service preparation.

The next planning slice should close that gap without prematurely introducing planning writes, sync-queue complexity, or multi-organization offline mirroring.

## Scope

- Make planning reads local-first for the currently active organization.
- Automatically fetch the full visible planning read model for the active organization when a signed-in active-organization context becomes available.
- Persist the active organization's visible planning read model locally so it remains available offline.
- Serve plan list, plan detail, sessions, ordered session items, and plan-origin reader context from the local planning store.
- Keep planning read behavior read-only in this slice.
- Keep the current backend-owned authorization boundary.
- Keep the current active-organization assumption.
- Keep the local projection item-safe by preserving session item identity and the embedded song summary fields needed by the UI.
- Preserve room for future finer-grained refresh strategies such as single-plan or single-song refresh without requiring them in this slice.

## Non-Goals

- No planning create, edit, delete, reorder, or drag-and-drop UI.
- No planning write-side sync queue or conflict handling.
- No multi-organization offline mirroring.
- No requirement to support only partially downloaded planning data as an acceptable offline state.
- No backend contract change to incremental or delta sync in this slice.
- No silent fallback from invalid planning context to ad hoc song-only behavior.
- No production-grade background refresh while the app is suspended or terminated.

## Product Slice Summary

This slice should prove a stronger local-first planning claim:

1. a signed-in user enters or restores an active organization context
2. the app eagerly refreshes the full visible planning read model for that organization
3. the app persists that planning state locally
4. the user can browse plans and open plan detail from local data
5. the user can open songs from planning using locally available planning context
6. when connectivity is poor or absent, the previously synchronized planning state remains fully readable offline

This slice is still read-only. It is about guaranteeing local availability of planning reads, not about introducing local planning mutations.

## Core Product Rules

- Planning for the active organization must be treated as local-first after the first successful refresh.
- The local planning read model must contain the full visible planning state for the active organization, not only the plans or details the user already opened.
- Offline planning behavior in this slice is organization-complete, not route-by-route opportunistic caching.
- Plan list, plan detail, ordered sessions, ordered session items, and plan-origin reader context must all be reconstructable from the local planning store.
- The app must not claim complete offline planning availability for an organization before that organization has completed at least one successful planning refresh.
- Explicit sign-out must remove authenticated local planning access.
- An in-flight planning refresh must not restore authenticated local planning data after sign-out finishes.

## Active Organization Boundary

- The offline guarantee in this slice applies only to the current active organization.
- The slice does not require mirroring all visible organizations locally.
- The local planning store must remain explicitly keyed by authenticated user and active organization ownership so authenticated data does not become device-global.
- If the active organization changes in the future, the planning local store boundary must remain explicit enough to support one active organization at a time without leaking stale cross-organization state.

## Local Model Requirements

### Normalized Local Read Model

The client must persist planning data as a normalized local read model rather than one opaque serialized planning blob.

Minimum required local model coverage:

- plan summary fields needed for the planning list
- plan detail fields needed for the planning detail route
- ordered sessions for each plan, with canonical `sessionId` and parent `planId`
- ordered session items for each session, keyed by `sessionItemId`, `sessionId`, and `planId`
- the embedded song summary fields needed to render the plan detail UI and resolve plan-origin reader navigation
- ownership metadata keyed by the authenticated `userId` and current `organizationId`

The local model must preserve duplicate song references as distinct session items when the backend allows the same song to appear more than once in one session.

This local model may be optimized for read-side projection rather than mirroring every backend table one-for-one, but it must preserve aggregate boundaries clearly enough that future finer-grained refresh strategies remain possible.

### Ordering Rules

The local read model must preserve the same deterministic visible ordering as the backend read path:

- plans sort by `scheduled_for` ascending with nulls last, then `updated_at` descending, then `id` ascending
- sessions sort by `position` ascending within a plan, then `id` ascending
- session items sort by `position` ascending within a session, then `id` ascending

### Future Partial Refresh Compatibility

This slice intentionally uses full active-organization refresh semantics, but the local model and repository boundary must not assume that only full-organization replacement will ever exist.

The implementation must therefore avoid choices that would make future targeted refreshes unnecessarily difficult, such as:

- storing the entire organization planning state only as one opaque blob
- exposing snapshot-only shapes directly to presentation code
- coupling route behavior directly to backend payload shape

This slice does not require plan-level or song-level refresh today. It only requires preserving that option.

## Refresh Semantics

### Eager Refresh Trigger

Planning refresh in this slice is eager.

When all of the following become true:

- the user is signed in
- the app has or restores the active organization context
- the application can attempt authenticated planning reads

the app must start a full planning refresh for that active organization.

The purpose of this eager refresh is to establish complete offline planning availability, not merely to warm the current screen.

### Sync Owner

One planning sync owner must control refresh lifecycle for the active organization.

That sync owner must:

- serialize overlapping refresh requests so only one refresh updates the local projection at a time
- surface explicit `idle`, `refreshing`, and `failed` states to the app
- preserve the previous local planning state when refresh fails after a successful sync already exists
- clear authenticated planning data, ownership metadata, and local sync state on explicit sign-out
- reset the sync owner's in-memory state to signed-out/unavailable after explicit sign-out so no stale projection remains live
- associate each refresh with a monotonically increasing active-organization generation so stale completions are ignored after an organization switch

### Full Active-Organization Refresh

The refresh path for this slice must fetch the full visible planning read model for the active organization.

That includes the data required to render:

- the plan list
- plan detail
- ordered sessions
- ordered session items
- plan-origin reader context based on session item identity

This slice does not require a separate lazy detail-fetch path as the basis of offline planning support.

### Atomic Replacement

Local planning state must be replaced atomically.

- A completed, consistent full planning refresh may replace the active local planning state for the active organization.
- A partial or failed refresh must not leave the local planning projection in a mixed old/new state that is presented as authoritative.
- If refresh fails after a previously successful planning refresh already existed, the last successful local planning state remains active.
- If the active organization changes, the sync owner must treat the new organization as the current local planning boundary and refresh it before exposing it as current.
- If the active organization changes while a refresh is in flight, the older refresh result must be discarded rather than repopulating the previous organization boundary.
- If the new active organization refresh fails before any successful projection exists for that organization, the previous organization's cached projection must not be exposed as the current state for the new organization.
- If the active organization changes, the previously active organization's cached projection must be purged from the active local planning store before the new organization becomes current.
- Switching back to a previously active organization later requires a fresh planning refresh for that organization.

## Offline Behavior

### After At Least One Successful Refresh

After the active organization completes one successful planning refresh, the app must be able to serve planning reads from the local store while offline.

Required offline behaviors:

- visible plans remain listable
- visible plan detail remains openable
- ordered sessions remain visible
- ordered song-backed session items remain visible
- plan-origin reader routes can resolve their planning context from local planning data

### Before The First Successful Refresh

If the user has not yet completed a successful planning refresh for the active organization, the app must not pretend that offline planning is fully available.

This slice may show a clear unavailable or not-yet-downloaded state in that situation, but it must not represent a partial ad hoc local subset as the full planning model.

## Reader Context Requirements

The current planning flow already depends on session-scoped reader context anchored to stable plan, session, session item, and song identifiers.

This slice must keep that context local-first as well:

- plan-origin reader navigation must be derivable from the local planning store after successful planning synchronization
- the selected session item identity remains the navigation anchor, not only song identity
- offline plan-origin reader entry must continue to respect same-session ordering from the locally stored planning model

This slice does not change reader-local runtime settings behavior. It only changes where the planning context comes from when planning is locally available.

## Authorization And Backend Boundary

- Supabase Auth identity and Postgres authorization remain the source of truth for what planning data is visible during online refresh.
- Flutter must not invent client-side authorization rules to compensate for missing or unavailable planning data.
- The local planning store is a persisted projection of backend-authorized data for the active organization.
- If later backend policy changes remove visibility, the next successful online refresh becomes the point where the local read model is updated accordingly.

## Failure Rules

- If an eager planning refresh fails and no prior successful local planning state exists for the active organization, planning remains unavailable for offline use.
- If an eager planning refresh fails and a prior successful local planning state exists, the app must keep serving the last successful local state.
- If sign-out occurs during an in-flight planning refresh, that refresh must not repopulate authenticated planning data after sign-out.
- Explicit sign-out must delete all authenticated planning rows for the user, including ownership metadata, sync state, plan rows, session rows, and session-item rows, rather than leaving any cached projection as active readable state.
- If a route describes invalid planning context, the app must continue to show explicit invalid-context behavior rather than silently degrading to unrelated navigation modes.

## Architecture Requirements

### Repository Boundary

Planning reads must remain behind explicit repository boundaries.

The planning repository for this slice must support:

- refreshing the full visible planning read model for the active organization
- reading plan list from local state
- reading plan detail from local state
- resolving planning reader context from local state

Presentation code must not need to know whether the current planning read came from a recent online refresh or from previously persisted local data.

### Local Store Ownership

The local planning store must be a repository-owned persisted projection, not a presentation-layer cache.

It should follow the same architectural intent already documented elsewhere in the repository:

- backend owns authorization and online visibility
- application layer orchestrates refresh and state transitions
- offline layer owns persisted local projections
- presentation reads from repository-backed local state
- authenticated projections remain tied to the current user and active organization boundary

### Refresh Strategy Flexibility

This slice standardizes on full active-organization refresh semantics, but it must avoid documenting or implementing that choice as if it were the only valid long-term model.

Durable architectural direction for this slice:

- current planning local-first behavior uses full-organization refresh
- local persistence stays normalized enough to permit later finer-grained refresh
- any future partial-refresh slice should be additive refinement, not a forced redesign

## Testing Requirements

TDD is mandatory.

### Unit Tests

Cover:

- active-organization eager refresh trigger behavior
- local planning snapshot ownership by authenticated user and active organization
- atomic replacement behavior for successful full refresh
- failed refresh preserving the last successful local planning state
- sign-out during in-flight refresh preventing stale repopulation
- local plan list and plan detail reads from the normalized planning store
- local resolution of plan-origin reader context from synchronized planning data

### Widget Tests

Cover:

- planning list rendering from local-first state
- planning detail rendering from local-first state
- explicit states for initial-not-downloaded vs offline-available planning
- planning behavior when refresh is running, succeeds, and fails while local data exists

### Integration Tests

Cover:

- eager signed-in planning refresh populating the local planning model
- offline planning list and plan detail reads after successful synchronization
- offline plan-origin reader navigation using local planning context
- failed refresh preserving the previous local planning state
- explicit sign-out clearing authenticated planning local access
- active-organization isolation and hidden-organization visibility boundaries

### Verification Boundary

Repository verification for this slice must strengthen executable proof rather than shifting planning local-first behavior into documentation only.

At minimum, verification must prove:

- planning refresh against the local Supabase stack
- offline planning reads from the persisted local planning model after refresh
- plan-origin reader context resolution from locally persisted planning data
- authenticated local planning data removal on explicit sign-out

## Documentation Requirements

This slice changes durable product and architecture understanding. Implementation of this slice must update the relevant repository documents in the same change, including:

- `README.md`
- `docs/product/vision.md`
- `docs/domain/domain-model.md`
- `docs/architecture/architecture.md`
- `docs/testing/testing-strategy.md`

If implementation decisions materially narrow or expand the local-first planning boundary beyond this spec, those changes must be reflected in the repository documentation during the same slice.

## Success Criteria

- A signed-in user with an active organization automatically downloads the full visible planning read model for that organization.
- After one successful planning refresh, planning remains fully readable offline for that organization.
- Local planning coverage includes plan list, plan detail, ordered sessions, ordered session items, and plan-origin reader context.
- Failed refresh does not destroy a previously valid local planning state.
- Explicit sign-out removes authenticated local planning access.
- The local planning model remains compatible with later finer-grained refresh strategies even though this slice itself uses full active-organization refresh.
