# Planning Workspace UI Spec

> Status: Draft

## Goal

Redesign the planning list and planning detail surfaces as one coherent, responsive planning workspace while preserving the existing local-first planning behavior, backend-enforced authorization boundary, and repository-owned sync architecture.

## Problem

The repository already proves the planning domain workflow:

- users can view active-organization plans from the local planning projection
- users can create and edit plans locally first
- users can create, rename, delete, and reorder sessions locally first
- users can add, delete, and reorder song-backed session items locally first
- pending, failed, and conflicted planning mutations remain visible and retryable
- scoped plan/session song routes can open the reader with set context

The current UI still reads like an implementation surface for those capabilities. Plan list and plan detail are separate simple list/card screens, actions are concentrated in app bars or icon rows, sync status appears as raw mutation cards, and responsive layout does not yet match the more deliberate reader and song-library design direction. That makes a powerful local-first workflow feel less organized than the product model underneath it.

## Scope

- Treat plan list and plan detail as one product slice: the planning workspace.
- Add a planning workspace prototype under `docs/prototypes/` using the same visual vocabulary as the existing reader and song-list/picker prototypes.
- Define responsive tablet and wide behavior for the same workspace, not separate feature sets.
- Refine plan list hierarchy, active/selected plan presentation, empty/loading/error/offline states, and planning mutation status presentation.
- Refine plan detail hierarchy, plan header, session grouping, song rows, and session edit entry points.
- Refine the existing plan create/edit editor view enough that primary plan actions have a matching visual treatment.
- Replace the separate session rename editor concept with one session editor surface where users can rename the selected session and reorder its songs without interpreting raw icon rows.
- Keep route back navigation standard: when a planning surface can go back, use a top-left arrow affordance rather than a dedicated text back button in the content or action area.
- Keep existing local-first write flows and mutation invalidation behavior intact unless a presentation refactor exposes an existing bug.
- Keep reader navigation integration intact for song rows opened from a plan/session context.
- Keep tests centered on observable UI behavior and state surfaces.

## Non-Goals

- No backend schema, RPC, RLS, or authorization changes.
- No new planning domain behavior.
- No drag-and-drop in this slice.
- No multi-select editing.
- No calendar view.
- No rich conflict-resolution workflow.
- No new session item types such as notes, attachments, or headings.
- No cross-plan session moves or cross-session item moves.
- No global navigation redesign outside the planning workspace entry and return paths needed by the existing app.

## Product Direction

Planning should feel like one workspace for preparing a service or rehearsal, not two unrelated CRUD screens.

The user-facing model is:

1. choose or create a plan
2. understand its current state
3. organize sessions
4. add and order songs
5. see local pending/conflict status without losing the main workflow
6. open a planned song into the reader with set context preserved

The UI should expose the domain hierarchy without exposing raw infrastructure concepts. Pending and conflicted local changes remain visible, but they should read as operational status attached to plans, sessions, or the workspace, not as database mutation records.

## Responsive Layout Decisions

### Current Navigation, Adaptive Layout

Tablet and wide layouts must keep the current planning navigation model: plan list and plan detail remain separate visible route surfaces. The slice still treats them as one product workflow through shared visual language, state taxonomy, and action vocabulary.

Wide and tablet layouts should adapt each route surface independently:

- plan list route shows the plan selector/list surface
- plan detail route shows the selected plan builder surface

Tablet must not stack plan list and plan detail on the same screen. Wide layout also does not require a split-pane workspace in this slice. If a later slice introduces split-pane planning, it needs its own spec because it changes navigation and selection behavior.

### Visual Consistency

The prototype and Flutter implementation should align with the existing `docs/prototypes` direction:

- quiet operational surfaces
- clear top bars and status surfaces
- compact controls
- list rows with strong title-first hierarchy
- badges for state and metadata
- icon buttons for compact repeated actions
- restrained cards only for repeated items or focused grouped surfaces

Planning should not become a decorative dashboard. It should stay dense enough for repeated preparation work while being visually calmer than the current raw list/card layout.

## Workspace Surfaces

### Plan List

The plan list should help users choose the right plan and understand whether a plan needs attention.

Required behavior:

- show plan name, optional description, scheduled date when present, and lightweight operational status
- do not invent plan lifecycle statuses such as `Ready` or `Draft`; plan-row badges should represent existing local-first/sync conditions such as local changes, conflict, or authorization denied
- distinguish empty planning data from loading and retryable failure
- surface pending or failed planning changes without replacing the list
- keep create-plan available as a primary action
- keep access to existing retry behavior for failed planning mutations

