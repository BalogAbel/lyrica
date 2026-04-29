# Planning Workspace UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor the planning list and planning detail surfaces into one coherent workspace UI slice with clearer responsive hierarchy, inline session-name editing, inline add-song entry points, simple native drag-and-drop reorder motion for sessions and songs, long-press-only touch reorder, explicit handling for loading, empty, simple per-mutation conflict actions, retryable failure, and authorization-denied states, and persisted mutation origin snapshots so local edits can rebase or discard from the current baseline.

**Architecture:** Keep user-facing planning domain capabilities, the local-first read model, and backend-enforced authorization boundary unchanged. Concentrate the UI work in the Flutter presentation layer by introducing a shared workspace shell, moving session rename/add-song/reorder controls into inline session headers/cards, and making drag-and-drop reorder the long-term target interaction for sessions and songs with simple built-in motion and long-press-only touch start. Keep plan detail as a single route surface that still opens the scoped reader from song rows. Tablet and wide layouts should adapt each route independently, never stacking plan list and plan detail on the same screen. The planning write layer should preserve an origin snapshot for each local mutation so later rebase, discard, and canonical reconciliation can reason about the pre-edit baseline.

**Tech Stack:** Flutter, Material 3, Riverpod, go_router, Drift, flutter_test

**Prototype note:** The companion prototype under `docs/prototypes/` is part of the same repository-owned slice. Keep prototype, spec, plan, and implementation consistent before merge; do not treat prototype decisions as external-only guidance.

---

### Task 1: Write Failing Widget Tests For The Workspace Refactor

**Files:**
- Modify: `apps/lyron_app/test/presentation/planning/plan_list_screen_test.dart`
- Modify: `apps/lyron_app/test/presentation/planning/plan_detail_screen_test.dart`
- Modify: `apps/lyron_app/test/presentation/planning/session_song_picker_test.dart`

- [x] **Step 1: Add failing tests for the new workspace hierarchy**

Cover:

- plan list still shows create-plan, loading, empty, retryable failure, and mutation-status surfaces
- plan detail shows a single route surface with a top-left back arrow when navigation can pop
- tablet layout keeps plan list and plan detail as separate surfaces instead of stacking them
- plan detail shows a session-name edit icon and inline add-song entry point for each session
- the session-name popup exposes a single text field prefilled with the current session name
- conflict state renders affected local changes one by one with `Keep mine` and `Discard mine`
- session song picker still works, but is opened only from the inline session add-song entry point

Run:

```bash
cd apps/lyron_app && flutter test \
  test/presentation/planning/plan_list_screen_test.dart \
  test/presentation/planning/plan_detail_screen_test.dart \
  test/presentation/planning/session_song_picker_test.dart
```

Historical note: this step originally failed before the workspace refactor landed.

- [x] **Step 2: Add focused expectations for the plan editor and session editor chrome**

Extend the detail tests to pin down:

- plan editor uses the same workspace visual language as the rest of planning
- session name popup contains a single editable session title field
- inline session cards contain add-song and song-order controls in place
- back-capable planning surfaces use an arrow affordance instead of a text back button in the content area

- [x] **Step 3: Add explicit conflict and retry state coverage**

Add cases that prove:

- conflict rows are rendered individually, not as one combined conflict banner or merge editor
- each conflict row offers only the simple `Keep mine` and `Discard mine` actions
- retryable planning mutation state keeps the list/detail content visible while still exposing retry actions

- [x] **Step 4: Re-run the focused widget tests**

Run the same `flutter test` command again.

Expected: PASS after the presentation refactor is complete.

