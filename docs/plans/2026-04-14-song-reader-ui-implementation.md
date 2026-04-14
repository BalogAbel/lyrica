# Song Reader UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the approved song reader UI direction in Flutter, starting from the current full-screen reader and evolving it into a compact touch-first reader plus an expanded large-viewport reader shell.

**Architecture:** Preserve the existing reader domain, projection, and runtime-controller boundaries. Concentrate the UI work inside the `presentation/song_reader/` subtree by introducing explicit reader layout state, extracting compact/expanded reader surfaces into focused widgets, and keeping the current song parsing and projection logic unchanged. The first implementation slice should prioritize compact reader chrome, bottom context, and overlay behavior, then layer expanded viewport side panels and adaptive layout on top.

**Tech Stack:** Flutter, Material 3, Riverpod, go_router, flutter_test

---

### Task 1: Map The Reader UI State Boundary

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_state.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_controller.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/session_scoped_reader_runtime_controller.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/session_scoped_reader_runtime_state.dart`
- Test: `apps/lyron_app/test/presentation/song_reader/song_reader_controller_test.dart`
- Test: `apps/lyron_app/test/presentation/song_reader/session_scoped_reader_runtime_controller_test.dart`

- [x] **Step 1: Add failing controller tests for the new UI state**

Cover the new reader UI state surface before implementation. Add focused tests for:

- overlay visibility toggling
- control presentation mode for the compact comparison behavior
- auto-fit enable and disable behavior
- parity between unscoped and scoped reader runtime state

Run:

```bash
flutter test \
  apps/lyron_app/test/presentation/song_reader/song_reader_controller_test.dart \
  apps/lyron_app/test/presentation/song_reader/session_scoped_reader_runtime_controller_test.dart
```

Expected: FAIL because the current controller and both runtime-state paths only support view mode, transpose, and font scale.

- [x] **Step 2: Extend `SongReaderState` with reader UI state**

Add the smallest set of UI state needed for the approved reader direction, for example:

- a compact control-surface visibility flag
- a reader control presentation mode enum if the comparison toggle should live in runtime state
- an auto-fit flag

Do not store viewport width or resolved column count in `SongReaderState`. Those belong to presentation-only layout calculation.

Keep normalization logic close to the state object and avoid pushing widget-specific branching into unrelated layers.

- [x] **Step 3: Extend `SongReaderController` with minimal UI actions**

Add only the actions required by the tests from Step 1, such as:

- show and hide controls
- toggle controls
- enable and disable auto-fit
- update shared font scale through gesture-driven inputs without weakening the existing normalization rules

Mirror the same capabilities into `SessionScopedReaderRuntimeController` so scoped plan/session readers preserve the same UI behavior boundary as the unscoped reader.

- [x] **Step 4: Re-run the controller test**

Run:

```bash
flutter test \
  apps/lyron_app/test/presentation/song_reader/song_reader_controller_test.dart \
  apps/lyron_app/test/presentation/song_reader/session_scoped_reader_runtime_controller_test.dart
```

Expected: PASS

### Task 2: Extract Reader Chrome Building Blocks

**Files:**
- Create: `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_bottom_context_bar.dart`
- Create: `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_compact_overlay.dart`
- Create: `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_expanded_context_panel.dart`
- Create: `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_expanded_tools_panel.dart`
- Create: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_layout.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_header.dart`
- Test: `apps/lyron_app/test/presentation/song_reader/widgets/song_reader_bottom_context_bar_test.dart`
- Test: `apps/lyron_app/test/presentation/song_reader/widgets/song_reader_compact_overlay_test.dart`
- Test: `apps/lyron_app/test/presentation/song_reader/song_reader_layout_test.dart`

- [x] **Step 1: Write failing widget tests for the new chrome pieces**

Add small widget tests that prove:

- the bottom context bar shows current, previous, and next song labels correctly
- the compact overlay renders the existing reader actions when visible
- the expanded context panel and tools panel can render without needing the whole screen
- a dedicated presentation helper resolves compact versus expanded shell and one- versus two-column content layout from viewport width, auto-fit state, and shared font scale

Run:

```bash
flutter test \
  apps/lyron_app/test/presentation/song_reader/widgets/song_reader_bottom_context_bar_test.dart \
  apps/lyron_app/test/presentation/song_reader/widgets/song_reader_compact_overlay_test.dart \
  apps/lyron_app/test/presentation/song_reader/song_reader_layout_test.dart
```

Expected: FAIL because these widgets do not exist yet.

- [x] **Step 2: Extract the compact bottom context bar**

