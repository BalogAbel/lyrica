# Song List And Plan Song Pick UX Implementation Plan

> Status: Delivered

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Implement the approved song-library browse UX and plan-session song picker UX so both flows support local title search, explicit state handling, and scope-controlled discovery controls without redesigning unrelated song or planning features.

**Architecture:** Keep the current local-first and backend-enforced boundaries intact. Add small presentation-layer state holders for browse controls, derive filtered/sorted views from existing repository-owned local data, and keep picker eligibility inside planning-aware local read flows. Reuse existing song catalog, mutation store, and planning write services instead of introducing new remote APIs or metadata contracts.

**Tech Stack:** Flutter, Material 3, Riverpod, go_router, flutter_test

---

## Slice Strategy

### First Implementation Slice

Implement song-library search plus explicit no-results state first. It is the smallest user-visible slice, reuses the existing local catalog contract, and establishes the search-state pattern that the picker can follow.

This branch now carries the combined first slice plus the browse filter/sort expansion:

- song-library title search
- explicit no-results state
- route-scoped browse query seam
- plan-session picker title search
- explicit picker no-eligible and no-results states
- responsive picker shell seam
- focused cross-route integration flow test
- keyboard and focus polish for picker dismissal and add control return

Later slices, if any, are limited to new requirements or extra polish beyond this shipped scope.

### Required Integration Gate

Do not treat the full feature as widget-test-only work. Route-state persistence and picker close/add behavior now have a dedicated integration test in this branch because they span navigation, modal presentation, and immediate local planning overlay updates. If future slices add new cross-route behavior, extend that coverage again.

### Deferred / Out-Of-Scope

- artist/tag/key/tempo search
- metadata-driven filter chips
- restart-durable browse preferences
- multi-select add
- drag-and-drop picker or list interactions
- backend contract expansion for richer song summary metadata

## Review Checkpoints

- After Task 1: confirm the browse-state seam is small and route-scoped.
- After Task 3: confirm picker state taxonomy matches the spec exactly.
- After Task 5: run a focused doc review to ensure spec, plan, and any deferred note still agree.

### Task 1: Add Song-Library Browse State And Title Search

**Files:**
- Create: `apps/lyron_app/lib/src/presentation/song_library/song_library_browse_row.dart`
- Create: `apps/lyron_app/lib/src/presentation/song_library/song_library_browse_state.dart`
- Create: `apps/lyron_app/lib/src/presentation/song_library/song_library_browse_controller.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_library/song_library_providers.dart`
- Test: `apps/lyron_app/test/presentation/song_library/song_library_providers_test.dart`
- Test: `apps/lyron_app/test/presentation/song_library/song_library_browse_controller_test.dart`

- [x] **Step 1: Write failing tests for route-scoped browse state**

Cover:

- default empty query
- case-insensitive title search
- query trimming
- state reset behavior when explicitly requested
- browse-state persistence across provider recomputation during one app session
- browse-state reset on explicit sign-out
- browse-state reset on active-organization change

Run:

```bash
flutter test \
  apps/lyron_app/test/presentation/song_library/song_library_providers_test.dart \
  apps/lyron_app/test/presentation/song_library/song_library_browse_controller_test.dart
```

Expected: FAIL because no browse-state seam exists yet.

- [x] **Step 2: Introduce focused browse-state types**

Add a small browse state that owns only:

- query string
- active operational filter
- active sort selection

Do not put loading or catalog sync state into this object; those remain owned by existing catalog state.

- [x] **Step 3: Add explicit browse-row normalization seam**

Create a small browse-row type that joins:

- one visible `SongSummary`
- zero or one local mutation status for that song in the current active-catalog boundary

Use this row as the filterable/searchable input for operational browse filters. Do not push mutation-awareness into `SongSummary`.

- [x] **Step 4: Derive searched song-library results from normalized local data**

Extend the song-library provider layer so the browse-visible list can be derived from:

- normalized browse rows built from current local song list plus mutation entries
- current browse query
- current operational filter
- current sort

Keep matching title-only for this slice.
Keep one raw catalog-list provider for non-browse consumers such as the plan song picker, and add a separate browse-derived provider for the song-list screen so picker eligibility never inherits browse query/filter state.

- [x] **Step 5: Re-run the focused provider/controller tests**

Run:

```bash
flutter test \
  apps/lyron_app/test/presentation/song_library/song_library_providers_test.dart \
  apps/lyron_app/test/presentation/song_library/song_library_browse_controller_test.dart
```

Expected: PASS

### Task 2: Add Song-Library Search, Filter, Sort, And State Surfaces

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_library/song_list_screen.dart`
- Modify: `apps/lyron_app/lib/src/shared/app_strings.dart`
- Test: `apps/lyron_app/test/presentation/song_library/song_list_screen_test.dart`

- [x] **Step 1: Write failing widget tests for browse controls and no-results states**

Cover:

- visible search field on the song list
- operational filter controls
- fixed title ordering, plus sort control presence only if a second approved local option exists
- no-results state for unmatched query
- distinct unavailable versus empty-catalog behavior remaining intact
- browse-state preservation after navigating to the reader and back

Run:

```bash
flutter test apps/lyron_app/test/presentation/song_library/song_list_screen_test.dart
```

Expected: FAIL because the current screen only renders the flat list.

- [x] **Step 2: Add browse controls without disturbing existing app-bar actions**

Place search and narrow discovery controls below the existing status surface and above the list. Keep the current refresh, add-song, planning-entry, and sign-out actions intact.

- [x] **Step 3: Render explicit no-results copy**

Add dedicated copy for:

- no local catalog yet
- empty catalog
- no matches for current browse controls

Do not collapse these into one generic empty message.

- [x] **Step 4: Re-run the song-list widget test**

Run:

```bash
flutter test apps/lyron_app/test/presentation/song_library/song_list_screen_test.dart
```

Expected: PASS

### Task 3: Add Planning Picker Query State, Eligibility Rules, And Empty-State Taxonomy

**Files:**
- Create: `apps/lyron_app/lib/src/presentation/planning/session_song_picker_state.dart`
- Create: `apps/lyron_app/lib/src/presentation/planning/session_song_picker.dart`
- Modify: `apps/lyron_app/lib/src/presentation/planning/plan_detail_screen.dart`
- Modify: `apps/lyron_app/lib/src/shared/app_strings.dart`
- Test: `apps/lyron_app/test/presentation/planning/plan_detail_screen_test.dart`
- Test: `apps/lyron_app/test/presentation/planning/session_song_picker_test.dart`

- [x] **Step 1: Write failing picker tests**

Cover:

- eligible songs exclude songs already present in the session
- local title search inside the picker
- explicit no-eligible state when every visible song is already present
- explicit no-results state when the query matches nothing
- fixed title ordering, plus sort control presence only if a second shared local option exists
- disabled/unavailable add-song affordance when no local cached catalog exists
- picker query resets when the picker closes and opens again

Run:

```bash
flutter test \
  apps/lyron_app/test/presentation/planning/plan_detail_screen_test.dart \
  apps/lyron_app/test/presentation/planning/session_song_picker_test.dart
```

Expected: FAIL because the current picker is an inline static `AlertDialog` list.

- [x] **Step 2: Extract the picker into its own widget**

Move picker content out of `plan_detail_screen.dart` so search, empty-state taxonomy, and responsive presentation can be tested without loading the whole plan screen.

Keep picker state widget-owned or presentation-owned per open. Construct fresh picker state each time the open action runs, dispose it on close, and verify reopen returns to the default empty query and default ordering. Do not hoist picker query/sort into app-global state that can leak across reopen or tenant changes.

- [x] **Step 3: Keep picker logic title-based and local-only**

Apply search and sort after duplicate exclusion. Do not fetch remote data or add richer metadata logic.

- [x] **Step 4: Re-run picker tests**

Run:

```bash
flutter test \
  apps/lyron_app/test/presentation/planning/plan_detail_screen_test.dart \
  apps/lyron_app/test/presentation/planning/session_song_picker_test.dart
```

Expected: PASS

### Task 4: Make Picker Responsive For Narrow And Wide Layouts

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/planning/plan_detail_screen.dart`
- Modify: `apps/lyron_app/lib/src/presentation/planning/session_song_picker.dart`
- Test: `apps/lyron_app/test/presentation/planning/plan_detail_screen_test.dart`
- Test: `apps/lyron_app/test/presentation/planning/session_song_picker_test.dart`

- [x] **Step 1: Add failing responsive-presentation tests**

Cover:

- wide layout uses dialog-style picker
- narrow layout uses full-screen sheet/page-style picker
- both paths expose the same search field, shared sort semantics, and result rows