### Task 2: Refactor Planning Presentation Into A Shared Workspace Shell

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/planning/plan_list_screen.dart`
- Modify: `apps/lyron_app/lib/src/presentation/planning/plan_detail_screen.dart`
- Create: `apps/lyron_app/lib/src/presentation/planning/widgets/planning_workspace_shell.dart`
- Create: `apps/lyron_app/lib/src/presentation/planning/widgets/planning_workspace_status_surface.dart`
- Modify: `apps/lyron_app/lib/src/presentation/planning/session_song_picker.dart`

Implementation note: the final slice kept the plan editor, name-only session popup, session card, and session item row as private presentation widgets inside `plan_list_screen.dart` and `plan_detail_screen.dart` because they are not reused outside those route surfaces.

- [x] **Step 1: Extract a shared workspace shell and status surface**

Create a small shell widget that owns:

- the quiet planning surface chrome
- the responsive content width rules for list/detail/editor surfaces
- the top-left back arrow placement when a route can pop
- the shared mutation/status presentation used by both list and detail

Keep the shell presentation-only. Do not move any repository or provider logic into it.

- [x] **Step 2: Move plan list and plan detail onto the new shell**

Update the list and detail screens so they:

- render one route surface at a time
- reuse the shared shell styling
- keep create-plan and edit-plan actions available
- keep existing local-first list/detail data loading behavior unchanged

- [x] **Step 3: Replace inline session rename/add-song controls with inline session-header actions**

Create inline session-header actions that own:

- a pencil icon that opens a small session-name popup with the current session name prefilled
- an inline add-song entry point on the session card
- drag/reorder affordances for songs and sessions
- session-item delete/reorder controls if they already belong to the same local editing flow

Keep add-song inline on the session card. Plan detail should expose a session name edit icon rather than the old inline control cluster. Use the built-in drag/reorder affordances for the session and song rows rather than a custom animation system, keep the motion native and lightweight, and require long press before touch drag starts.

- [x] **Step 4: Keep the scoped reader and existing write flow boundaries intact**

Preserve:

- plan song-row navigation into the scoped reader with route context
- the local-first write service calls for plan, session, and session-item mutations
- the current repository-backed mutation retry behavior

Only move presentation entry points. Do not change the underlying write model unless tests expose a real bug.

- [x] **Step 5: Re-run the focused widget tests**

Run the same `flutter test` command again.

Expected: PASS.

### Task 3: Update Copy, Polish States, And Verify The UI Slice

**Files:**
- Modify: `apps/lyron_app/lib/src/shared/app_strings.dart`
- Modify: `docs/specs/2026-04-24-planning-workspace-ui.md` if implementation reveals a durable wording or scope mismatch
- Modify: `docs/architecture/architecture.md` if a durable presentation boundary needs to be recorded
- Modify: `docs/testing/testing-strategy.md` if the new planning workspace tests add a standing expectation

- [x] **Step 1: Tighten planning copy for the new workspace surfaces**

Update labels and helper text so they match the new UI hierarchy:

- session name edit icon and popup labels
- inline add song labels for session cards
- explicit conflict copy that describes one affected local change at a time and offers only simple `Keep mine` / `Discard mine` actions
- back-arrow-oriented planning navigation copy where needed

- [x] **Step 2: Verify the responsive state surfaces at the widget level**

Run targeted Flutter tests for:

- plan list
- plan detail
- session song picker

Keep the presentation verification focused on plan list, plan detail, and picker behavior. Because this slice also preserves origin snapshots in the local mutation store, run focused local database, write-service, and sync-controller tests for that write-layer persistence.

- [x] **Step 3: Review the UI slice for any durable documentation drift**

If the implementation changes any lasting product wording, architecture boundary, or test expectation, mirror that in the repository docs in the same change. Do not leave a durable behavior change only in code.

- [x] **Step 4: Run the final verification set**

Run:

```bash
cd apps/lyron_app && flutter test \
  test/application/planning/planning_write_service_test.dart \
  test/application/planning/planning_mutation_sync_controller_test.dart \
  test/offline/planning/planning_mutation_store_test.dart \
  test/presentation/planning/plan_list_screen_test.dart \
  test/presentation/planning/plan_detail_screen_test.dart \
  test/presentation/planning/session_song_picker_test.dart
```

Expected: PASS.
