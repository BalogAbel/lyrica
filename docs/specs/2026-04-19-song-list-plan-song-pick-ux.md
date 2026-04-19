# Song List And Plan Song Pick UX Spec

> Status: Draft

## Goal

Define the next focused UX slice for the active-organization song catalog by improving how users browse songs in the song library and how they pick songs into plan sessions, without widening scope into song editing, planning redesign, or new backend-owned domain behavior.

## Problem

The repository already proves local-first song reads and local-first planning writes, but the two song-selection surfaces remain too primitive for routine use:

- the song library is a flat title list with fixed ordering and no in-surface discovery tools
- the plan-session picker is a static dialog list with no search, no explicit empty-state taxonomy, and no responsive behavior

That gap creates a product mismatch. The app can already keep songs and planning locally usable offline, but it still makes common browse and add flows scale poorly as catalogs grow.

This slice should improve discoverability and add speed while preserving the current local-first, backend-enforced, projection-plus-mutation architecture.

## Companion Artifact

This spec is grounded by [docs/specs/2026-04-19-song-list-plan-song-pick-ux-discovery.md](docs/specs/2026-04-19-song-list-plan-song-pick-ux-discovery.md).

Visual companion prototype:

- `docs/prototypes/song-list-plan-picker-mockup.html`

## Scope

- Define the canonical UX difference between:
  - song library browse flow
  - plan session song picker flow
- Add local search behavior to both flows.
- Define minimal, scope-controlled filter behavior.
- Define minimal, scope-controlled sort behavior.
- Define empty, loading, error, unavailable, offline, and no-results states relevant to both flows.
- Define selection and add-flow UX for plan-session song picking.
- Define lightweight state persistence rules where needed.
- Define responsive, accessibility, keyboard, and mobile expectations that fit the current Flutter patterns.

## Non-Goals

- No song create/edit/delete redesign.
- No plan list or plan detail visual redesign beyond the picker surface and the local controls needed around it.
- No backend contract expansion solely to support rich metadata facets in this slice.
- No multi-select add flow.
- No drag-and-drop.
- No fuzzy search ranking, server-side search, or cross-organization song discovery.
- No attachment or note item picking.
- No full command palette or global keyboard shortcut system.
- No restart-durable persistence for browse or picker UI state.

## Product Rule

Use one local song catalog, two different jobs:

- song library helps users browse, inspect, and open songs
- plan song picker helps users make a fast, safe add decision inside one session

The picker may reuse browse vocabulary, but it must not become a second general-purpose song-library screen.

## Current Repository Constraints

- Both flows read from the active-organization local-first song catalog.
- `SongSummary` currently exposes `id`, `title`, `slug`, and `version`; this slice must not assume richer local browse metadata unless another approved slice expands that contract first.
- Song library order is currently title ascending from the local catalog store.
- Plan-session add already excludes duplicate songs already present in the target session.
- Picker availability already depends on a locally available cached song catalog.
- Authorization remains backend-enforced; client preflight checks exist only for UX and local validation.

## User Experience Outcomes

### Song Library Browse Flow

The song library must support quick narrowing and reopening of songs from the active local catalog without leaving the browse screen to "hunt" manually through a long flat list.

The browse flow should answer:

- Can I find a song quickly?
- Can I narrow to songs that need my attention?
- Can I reopen a song and return to the same narrowed list state?

### Plan Session Song Picker Flow

The picker must support a fast, low-friction "choose one eligible song for this session" action without losing plan context.

The picker should answer:

- Which songs can still be added to this session?
- Can I find the intended song quickly?
- If no song can be added, is the reason clear?

## Core UX Rules

### Shared Rules

- Search is local-only against the already available active-organization song catalog.
- Search updates results immediately on text change.
- Search matching must be case-insensitive.
- Search starts from song title; this slice does not require richer metadata search.
- Loading, unavailable, empty, and no-results states must use explicit copy rather than silently rendering blank space.
- Offline mode must continue to read from local data and must not imply weaker local access than the current repository already guarantees.