Search and advanced filters are not required for this slice unless they can be added without widening the behavior surface. The main objective is visual and information hierarchy, not catalog-style discovery.

### Plan Detail

The plan detail should behave as a service builder.

Required behavior:

- show a plan header with name, description, scheduled date when present, and edit action
- show route back navigation as a top-left arrow when the current navigation stack supports going back
- show sessions in current merged local-first order
- show a clear session editor entry point without crowding the session title
- show session items in current merged local-first order
- expose session editing from each session on plan detail
- show inline session-name editing, add-song, and song-order controls once the session editor is open
- preserve scoped reader navigation when a song row opens the reader
- render empty session state explicitly
- render no-session state explicitly
- show pending/conflict status in a way that does not obscure the session and song list

The current up/down reorder behavior may remain the implementation interaction for this slice. Drag-and-drop can be designed later once the workspace hierarchy is stable.

## State Model

The workspace must distinguish these states where applicable:

- loading plans
- loading plan detail
- no plans
- plan detail unavailable or load failure
- no sessions in a plan
- empty session
- no local song catalog available for add-song
- pending planning mutation
- failed retryable planning mutation
- conflict planning mutation with per-entry `Keep mine` and `Discard mine` choices where the app has enough local mutation context to present the affected item
- authorization-denied planning mutation
- offline cached planning data remains usable

Offline cached planning status may be shown only from existing planning sync, connectivity, or cached-data state already exposed by providers. This slice must not create a second connectivity or planning-sync state machine.

State copy and layout should remain consistent with existing app vocabulary. Sync state must not imply that Flutter is the authority for authorization or canonical acceptance.

## Architecture Constraints

- Presentation code reads planning data through existing providers and repositories.
- UI must not merge raw projection rows with raw mutation rows.
- UI may derive display grouping from already exposed planning mutation records, but it must not create a second planning write state machine.
- Backend-enforced authorization remains the durable authority.
- The local-first projection plus mutation-store boundary from `ADR-014-planning-write-projection-mutation-boundary.md` remains unchanged.
- Any durable product or architecture decisions discovered during implementation must be mirrored in repository docs, not only in the prototype.

## Prototype Requirements

Create a prototype companion in `docs/prototypes/` before implementation planning:

- `planning-workspace-mockup.html`
- `planning-workspace-mockup.css`
- `planning-workspace-mockup.js`

The prototype should include reviewer controls matching the existing prototype style:

- screen: plan list, plan detail, plan editor, session editor
- layout: tablet, wide
- theme: standard, high contrast, black
- state: default, loading, empty, no sessions, empty session, catalog unavailable, offline cached, pending mutation, conflict, authorization denied, retryable failure

The prototype should show plan selection, plan detail behavior, the plan editor, and the combined session editor in one artifact.

## Acceptance Criteria

1. A repository-owned planning workspace prototype exists under `docs/prototypes/` and reuses the existing prototype visual vocabulary.
2. Plan list and plan detail are treated as one coherent planning workspace in spec, plan, and implementation.
3. Tablet and wide layouts keep the existing plan-list-to-plan-detail navigation model and never stack both route surfaces on the same tablet screen.
4. Plan list renders clear loading, empty, retryable failure, and mutation-status states.
5. Plan detail renders clear loading, retryable failure, no-session, empty-session, pending, conflict, and authorization-denied states.
6. Plan create/edit and the combined session editor views match the planning workspace visual vocabulary.
7. Session rename and song reorder affordances live in the combined session editor and preserve existing local-first behavior.
8. Each session on plan detail exposes a visible entry point into session editing.
9. Conflict state presents affected local changes individually with `Keep mine` and `Discard mine` choices.
10. Back-capable planning surfaces use a top-left arrow affordance and do not expose a separate text back button in the main action area.
11. Existing plan create/edit and session create/rename/delete/reorder behaviors remain available.
12. Existing session-item add/delete/reorder and scoped reader navigation remain available.
13. Planning mutation retry remains available for failed entries.
14. UI code remains provider/repository-driven and does not bypass backend-enforced authorization or repository-owned local-first boundaries.
15. Widget tests cover the main responsive/state surfaces and critical existing planning actions after refactor.

## Validation Notes

- Validate tablet and wide Flutter viewports.
- Validate with normal synced data, pending local mutations, conflict mutations, and no cached song catalog for add-song.
- Validate navigation from plan song row into scoped reader and back.
- Run app-only verification for UI-only implementation unless the final plan changes backend, migration, or local Supabase behavior.
