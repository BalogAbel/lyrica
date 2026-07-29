# S4 — ARCH-3: Decompose the UI god-components

**Date:** 2026-07-27
**Slice:** S4 (Phase 2)
**Finding:** ARCH-3 (`docs/architecture/repository-review-2026-06-22.md`)
**Branch:** `refactor/ui-decomposition-phase2`
**Also closes:** `docs/deferred/2026-04-30-planning-reorder-optimistic-state.md`

## Problem

Three presentation files carry most of the app's UI logic in a single class each:

| File | Lines | Widget/behaviour classes inside |
|------|-------|---------------------------------|
| `presentation/planning/plan_detail_screen.dart` | 1232 | 6 widget classes + 4 file-level helpers |
| `presentation/song_editor/song_editor_screen.dart` | 1088 | 13 widget classes, 1 state class with 22 private methods |
| `presentation/song_reader/song_reader_screen.dart` | 998 | 1 state class carrying zoom persistence, immersive-mode sync, song actions, shell routing |

Nothing inside those files can be widget-tested in isolation: a test for the
session card, the source panel, or the reader overflow menu has to build the whole
screen, with the whole provider graph behind it. ARCH-3 records this as a Medium
finding ("UI god-components").

Both `presentation/planning/` and `presentation/song_reader/` already have a
`widgets/` subdirectory (`planning_workspace_shell.dart`; 12 reader widget files),
so the target layout already exists and is not being invented here.

## Goal

Decompose the three screens along responsibility lines so that:

1. No screen file exceeds ~400 lines.
2. Every extracted widget is independently widget-testable (public class, own
   file, data + callbacks in, no hidden dependency on the parent's state).
3. Behaviour is unchanged — the extraction is proven by characterization tests
   written **before** the move and passing unchanged after it.
4. The Phase 0–1 gains survive: extracted widgets keep the scoped planning
   invalidation of ARCH-2 and never bypass `ActiveOrganizationResolver` (ARCH-5).

One behaviour change ships alongside the refactor, in its own commits and its own
TDD cycle: the deferred optimistic-reorder-overlay cleanup (see
[Deferred item closure](#deferred-item-closure)).

## Non-goals

- No visual redesign. Widget trees move; they do not change.
- No new state management layer for planning. No provider is added, removed, or
  re-scoped by the extraction itself.
- No change to reader parsing/transpose semantics. The reader layout work (UX-1)
  and the plan date picker (UX-2) are slice S5 on the same branch.
- `docs/deferred/2026-04-22-song-reader-chordpro-modulation.md` stays deferred and
  its stated contract (global-only transpose) is not touched.

## Design

### D1 — State ownership rule

State moves with the widget that owns the interaction that mutates it. No state is
lifted into a new controller; that would be scope creep beyond ARCH-3.

| State | Owner today | Owner after |
|-------|-------------|-------------|
| `_optimisticSessionOrder`, `_sessionReorderGeneration`, `_sessionReorderTail`, `_latestPlanDetail` | `_PlanDetailScreenState` | unchanged — the screen owns the sessions `ReorderableListView` |
| `_optimisticItemOrder`, `_itemReorderGeneration`, `_itemReorderTail`, `_pickerOpen`, `_addSongInFlight`, `_addSongFocusNode` | `_SessionCardState` | moves intact with the class to `widgets/plan_session_card.dart` |
| dialog `TextEditingController`s, `_scheduledForError` | dialog state classes | move with their dialog file; dispose sites move unchanged |
| `_controller`, `_sourceController`, `_tabletTab`, `_savedSource`, `_isDirty` | `_SongEditorScreenState` | unchanged — the screen owns save/discard |
| `_persistZoomTimer`, `_seededZoom` | `_SongReaderScreenState` | move into `SongReaderZoomPersistence` |
| `_lastAppliedImmersive` | `_SongReaderScreenState` | moves into `SongReaderImmersiveMode` |

### D2 — Provider contract (protects ARCH-2 and ARCH-5)

Extracted widgets stay `ConsumerWidget` / `ConsumerStatefulWidget` and keep the
**same** provider calls at the **same** granularity they have today:

- family-scoped reads and invalidations stay family-scoped:
  `planningPlanDetailProvider(planId)`, `songLibraryReaderProvider(songId)`,
  `sessionScopedReaderRuntimeControllerProvider(sessionKey)`.
- `planningMutationEntriesProvider` and `planningPlanListProvider` invalidations
  stay exactly where they are.
- `planningDataRevisionProvider` is bumped only where it is bumped today
  (`plan_detail_screen.dart:201`, the plan edit path). Extraction must not add a
  bump to any other write path.
- Organization and user identity always come from `activePlanningContextProvider`
  / `activeCatalogContextProvider`. No extracted widget constructs, caches, or
  threads an organization id of its own.

Prohibited by this spec: introducing a broader watch (for example watching
`planningDataRevisionProvider` in a widget that today watches only
`planningPlanDetailProvider(planId)`) to make an extracted widget "refresh".

### D3 — Extraction layout

Convention follows `presentation/song_reader/widgets/`: one responsibility per
file, `snake_case` filename matching the primary public class, cohesive
sub-widgets allowed to stay private in the same file.

**`presentation/planning/widgets/`**

| New file | Source lines | Public class |
|----------|--------------|--------------|
| `plan_session_card.dart` | 378–912 | `PlanSessionCard` |
| `plan_editor_dialog.dart` | 914–1036 | `PlanEditorDialog` |
| `session_editor_dialog.dart` | 1038–1102 | `SessionEditorDialog` |
| `plan_song_item_row.dart` | 1118–1208 | `PlanSongItemRow` |
| `retryable_error_state.dart` | 1210–1232 | `RetryableErrorState` |

File-level helpers travel with their only caller: `_formatScheduledFor` and the
plan-editor parsing/normalizing helpers (`_normalizeText`,
`_parseOptionalDateTime`) move to `plan_editor_dialog.dart`;
`_handlePlanningAddSongError` moves to `plan_session_card.dart`.
`plan_detail_screen.dart` target: ~360 lines.

**`presentation/song_editor/widgets/`** (new directory)

| New file | Source lines | Public classes |
|----------|--------------|----------------|
| `song_editor_top_bar.dart` | 571–689 | `SongEditorTopBar`, `SongEditorStatusBanner` |
| `song_editor_tab_bar.dart` | 691–716 | `SongEditorTabBar` |
| `song_editor_panels.dart` | 718–919, 921–970 | `SongEditorOverviewPanel`, `SongEditorCanonicalPanel`, `SongEditorSourcePanel`, `SongEditorPreviewPanel`, `SongEditorPanelShell` |
| `song_editor_summary_list.dart` | 972–1048 | `SongEditorSummaryList` |
| `song_editor_stepper.dart` | 1050–1088 | `SongEditorStepper` |
| `song_editor_dialogs.dart` | 277–316 | `showSongEditorConflictDialog`, `confirmDiscardSongEditorChanges` |

`_TabletTab` moves next to the tab bar it drives and is exported for the screen.
Plus `presentation/song_editor/song_editor_selection.dart` — the three pure
functions at 363–419 (`preserveSelectionAfterSourceRewrite`,
`sharedPrefixLength`, `sharedSuffixLength`), which get direct unit tests instead
of being reachable only through a rendered editor.
`song_editor_screen.dart` target: ~370 lines.

**`presentation/song_reader/`**

Widgets into `widgets/`: `song_reader_app_bar.dart` (title, warning indicator,
overflow menu wiring) and `song_reader_overflow_menu.dart`
(`_SongReaderOverflowAction` + menu construction).

Behaviour into plain classes beside the screen, each independently testable:

| New file | Responsibility | Moved from |
|----------|----------------|------------|
| `song_reader_zoom_persistence.dart` | seed shared font scale from the preferences store; debounce-persist changes | `_seedZoomFromStorage`, `_persistFontScale`, `_persistZoomTimer`, `_seededZoom` |
| `song_reader_immersive_mode.dart` | apply/restore `SystemChrome` UI mode with last-applied de-duplication | `_applyImmersiveMode`, `_lastAppliedImmersive` |
| `song_reader_song_actions.dart` | edit-song navigation and delete-song flow incl. capability/context reads and post-delete invalidation | overflow action handlers ~500–560 |

`song_reader_screen.dart` target: ~400 lines.

### D4 — Test contract for the refactor

Characterization tests are written and green **before** any code moves, and must
pass **unchanged** afterwards. They are the proof of "no behaviour change".

Existing suites are extended in place:
`test/presentation/planning/plan_detail_screen_test.dart`,
`test/presentation/song_editor/song_editor_screen_test.dart`,
`test/presentation/song_reader/song_reader_screen_test.dart`.

Behaviour pinned:

- **Planning:** session reorder applies optimistically and survives a rebuild;
  reorder failure rolls the overlay back; item reorder inside a session card;
  plan editor dialog validation and save; session rename and delete confirmation;
  the add-song picker gate (`_canAddSong` / catalog context); retry from the
  error state.
- **Editor:** dirty tracking and discard confirmation; save path invalidations;
  transpose/capo steppers with cursor-position preservation; tablet tab switching
  and canonical view toggle; capability gate.
- **Reader:** zoom seeded from the store and persisted after the debounce window;
  immersive-mode toggle applies once per state change; overflow actions (edit,
  delete, view mode, instrument); compact-vs-expanded shell selection at the
  layout breakpoint.

After extraction, each extracted widget gets its own test file exercising it in
isolation (built directly, not through the screen), under
`test/presentation/<area>/widgets/`.

### D5 — Deferred item closure {#deferred-item-closure}

`docs/deferred/2026-04-30-planning-reorder-optimistic-state.md` describes the
remaining concern as cleanup semantics, not write correctness. Current behaviour,
verified in `plan_detail_screen.dart`:

- The overlay is set on drag (`_optimisticSessionOrder = currentOrder`) and
  cleared **only** on write failure (`:319`) or implicitly ignored when
  `_orderedSessions` finds it structurally incompatible with the fresh projection
  (different length, or an id that no longer exists, `:141–158`).
- On success it is never cleared. A compatible-but-stale overlay therefore masks
  the refreshed projection for the lifetime of the screen.
- Failure is silent to the user: `_reportReorderError` only calls
  `FlutterError.reportError`.

The same two properties hold for the item-level overlay in the session card
(`:836–900`).

This slice closes both gaps:

1. **Clear on refetch.** When a fresh `PlanDetail` arrives and no reorder is in
   flight for the current generation, and the incoming order already equals the
   optimistic order, the overlay is dropped. The projection becomes the single
   source of truth again as soon as it agrees with the optimistic state.
2. **Surface the rollback.** When a reorder write fails and the overlay is rolled
   back, the user gets a visible message (new `AppStrings` key) in addition to the
   existing `FlutterError.reportError` call.
3. Both rules apply identically to the session-level and item-level overlays.

This is a behaviour change, so it is **not** covered by the characterization
tests: it gets its own failing-test-first cycle, its own commits, its own review
doc entry, and ADR-023 recording the overlay lifecycle contract. The deferred file
is removed in the same commit, per `docs/deferred/README.md` tracking rule.

Race note: clearing on refetch must not drop an overlay that a still-in-flight
reorder depends on. The existing generation token
(`_sessionReorderGeneration` / `_itemReorderGeneration`) plus an explicit
"no write in flight" condition gate the clear; the test forces the interleaving
(refetch arriving while a write is pending) rather than relying on timing.

## Verification

- `plan_detail_screen.dart`, `song_editor_screen.dart`, `song_reader_screen.dart`
  each under ~400 lines (`wc -l`).
- Characterization tests unchanged between the pre-extraction and
  post-extraction commits (`git diff` on the test files is empty across the
  extraction commits).
- New per-widget test files pass.
- Full local verification: `verify`, `backend_write_contracts`, `migrations`.

## Documentation duties

- `docs/architecture/architecture.md` — presentation-layer structure and the
  screen/widget boundary rule.
- `docs/architecture/decisions/ADR-023-*.md` — optimistic reorder overlay
  lifecycle.
- `docs/architecture/repository-review-2026-06-22.md` — ARCH-3 struck through and
  marked done, following the existing convention.
- `docs/deferred/2026-04-30-planning-reorder-optimistic-state.md` — removed.
- `docs/plans/2026-07-27-arch3-ui-decomposition.md` — implementation plan.