### Song Library Rules

- Song library keeps a persistent search field above the visible results.
- Song library exposes a minimal filter control with exactly:
  - `All`
  - `Pending sync`
  - `Conflicts`
- Song library keeps default sort as `Title (A-Z)`.
- Song library exposes a visible sort control only if implementation can support at least one second clean local option without widening the data contract; otherwise the slice ships with fixed `Title (A-Z)` ordering only.
- Song-library search, filter, and sort state must survive rebuilds and back navigation from the reader during the same app session.
- Song-library browse state does not need restart persistence.
- Song-library browse state belongs to the signed-in active-catalog boundary and must reset on explicit sign-out or active-organization change.

### Plan Song Picker Rules

- Picker only shows songs eligible to add to the target session.
- Songs already present in that session are excluded before search and sort are applied.
- Picker search is local-only and title-based.
- Picker keeps default sort as `Title (A-Z)`.
- Picker does not add a visible sort control unless the same second clean local option already exists in the shared song-library vocabulary.
- Picker does not add a broader explicit filter set in this slice; the eligibility boundary is the filter.
- Picker state is ephemeral, created fresh for each picker open, and resets whenever the picker closes.
- Picker state must not survive picker reopen, sign-out, or active-organization change.
- Picker must return the user directly to the plan detail after local add succeeds; no intermediate confirmation surface.

## Search Behavior

### Matching

- Match against normalized song title.
- Ignore case.
- Trim surrounding whitespace from the query before matching.
- Empty query restores the current filter/sort result set.

### Result Scoping

- Song library search runs against the current local song-library data set after the active filter is applied.
- Picker search runs against the already-eligible song set for the current session.

## Filter Behavior

### Song Library

The song library filter is intentionally operational, not metadata-driven.

- `All` shows the normal visible song catalog.
- `Pending sync` narrows to songs with pending local mutation state.
- `Conflicts` narrows to songs with conflict mutation state.

This keeps filter scope aligned with existing local mutation concepts instead of expanding the song summary contract for tags, artists, or worship-key metadata.

To make that implementable without widening `SongSummary`, the UI must derive browse rows from a repository-owned local join between:

- visible `SongSummary` records
- local song mutation records for the same active user and organization

The derived browse row is a presentation-level view model, not a new backend contract.

### Plan Song Picker

The picker uses one implicit filter: `eligible songs for this session`.

That means:

- songs already present in the session are excluded
- songs not available in the local cached catalog are unavailable for add

This slice does not add user-controlled metadata filters to the picker.

## Sort Behavior

### Required Sort

- `Title (A-Z)` is required in both flows and remains the default.

### Optional Second Sort

The implementation plan may include one second sort for the song library only if it can be backed by already available local state without broadening the slice. If no such option is cleanly available, the slice should ship with fixed title ordering and no visible sort control.

The picker should not introduce picker-only sort semantics in this slice.

## State Taxonomy

### Song Library

Required distinct states:

- `Loading` while song list data is still resolving
- `Unavailable` when no local cached catalog exists yet
- `Empty catalog` when the local catalog exists but contains no songs
- `Browse results` when at least one song matches current controls
- `No results` when the catalog exists but current search/filter returns nothing
- `Offline cached` when catalog remains readable from local cache without connectivity
- `Refresh failed with cache preserved` when last refresh failed but cached songs remain usable
- `Retryable error` when the route cannot load and retry is meaningful

### Plan Song Picker

Required distinct states:

- `Unavailable` when no local cached catalog exists for eligible add
- `Loading` when the picker is preparing its local result set
- `Eligible results` when at least one song can be added
- `No eligible songs` when every visible song is already used in the session
- `No results` when eligible songs exist but the current query matches none
- `Add in progress` only if needed to prevent duplicate submission during the local mutation call

Picker failure states should stay narrow. The picker should rely on the existing planning mutation/error surfaces for post-submit sync failures instead of inventing a second sync-status system inside the picker itself.

## Selection And Add Flow

### Entry

