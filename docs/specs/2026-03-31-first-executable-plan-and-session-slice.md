# First Executable Plan And Session Slice Spec

> Status: Implemented

## Goal

Deliver the first executable planning slice for Lyrica by simplifying the canonical planning hierarchy to `plan -> session -> session_items`, seeding real local planning records in Supabase, and rendering those records in a minimal read-only Flutter flow.

## Problem

The repository already contains a broader planning-oriented domain shape centered on `plans`, `events`, `sessions`, and `session_items`, but that structure has not yet been validated through an executable product slice. At the same time, the current hierarchy appears more detailed than the team can presently justify from real product needs.

The immediate product need is narrower:

- prove that Lyrica can model a planning container with one or more operational session lists
- keep songs as separate canonical entities referenced from those lists
- show real plan and session data in the app rather than leaving the planning domain as documentation-only structure

This slice intentionally uses executable product evidence to validate the simplified domain instead of treating the change as documentation-only cleanup.

## Scope

- Simplify the active planning direction from `plan -> event -> session -> session_items` to `plan -> session -> session_items`.
- Treat `song` as a separate canonical entity referenced by `session_items`.
- Add a repository-owned local Supabase schema path for `plans`, `sessions`, and `session_items` that matches the simplified direction.
- Seed a small amount of local planning data that references the existing local demo song catalog.
- Define deterministic ordering for plans, sessions, and session items.
- Define the minimum repository read contract and route placement needed to make the slice executable.
- Add one minimal read-only planning flow in Flutter that proves:
  - plans can be listed
  - a plan can be opened
  - sessions belonging to that plan are visible
  - ordered song-backed session items render inside each session
- Preserve backend-owned authorization and organization scoping.
- Keep the slice compatible with the current local-first architecture direction, even though this slice itself does not yet require offline write behavior.

## Non-Goals

- No create, edit, delete, reorder, or drag-and-drop planning UI.
- No write-side sync queue or offline mutation flow.
- No mixed session item types beyond songs in this slice.
- No recursive nested list-in-list planning structure.
- No calendar-specific event layer in this slice.
- No final UX terminology decision beyond what is needed to render the minimal read-only flow.
- No attempt to solve the full planning workflow, volunteer scheduling, FreeShow export, or service execution controls.
- No production migration strategy beyond what is necessary for the repository's current local-only development state.
- No local Drift-backed planning cache in this slice.

## Product Slice Summary

The current executable product focus proves authenticated song reading, cached local-first catalog refresh, and robust verification of the read-only song library. What is still missing is the first executable planning structure built on top of that song catalog.

This slice proves a narrow but important next claim: the product can represent planning data as a `plan` containing one or more `sessions`, where each session is an ordered list of song-backed entries. The user should be able to open real seeded planning records and understand the structure through a minimal read-only UI.

This is not a full planning feature. It is the first executable proof that the simplified planning domain is concrete, renderable, and worth building on.

## Core Domain Rules

- `plan` is the top-level planning container in this slice.
- `session` belongs directly to a `plan`.
- `session_item` belongs to a `session`.
- In this slice, every `session_item` references exactly one `song`.
- `song` remains a separate canonical aggregate and must not be embedded under plans or sessions.
- The same `song` may appear in multiple sessions and multiple plans.
- Session item ordering must be explicit and stable.
- Session ordering inside a plan must be explicit and stable.
- Organization scope must remain aligned across `plan`, `session`, `session_item`, and referenced `song`.
- Group scope, when present, must remain aligned between a `plan` and all of its sessions.

## Simplified Planning Model

### Canonical Shape

This slice establishes the active planning direction as:

- `plan`
- `session`
- `session_item`
- `song`

Relationship summary:

- one organization has many plans
- one plan has many sessions
- one session has many session items
- one session item references one song in this slice

### Removed Active Layer

The previously modeled `event` layer is not part of the active planning direction for this slice.

Reason:

- the team does not currently have a validated product need for a separate calendar-facing middle layer
- the additional layer increases domain and UX complexity before the simpler `plan -> session` model has been proven through real usage

This slice does not forbid a future calendar or occurrence concept. It only states that such a layer is not justified as part of the first executable planning slice.

### Schema Replacement Boundary

This slice is not documentation-only. It changes the active repository-owned local schema direction.

Required schema outcome:

- `sessions.plan_id` replaces `sessions.event_id` as the owning parent reference
- `sessions` gain an explicit `position` column for stable ordering inside a plan
- `unique (plan_id, position)` becomes the session ordering constraint inside a plan
- `session_items` continue using `position` with `unique (session_id, position)`