Create a focused widget that can render:

- previous song label when scoped context provides it
- current song title
- next song label when scoped context provides it

If scoped context is unavailable, keep the bar renderable with the current song only instead of collapsing the whole layout.

- [x] **Step 3: Extract the compact overlay**

Move the current view-mode, transpose, and shared-font-scale controls into a dedicated overlay widget that can be shown or hidden by the screen.

Do not add editor or delete actions to the overlay; keep it reader-focused.

- [x] **Step 4: Extract expanded side panels**

Create lightweight left and right panel widgets that:

- render performance context on the left
- render reader tools on the right
- stay usable even while some scoped context is absent

- [x] **Step 5: Introduce an explicit presentation layout seam**

Create `song_reader_layout.dart` as the single owner of:

- compact versus expanded shell selection
- content column-count resolution
- width and scale thresholds used only by presentation code

This avoids pushing viewport ownership into `SongReaderState` or controller code.

- [x] **Step 6: Re-run the new widget tests**

Run:

```bash
flutter test \
  apps/lyron_app/test/presentation/song_reader/widgets/song_reader_bottom_context_bar_test.dart \
  apps/lyron_app/test/presentation/song_reader/widgets/song_reader_compact_overlay_test.dart \
  apps/lyron_app/test/presentation/song_reader/song_reader_layout_test.dart
```

Expected: PASS

### Task 3: Restructure `SongReaderScreen` Into Compact And Expanded Layouts

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_screen.dart`
- Create: `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_compact_surface.dart`
- Create: `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_expanded_surface.dart`
- Test: `apps/lyron_app/test/presentation/song_reader/song_reader_screen_test.dart`

- [x] **Step 1: Add failing screen tests for compact and expanded shells**

Extend `song_reader_screen_test.dart` to prove:

- compact reader shows the bottom context bar and hides the overlay by default
- compact reader can reveal the overlay through direct interaction
- expanded reader shows side panels and does not render the compact overlay
- the existing back affordance and load/error states continue to work

Run:

```bash
flutter test apps/lyron_app/test/presentation/song_reader/song_reader_screen_test.dart
```

Expected: FAIL because the screen still renders the legacy list-based layout.

- [x] **Step 2: Extract the compact reader surface**

Create a compact reader surface widget that owns:

- the song body
- the bottom context bar
- the temporary overlay
- tap-driven overlay visibility

The compact surface should remain the default for touch-first and smaller viewports.

- [x] **Step 3: Extract the expanded reader surface**

Create an expanded surface widget that owns:

- left context panel
- center reader surface
- right tools panel

It must not render the compact overlay when expanded.

- [x] **Step 4: Refactor `SongReaderScreen` to choose the surface by viewport**

Use the smallest possible viewport rule at the presentation boundary. Keep all existing load, retry, not-found, access-denied, and scoped-routing behavior intact while routing the success state through the new compact or expanded surface.

Use `song_reader_layout.dart` as the only viewport/layout decision seam.

- [x] **Step 5: Re-run the screen test**

Run:

```bash
flutter test apps/lyron_app/test/presentation/song_reader/song_reader_screen_test.dart
```

Expected: PASS

### Task 4: Implement Adaptive Song Layout Inside The Reader Surface

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_section_view.dart`
- Create: `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_section_grid.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_line_view.dart`
- Test: `apps/lyron_app/test/presentation/song_reader/widgets/song_line_view_test.dart`
- Test: `apps/lyron_app/test/presentation/song_reader/song_reader_screen_test.dart`

- [x] **Step 1: Add failing tests for scale- and width-aware presentation**

Add tests that prove:

- larger shared font scale still affects rendered lyric text
- compact reader stays one-column when space is tight
- larger reader width can switch to a denser presentation when auto-fit is active

Run:

```bash
flutter test \
  apps/lyron_app/test/presentation/song_reader/widgets/song_line_view_test.dart \
  apps/lyron_app/test/presentation/song_reader/song_reader_screen_test.dart
```

Expected: FAIL because the current reader always renders a simple vertical list.

- [x] **Step 2: Add a focused section-grid boundary**

Create a reader-only layout widget that can decide whether sections render in one or more columns based on:

- viewport width
- current shared font scale
- auto-fit state

Keep the decision logic local to presentation code.
That decision must come from `song_reader_layout.dart`, not from `SongReaderState`.

- [x] **Step 3: Preserve readability first**

When adapting to multiple columns:

- preserve deterministic reading order
- avoid horizontal scrolling
- keep chords aligned with lyrics through the existing line-view logic

- [x] **Step 4: Re-run the layout-related tests**