- Each session keeps one visible `Add song` affordance.
- When no local cached catalog exists, the affordance remains disabled and explanatory copy stays visible near the control.

### Picker Presentation

- Wide layouts use a dialog-style picker.
- Narrow layouts use a full-screen sheet or page-style picker.
- Both presentations expose the same search, sort, empty-state, and selection rules.

### Selection

- A song row is directly actionable.
- One tap/click adds the selected song locally.
- The picker closes after a successful local record.
- The updated session item appears immediately in plan detail through the existing local-first planning write overlay.

### Duplicate Prevention

- The picker must not show songs already present in the target session.
- If a stale race still attempts a duplicate local add, existing service-layer validation remains the final client-side guard before backend enforcement.

## State Persistence

- Song-library query, filter, and sort are route-scoped UI state.
- That state must survive route rebuilds and back navigation from the song reader during the same app run.
- That state must remain scoped to the current signed-in active-catalog boundary only.
- When sign-out clears the active catalog context, browse state resets instead of leaking into the next signed-in session.
- When the active organization changes, browse state resets for the new boundary instead of carrying the previous organization's query/filter/sort across tenants.
- That state does not need persistence across app restart or sign-out.
- Picker state is modal-scoped, created per presentation, and discarded when picker closes.
- Reopening the picker starts from the default empty query and default sort for the current session.

## Accessibility, Keyboard, And Mobile Expectations

- Search controls must use visible labels, not placeholder-only semantics.
- Icon-only controls must keep descriptive tooltips or semantic labels.
- Keyboard order must be deterministic: search, then filter and sort controls when present, then result rows.
- Enter/Space on a focused song row must open or add, matching the flow.
- Escape/back must dismiss the picker.
- Touch targets must remain comfortable on phone and tablet layouts.
- Narrow-layout picker controls must be usable without hover.
- The plan detail must remain readable and actionable after the picker closes; focus should return to a sensible session-local control.

## Architecture Boundaries

- Search, filter, and sort remain client-side operations over repository-owned local read data.
- This slice must not move authorization, duplicate-song enforcement, or canonical acceptance into Flutter.
- Song-library operational filters may depend on local mutation store data because that is already repository-owned local state.
- Song-library operational filters require one explicit normalization seam that joins local song summaries with local mutation status for the current active-catalog boundary before filter and search are applied.
- Picker eligibility depends on the same local song catalog and planning detail already present in the current architecture.

## Testing Requirements

TDD is mandatory when implementation starts.

### Unit Tests

Cover:

- song-library query/filter/sort state mapping
- picker eligibility filtering
- case-insensitive local search behavior
- song-library operational filter behavior for pending/conflict states
- state-persistence rules for browse flow

### Widget Tests

Cover:

- song-library search/filter/sort controls and no-results state
- song-library offline/unavailable/empty states staying distinct
- picker search behavior
- picker unavailable/no-eligible/no-results state taxonomy
- responsive picker presentation rules at narrow versus wide layouts
- keyboard and focus behavior for actionable rows where practical

### Integration Tests

Cover:

- browse a narrowed song list, open a song, return to preserved browse state
- open picker from plan detail, search, add a song, and confirm immediate local detail update
- offline cached browse and picker behavior after prior successful catalog sync

## Deferred And Out-Of-Scope Notes

- richer metadata search such as artist, tags, key, or tempo
- metadata-driven filter chips
- multi-select add
- drag-and-drop reorder polish tied to this picker work
- restart-durable browse preferences
- server-side search or remote-first picker fallback

If later product work requires rich metadata filters, that must be planned as an explicit contract-expansion slice rather than being smuggled into this UX slice.

## Success Criteria

- Users can search songs locally in both the song library and the plan-session picker.
- Song library gains explicit, narrow discovery controls without becoming a redesign project.
- Plan song picker becomes fast, responsive, and explicit about unavailable, empty, and no-result cases.
- Browse and picker flows share vocabulary where helpful while staying distinct in purpose.
- The resulting implementation scope remains small enough for mergeable slices and does not widen backend or authorization boundaries.