Required local schema cleanup in this slice:

- the active local schema path must no longer require `events` for seeded or executable planning data
- any foreign keys, indexes, helper functions, policies, and triggers that currently assume `sessions.event_id` must be updated to the new `sessions.plan_id` ownership

For this slice, `events` should be treated as removed from the active local planning schema rather than kept as a parallel dormant planning layer. Because the repository is still local-only for this planning work, the slice may use the simplest repository-owned schema change path that leaves the local baseline coherent and executable.

## Ordering Rules

### Plan Ordering

Plans must render in this order:

1. `scheduled_for` ascending with null values last
2. `updated_at` descending as tie-breaker
3. `id` ascending as final deterministic tie-breaker

This keeps the initial plan list deterministic without adding a manual plan ordering model in the first slice.

### Session Ordering

Sessions must render in ascending `position` order within a plan.

Requirements:

- `position` is explicit on `sessions`
- positions must be unique within a plan
- seed data must use stable non-overlapping positions

### Session Item Ordering

Session items must render in ascending `position` order within a session.

## Seeded Data Requirements

The local repository workflow must include seeded planning records that make the slice real rather than purely structural.

Minimum required local fixture:

- at least one plan
- at least one session belonging to that plan
- at least two ordered session items inside that session
- session items referencing songs from the existing local demo song catalog

Preferred local proof:

- one simple single-session plan
- one multi-session plan
- one hidden-organization plan fixture that is not visible to the demo user

Reason:

- the simple plan proves the smallest common case
- the multi-session plan proves that `plan -> session` is not an unnecessary wrapper
- the hidden fixture makes organization-scoping verification real rather than theoretical

Required fixture details:

- demo-visible plans may be organization-scoped with `group_id` set to `null` in this slice
- if a seeded plan uses `group_id`, all of its seeded sessions must use the same `group_id`
- hidden planning fixtures must belong to the hidden organization and must not be visible to the demo user

This slice does not require a production-ready data migration story because the repository is still local-only for this planning work, but the resulting schema and seed path must still be repository-owned and repeatable.

## User Flows

### Planning List

1. The user signs in through the existing authenticated app flow.
2. The user opens the planning area.
3. The app loads the visible plans for the current organization.
4. The user sees at least the seeded local plans for the demo organization.

### Plan Detail

1. The user selects a plan.
2. The app loads that plan and its sessions.
3. The user sees the sessions in a stable order.
4. For each session, the app shows the ordered song-backed entries.

### Session Reading Context

1. The user opens a plan detail view.
2. The user can understand which songs belong to which session.
3. The user can distinguish separate sessions within the same plan.
4. The app does not yet require editing or rearranging the plan structure.

## UI Requirements

### Minimal Read-Only Planning Flow

The Flutter app must expose one small but real read-only planning flow.

At minimum:

- a dedicated plan list route
- a dedicated plan detail route
- visible session grouping inside the selected plan
- visible ordered song entries inside each session

The initial planning flow may remain intentionally simple and utilitarian. This slice is about proving the domain and data path, not shipping final planning UX polish.

### Route Placement

This slice must add planning as a new signed-in route subtree rather than replacing the current signed-in song list home.

Required route behavior:

- the existing signed-in home route continues to land on the song list
- the app adds a planning list route reachable from the signed-in area
- selecting a plan opens a dedicated plan detail route
- planning routes require the same signed-in gate as the existing song list and reader routes

The initial entry point from the song list to the planning area may be simple, such as a visible button or app bar action. The slice does not require final information architecture polish.

### Session Terminology In UI

This slice does not require the final user-facing label for `session`.

Requirements:

- the domain model and implementation should use canonical `session` naming
- the initial UI may show either `session` directly or a temporary user-facing label if needed for clarity
- any temporary UI copy must not reintroduce a conflicting domain layer such as `event`

### Song Entry Visibility

For each song-backed session item, the UI should show enough song information to prove the reference works.

At minimum:

- song title
- stable item ordering within the session

The slice may reuse existing `SongSummary` data rather than introducing a planning-specific song projection.

## Data Access Boundary

This slice must preserve the current architecture principles.

- Supabase remains the backend source of truth for planning records.
- Backend authorization and organization visibility remain backend-enforced.
- Flutter consumes planning data through repository boundaries rather than embedding authorization logic in widgets.
- Songs remain separate entities and are referenced from planning records instead of duplicated into session-owned payloads.
- This slice may reuse existing song summary shapes where they are sufficient to render planning entries.
- This first planning slice is allowed to be online-only behind repository boundaries.
- This slice must not introduce a local Drift-backed planning projection or planning cache.