Run:

```bash
flutter test \
  apps/lyron_app/test/presentation/song_reader/widgets/song_line_view_test.dart \
  apps/lyron_app/test/presentation/song_reader/song_reader_screen_test.dart
```

Expected: PASS

### Task 5: Add Touch-First Reader Interactions

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_screen.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_compact_surface.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_controller.dart`
- Test: `apps/lyron_app/test/presentation/song_reader/song_reader_screen_test.dart`

- [x] **Step 1: Add failing interaction tests**

Extend the screen test to prove:

- tapping the compact reader surface reveals and hides the overlay
- double tapping toggles auto-fit
- changing scale continues to update lyric size

If gesture fidelity is hard to cover fully in widget tests, at least cover the state transitions and visible outcomes.

Run:

```bash
flutter test apps/lyron_app/test/presentation/song_reader/song_reader_screen_test.dart
```

Expected: FAIL because the current screen does not expose these interactions.

- [x] **Step 2: Implement tap and double-tap behavior**

Add the minimal gesture handling needed for:

- single-tap overlay reveal/hide in compact mode
- double-tap auto-fit toggle in compact mode

Keep expanded mode free of compact overlay behavior.

- [x] **Step 3: Implement inactivity-based overlay hiding**

Use the lightest timer-based UI behavior that makes the compact overlay disappear after inactivity without creating stale timers after disposal.

- [x] **Step 4: Re-run the interaction test**

Run:

```bash
flutter test apps/lyron_app/test/presentation/song_reader/song_reader_screen_test.dart
```

Expected: PASS

### Task 6: Preserve Existing Editing And Scoped Navigation Affordances

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_screen.dart`
- Test: `apps/lyron_app/test/presentation/song_reader/song_reader_screen_test.dart`
- Test: `apps/lyron_app/test/integration/song_reader_flow_test.dart`
- Test: `apps/lyron_app/test/integration/plan_session_reader_flow_test.dart`

- [x] **Step 1: Add failing regression assertions if needed**

Make sure the reader refactor still covers:

- song edit and delete actions
- scoped previous/next navigation context
- direct-route fallback navigation

Add or tighten tests before changing the screen further if any of these are only implicitly covered today.

- [x] **Step 2: Keep the editing affordances outside the compact overlay**

Preserve edit and delete actions in a stable, non-reader-control location so the reader overlay stays reading-focused.

Move them to a persistent top action area owned by `SongReaderScreen`, above the compact or expanded reader surface, so they remain:

- outside the compact overlay
- outside the expanded side panels
- present for both scoped and unscoped readers without duplication

- [x] **Step 3: Re-run the screen and integration tests**

Run:

```bash
flutter test \
  apps/lyron_app/test/presentation/song_reader/song_reader_screen_test.dart \
  apps/lyron_app/test/integration/song_reader_flow_test.dart \
  apps/lyron_app/test/integration/plan_session_reader_flow_test.dart
```

Expected: PASS

### Task 7: Documentation And Final Verification

**Files:**
- Modify: `docs/specs/2026-04-13-song-reader-ui-discovery.md`
- Modify: `docs/plans/2026-04-14-song-reader-ui-implementation.md`
- Modify: `apps/lyron_app/README.md`

- [x] **Step 1: Update the spec only if implementation changes the approved reader behavior**

Do not churn the discovery spec for implementation detail. Only update it if compact-versus-expanded rules, overlay behavior, or theme/layout decisions materially change.

- [x] **Step 2: Update app-level documentation if reader behavior becomes materially different**

If the user-facing reader behavior changes enough to matter to future engineers, add a concise note to `apps/lyron_app/README.md`.

- [x] **Step 3: Run the focused verification suite**

Run:

```bash
flutter test \
  apps/lyron_app/test/presentation/song_reader/song_reader_controller_test.dart \
  apps/lyron_app/test/presentation/song_reader/widgets/song_line_view_test.dart \
  apps/lyron_app/test/presentation/song_reader/widgets/song_reader_bottom_context_bar_test.dart \
  apps/lyron_app/test/presentation/song_reader/widgets/song_reader_compact_overlay_test.dart \
  apps/lyron_app/test/presentation/song_reader/song_reader_screen_test.dart \
  apps/lyron_app/test/integration/song_reader_flow_test.dart \
  apps/lyron_app/test/integration/plan_session_reader_flow_test.dart
```

Expected: PASS

- [x] **Step 4: Run broader app verification if the slice lands cleanly**

Run:

```bash
./scripts/verify.sh --skip-migrations
```

Expected: PASS