Run:

```bash
flutter test \
  apps/lyron_app/test/presentation/planning/plan_detail_screen_test.dart \
  apps/lyron_app/test/presentation/planning/session_song_picker_test.dart
```

Expected: FAIL because only one fixed dialog presentation exists today.

- [x] **Step 2: Add one presentation seam for picker form factor**

Resolve dialog versus narrow full-screen presentation at the presentation boundary only. Do not move plan-write orchestration into a new layer.

- [x] **Step 3: Re-run responsive picker tests**

Run:

```bash
flutter test \
  apps/lyron_app/test/presentation/planning/plan_detail_screen_test.dart \
  apps/lyron_app/test/presentation/planning/session_song_picker_test.dart
```

Expected: PASS

### Task 5: Polish Keyboard, Focus, And Copy Consistency

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_library/song_list_screen.dart`
- Modify: `apps/lyron_app/lib/src/presentation/planning/session_song_picker.dart`
- Modify: `apps/lyron_app/lib/src/shared/app_strings.dart`
- Modify: `docs/specs/2026-04-19-song-list-plan-song-pick-ux.md`
- Modify: `docs/plans/2026-04-19-song-list-plan-song-pick-ux.md`
- Test: `apps/lyron_app/test/presentation/song_library/song_list_screen_test.dart`
- Test: `apps/lyron_app/test/presentation/planning/session_song_picker_test.dart`

- [x] **Step 1: Add failing focus and semantics tests where practical**

Cover:

- search field has explicit label text
- icon or row actions preserve tooltip/semantic labels
- Tab traversal reaches search, then any filter/sort control, then result rows in deterministic order
- Enter/Space on a focused song row triggers open or add
- back/Escape dismisses the picker

Run:

```bash
flutter test \
  apps/lyron_app/test/presentation/song_library/song_list_screen_test.dart \
  apps/lyron_app/test/presentation/planning/session_song_picker_test.dart
```

Expected: FAIL for the new accessibility/focus expectations before implementation.

- [x] **Step 2: Align copy and focus-return behavior**

Ensure new strings and focus handling match the spec, especially:

- browse no-results copy
- picker no-eligible copy
- picker no-results copy
- search labels
- focus return to the session-local add control after picker dismissal

- [x] **Step 3: Re-run focused widget tests**

Run:

```bash
flutter test \
  apps/lyron_app/test/presentation/song_library/song_list_screen_test.dart \
  apps/lyron_app/test/presentation/planning/session_song_picker_test.dart
```

Expected: PASS

### Task 6: Verify, Update Docs In Lockstep, And Prepare Handoff

**Files:**
- Create: `apps/lyron_app/test/integration/song_list_plan_song_pick_flow_test.dart`
- Modify: `docs/specs/2026-04-19-song-list-plan-song-pick-ux-discovery.md`
- Modify: `docs/specs/2026-04-19-song-list-plan-song-pick-ux.md`
- Modify: `docs/plans/2026-04-19-song-list-plan-song-pick-ux.md`

- [x] **Step 1: Reconcile implementation against discovery/spec/plan**

Confirm the delivered behavior still matches:

- title-based local search
- narrow operational filter scope
- picker eligibility-only scope
- explicit state taxonomy
- route-scoped persistence for browse flow only

- [x] **Step 2: Add targeted integration coverage for cross-route and picker flows**

Create one focused integration test that proves:

- narrow song-library search survives opening a song and returning to the list
- song-library operational filter changes the visible browse result without mutating the raw catalog source used elsewhere
- picker search narrows eligible songs, adds one song, closes, and shows the new row immediately in plan detail
- opening the picker for a fully used session shows the explicit no-eligible state
- reopening the picker resets its local query state

Run:

```bash
flutter test apps/lyron_app/test/integration/song_list_plan_song_pick_flow_test.dart
```

Expected: PASS

- [x] **Step 3: Run app-only verification**

Run:

```bash
flutter test
flutter analyze
./scripts/verify.sh --skip-migrations
```

Expected: PASS

Use full `./scripts/verify.sh` only if implementation unexpectedly touches backend-backed song read, planning contract, or local Supabase workflow behavior.

- [x] **Step 4: Update status lines and deferred notes if scope changes**

If implementation narrows or expands the slice, update the spec/plan status notes and add a `docs/deferred/` entry only for consciously deferred correctness or workflow behavior, not generic polish.