## Repository Read Contract

The first executable planning slice must define explicit read-side repository surfaces.

Minimum required operations:

- `listPlans()`
- `getPlanDetail(planId)`

Required `listPlans()` behavior:

- returns the visible plans for the signed-in user's current organization scope
- applies the required plan ordering rules
- returns enough summary data to render the plan list at minimum:
  - `id`
  - `name`
  - `description`
  - `scheduledFor`
  - `updatedAt`

Required `getPlanDetail(planId)` behavior:

- returns one visible plan plus its sessions and song-backed session items
- applies the required session and session item ordering rules
- includes enough song summary data to render item titles without extra per-item song fetches

Minimum returned shape for each session item in `getPlanDetail(planId)`:

- `id`
- `position`
- `songId`
- `songTitle`

Implementation note:

- the backend/read path may use joined queries, a view, an RPC, or multiple repository-owned queries
- the Flutter feature must not depend on ad hoc widget-level joins

Missing-reference rule:

- if a `session_item` references a song that remains valid at the table level but is not available in the readable projection, the repository must treat the plan detail load as a failure state for that plan rather than silently dropping the item
- this failure must be testable at the repository level

## Schema Direction

The repository-owned schema direction for this slice is:

- `plans`
- `sessions`
- `session_items`

Required relationship change:

- `sessions` belong directly to `plans`
- `sessions.plan_id` is required
- `sessions.event_id` is removed from the active local schema path
- `sessions.position` is required for explicit ordering within a plan

Required item rule:

- `session_items` reference songs in this slice

This slice does not require solving future support for notes, attachments, media, or nested lists, but the schema should avoid making those future additions unnecessarily difficult.

## Authorization And Visibility Rules

- Plan visibility is organization-scoped.
- Session and session-item visibility are organization-scoped as well.
- Read access for this slice must be consistent across `plans`, `sessions`, and `session_items` for the same visible organization scope.
- This slice does not introduce planning-specific view-only capabilities. Active organization membership is the read boundary for the planning read path.
- Session visibility is inherited from the owning plan and organization.
- Session item visibility is inherited from the owning session and referenced song scope.
- The app must not expose plans or sessions outside the signed-in user's visible organization scope.
- Flutter may render role-aware affordances later, but authorization remains backend-enforced in this slice.
- In this slice, group scope is optional on plans. If `plan.group_id` is non-null, all child sessions must inherit the same `group_id`.
- This slice does not introduce session-level group overrides that diverge from the owning plan.
- Planning writes remain capability-based in backend-owned RBAC. This slice does not require separate read and write scope rules for planning data inside one visible organization.

## Testing Requirements

TDD is mandatory.

### Schema And Seed Verification

Cover:

- local schema reset producing the simplified planning structure
- local schema reset no longer requiring `events` for the planning read path
- seeded plans existing after local reset
- seeded sessions belonging directly to seeded plans
- seeded session items referencing visible seeded songs
- hidden-organization seeded plans remaining outside demo-user visibility

### Unit Tests

Cover:

- plan repository mapping
- session grouping and ordering
- session item to song summary mapping
- plan ordering rules
- failure behavior when a session item references a missing song

### Widget Tests

Cover:

- plan list rendering
- plan detail rendering
- multiple sessions rendering distinctly within one plan
- ordered song entries rendering inside a session
- signed-in navigation into the planning list and plan detail routes

### Integration Tests

Cover:

- authenticated user can load seeded plans from the backend
- selected plan detail renders sessions and ordered song entries
- organization scoping prevents cross-organization plan visibility
- signed-in users cannot reach planning routes while signed out

## Documentation Impact

This slice must update the canonical repository documents that currently describe the broader planning hierarchy.

Expected updates:

- `docs/domain/domain-model.md`
- `docs/architecture/architecture.md`
- `docs/product/vision.md`
- `README.md` if repository-level guidance or current slice summaries need adjustment

If the schema or product wording changes during implementation, the repository docs must be updated in the same change.

## Acceptance Criteria

This slice is complete when:

- the active planning direction is documented as `plan -> session -> session_items`
- the local Supabase schema and seed workflow produce usable plan, session, and session item records
- at least one authenticated read-only planning flow in Flutter renders those records
- session items visibly resolve to existing songs
- automated tests prove the minimal planning read path end-to-end

## Open Questions

- What final user-facing label should replace or complement `session` in the planning UI, if any?
- Should the first plan detail screen show one session expanded by default or all sessions expanded?
