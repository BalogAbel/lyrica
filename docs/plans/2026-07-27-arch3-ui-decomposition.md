# ARCH-3 UI Decomposition Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split the three god-component screens (`plan_detail_screen.dart` 1232, `song_editor_screen.dart` 1088, `song_reader_screen.dart` 998) into independently testable widgets and behaviour classes without changing behaviour, then close the deferred optimistic-reorder-overlay cleanup gap.

**Architecture:** Characterization widget tests are written first and must pass unchanged across the extraction. Widgets move into the existing `widgets/` convention (one responsibility per file, public class, data + callbacks in). Reader behaviour (zoom persistence, immersive mode, song actions) moves into plain classes beside the screen. State moves with the widget that owns the interaction; no new provider, no widened `ref.watch`.

**Tech Stack:** Flutter, Riverpod (`flutter_riverpod`), `flutter_test` widget tests, `go_router`.

**Spec:** `docs/specs/2026-07-27-arch3-ui-decomposition.md`

**Branch:** `refactor/ui-decomposition-phase2` (already created; do not branch again, do not merge)

---

## Ground rules for every task

- Run `cd apps/lyron_app && dart format lib test` before every commit. `verify` fails on unformatted code.
- Never widen a provider subscription. If a moved widget watched `planningPlanDetailProvider(planId)`, it keeps watching exactly that. Never add a `planningDataRevisionProvider` bump; the only legitimate bump is the existing one in the plan-edit path.
- Never build an organization id by hand. It comes from `activePlanningContextProvider` / `activeCatalogContextProvider` only.
- Test file paths use the mirror convention: `lib/src/presentation/X/widgets/y.dart` → `test/presentation/X/widgets/y_test.dart`.
- Full suite: `cd apps/lyron_app && flutter test`. Single test: `flutter test test/<path> --plain-name '<test name>'`.

---

## File Structure

**Created**

| File | Responsibility |
|------|----------------|
| `apps/lyron_app/lib/src/presentation/planning/widgets/plan_session_card.dart` | one session card: rename/delete/add-song, item list + item reorder overlay |
| `apps/lyron_app/lib/src/presentation/planning/widgets/plan_editor_dialog.dart` | plan name/description/scheduled-for editing dialog + its parsing helpers |
| `apps/lyron_app/lib/src/presentation/planning/widgets/session_editor_dialog.dart` | session create/rename dialog |
| `apps/lyron_app/lib/src/presentation/planning/widgets/plan_song_item_row.dart` | one song row inside a session, with delete |
| `apps/lyron_app/lib/src/presentation/planning/widgets/retryable_error_state.dart` | message + retry button error surface |
| `apps/lyron_app/lib/src/presentation/song_editor/widgets/song_editor_top_bar.dart` | editor header + status banner |
| `apps/lyron_app/lib/src/presentation/song_editor/widgets/song_editor_tab_bar.dart` | tablet tab selector + `SongEditorTab` enum |
| `apps/lyron_app/lib/src/presentation/song_editor/widgets/song_editor_panels.dart` | overview / canonical / source / preview panels + panel shell |
| `apps/lyron_app/lib/src/presentation/song_editor/widgets/song_editor_summary_list.dart` | metadata summary rows |
| `apps/lyron_app/lib/src/presentation/song_editor/widgets/song_editor_stepper.dart` | transpose / capo −/value/+ control |
| `apps/lyron_app/lib/src/presentation/song_editor/widgets/song_editor_dialogs.dart` | conflict dialog + discard confirmation |
| `apps/lyron_app/lib/src/presentation/song_editor/song_editor_selection.dart` | pure cursor-preservation functions |
| `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_app_bar.dart` | reader app bar (title, warning indicator, overflow menu slot) |
| `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_overflow_menu.dart` | overflow menu + `SongReaderOverflowAction` enum |
| `apps/lyron_app/lib/src/presentation/song_reader/song_reader_zoom_persistence.dart` | seed + debounce-persist shared font scale |
| `apps/lyron_app/lib/src/presentation/song_reader/song_reader_immersive_mode.dart` | `SystemChrome` UI-mode application with dedupe |
| `apps/lyron_app/lib/src/presentation/song_reader/song_reader_song_actions.dart` | edit/delete song flows |
| `apps/lyron_app/lib/src/application/planning/planning_reorder_overlay.dart` | pure overlay-lifecycle logic shared by session and item reorder |
| `docs/architecture/decisions/ADR-023-optimistic-reorder-overlay-lifecycle.md` | overlay lifecycle decision |

**Modified**

| File | Change |
|------|--------|
| `apps/lyron_app/lib/src/presentation/planning/plan_detail_screen.dart` | shrinks to the screen shell + session reorder orchestration (~360 lines) |
| `apps/lyron_app/lib/src/presentation/song_editor/song_editor_screen.dart` | shrinks to state + orchestration (~370 lines) |
| `apps/lyron_app/lib/src/presentation/song_reader/song_reader_screen.dart` | shrinks to state + shell routing (~400 lines) |
| `apps/lyron_app/lib/src/shared/app_strings.dart` | new reorder-failure message key |
| `docs/architecture/architecture.md` | presentation structure section |
| `docs/architecture/repository-review-2026-06-22.md` | ARCH-3 struck through |

**Deleted**

| File | Reason |
|------|--------|
| `docs/deferred/2026-04-30-planning-reorder-optimistic-state.md` | closed by Tasks 9–10 |

---

## Task 1: Characterization — session reorder optimism, rollback, staleness

Coverage audit found these three behaviours unpinned. They must be pinned before `_SessionCard` moves out of the file.

**Files:**
- Test: `apps/lyron_app/test/presentation/planning/plan_detail_screen_test.dart` (add after the existing `'queues session reorder requests while one is in flight'` test)

- [ ] **Step 1: Write the three failing-by-absence characterization tests**

These assert today's behaviour exactly. `_FakePlanningWriteService` already accepts `onReorderSessions`, and `_editablePlanDetailFixture()` already produces three sessions (`Warm-Up`, `Main Set`, `Closing`) — reuse both, do not add fixtures.

```dart
  testWidgets('shows reordered sessions before the local write completes', (
    tester,
  ) async {
    final reorderCompleter = Completer<void>();
    final writeService = _FakePlanningWriteService(
      onReorderSessions: (_) => reorderCompleter.future,
    );

    await tester.pumpWidget(
      buildApp(
        planDetailValue: _editablePlanDetailFixture(),
        writeService: writeService,
      ),
    );
    await tester.pumpAndSettle();

    final sessionList = tester
        .widgetList<ReorderableListView>(find.byType(ReorderableListView))
        .first;
    sessionList.onReorder(0, 3);
    await tester.pump();

    expect(
      tester.getTopLeft(find.text('Warm-Up')).dy,
      greaterThan(tester.getTopLeft(find.text('Closing')).dy),
    );

    reorderCompleter.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('rolls the session order back when the reorder write fails', (
    tester,
  ) async {
    final writeService = _FakePlanningWriteService(
      onReorderSessions: (_) async => throw StateError('session reorder failed'),
    );

    await tester.pumpWidget(
      buildApp(
        planDetailValue: _editablePlanDetailFixture(),
        writeService: writeService,
      ),
    );
    await tester.pumpAndSettle();

    final sessionList = tester
        .widgetList<ReorderableListView>(find.byType(ReorderableListView))
        .first;
    sessionList.onReorder(0, 3);
    await tester.pump();
    expect(
      tester.getTopLeft(find.text('Warm-Up')).dy,
      greaterThan(tester.getTopLeft(find.text('Closing')).dy),
    );

    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('Warm-Up')).dy,
      lessThan(tester.getTopLeft(find.text('Closing')).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('stale session reorder result does not clear newer order', (
    tester,
  ) async {
    final firstReorderCompleter = Completer<void>();
    var reorderCalls = 0;
    final writeService = _FakePlanningWriteService(
      onReorderSessions: (_) async {
        reorderCalls += 1;
        if (reorderCalls == 1) {
          await firstReorderCompleter.future;
          throw StateError('late session reorder failure');
        }
      },
    );

    await tester.pumpWidget(
      buildApp(
        planDetailValue: _editablePlanDetailFixture(),
        writeService: writeService,
      ),
    );
    await tester.pumpAndSettle();

    final sessionList = tester
        .widgetList<ReorderableListView>(find.byType(ReorderableListView))
        .first;
    sessionList.onReorder(0, 3);
    await tester.pump();
    sessionList.onReorder(0, 2);
    await tester.pump();

    final orderAfterSecondDrag = tester.getTopLeft(find.text('Warm-Up')).dy;

    firstReorderCompleter.complete();
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.text('Warm-Up')).dy, orderAfterSecondDrag);
  });
```

- [ ] **Step 2: Run them; all three must pass**

Run: `cd apps/lyron_app && flutter test test/presentation/planning/plan_detail_screen_test.dart --plain-name 'session reorder'`

Expected: PASS. These pin existing behaviour, so a failure means the assertion is wrong about today's code, not that the code is broken — fix the test, not the screen.

If the `FlutterError.reportError` call in the failure path makes `tester.takeException()` non-null, keep the assertion but change it to swallow the expected error the way the existing item-level tests do; do **not** change `_reportReorderError`.

- [ ] **Step 3: Commit**

```bash
cd /Users/abelbalog/Documents/Development/private/lyrica
cd apps/lyron_app && dart format lib test && cd ..
git add apps/lyron_app/test/presentation/planning/plan_detail_screen_test.dart
git commit -m "test(planning): characterize session reorder optimism and rollback

Pins the session-level optimistic overlay behaviour (apply before write,
roll back on failure, ignore a stale result) before the session card is
extracted out of plan_detail_screen.dart."
```

---

## Task 2: Characterization — item rollback, rename validation, delete cancel

**Files:**
- Test: `apps/lyron_app/test/presentation/planning/plan_detail_screen_test.dart`

- [ ] **Step 1: Write the three tests**

```dart
  testWidgets('rolls the session item order back when the write fails', (
    tester,
  ) async {
    final writeService = _FakePlanningWriteService(
      onReorderSessionItems: (_) async => throw StateError('item reorder failed'),
    );

    await tester.pumpWidget(
      buildApp(
        planDetailValue: _planDetailWithItemsFixture(),
        writeService: writeService,
        visibleSongs: const [
          SongSummary(id: 'song-1', slug: 'alpha', title: 'Alpha'),
          SongSummary(id: 'song-2', slug: 'beta', title: 'Beta'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final itemList = tester
        .widgetList<ReorderableListView>(find.byType(ReorderableListView))
        .elementAt(1);
    itemList.onReorder(1, 0);
    await tester.pump();
    expect(
      tester.getTopLeft(find.textContaining('Beta')).dy,
      lessThan(tester.getTopLeft(find.textContaining('Alpha')).dy),
    );

    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.textContaining('Alpha')).dy,
      lessThan(tester.getTopLeft(find.textContaining('Beta')).dy),
    );
  });

  testWidgets('session rename rejects an empty name', (tester) async {
    final writeService = _FakePlanningWriteService();

    await tester.pumpWidget(
      buildApp(
        planDetailValue: _editablePlanDetailFixture(),
        writeService: writeService,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('session-rename-button-session-1')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '   ');
    await tester.pumpAndSettle();

    await tester.tap(find.text(AppStrings.commonSave));
    await tester.pumpAndSettle();

    expect(writeService.renamedSessionDraft, isNull);
  });

  testWidgets('cancelling the session delete dialog does not delete', (
    tester,
  ) async {
    final writeService = _FakePlanningWriteService();

    await tester.pumpWidget(
      buildApp(
        planDetailValue: _editablePlanDetailFixture(),
        writeService: writeService,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('session-delete-button-session-1')));
    await tester.pumpAndSettle();

    await tester.tap(find.text(AppStrings.commonCancel));
    await tester.pumpAndSettle();

    expect(writeService.deletedSessionDraft, isNull);
  });
```

- [ ] **Step 2: Fix the identifiers against the real code, then run**

The three widget keys and the two `AppStrings` constants above are the names to verify first — open `plan_detail_screen.dart` (rename button, delete button, save/cancel labels) and `lib/src/shared/app_strings.dart` and substitute the real ones. Do not invent new keys and do not add keys to `plan_detail_screen.dart`; if a control has no key, locate it via its existing tooltip/icon the way the surrounding tests do.

Run: `cd apps/lyron_app && flutter test test/presentation/planning/plan_detail_screen_test.dart`

Expected: whole file PASS.

- [ ] **Step 3: Commit**

```bash
cd apps/lyron_app && dart format lib test && cd ..
git add apps/lyron_app/test/presentation/planning/plan_detail_screen_test.dart
git commit -m "test(planning): characterize item rollback, rename validation, delete cancel"
```

---

## Task 3: Characterization — song editor gaps

**Files:**
- Test: `apps/lyron_app/test/presentation/song_editor/song_editor_screen_test.dart`

Gaps from the audit: conflict dialog, edit-mode save invalidations, summary list rendering.

- [ ] **Step 1: Read the existing harness**

Read the top of the file (the `buildApp`/`pumpEditor` helper and the fake `SongLibraryService`). Every new test reuses it. Note how `'create mode save calls createSong and navigates to reader'` (`:399`) injects the service and asserts navigation — the two save tests below mirror that shape.

- [ ] **Step 2: Write the three tests**

```dart
  testWidgets('edit mode save calls updateSong and refreshes the reader', (
    tester,
  ) async {
    // Mirror the setup of 'create mode save calls createSong and navigates to
    // reader', but pump the editor in edit mode for an existing song and assert:
    //   expect(service.updatedSongIds, ['song-1']);
    // plus that songLibraryReaderProvider('song-1') was invalidated — observe
    // the invalidation through a counting override of that provider, the way
    // plan_detail_screen_test observes planningPlanDetailProvider rebuilds.
  });

  testWidgets('save surfaces the conflict dialog when the write conflicts', (
    tester,
  ) async {
    // Inject a service whose updateSong throws the conflict error the screen
    // maps to _showConflictResolutionRequiredDialog, then assert the dialog
    // title text is present and the editor did not navigate away.
  });

  testWidgets('summary list renders title, artist and key rows', (
    tester,
  ) async {
    // Pump the editor in wide layout with a parsed song carrying title/artist/
    // key, then assert one find.text per metadata value.
  });
```

The bodies above are deliberately described rather than pre-written: the exact
service fake, the conflict error type, and the `AppStrings` labels must be read
out of `song_editor_screen.dart:218-291` and the existing test helpers first. Do
not guess names. Write the real bodies in this step; do not commit comments.

- [ ] **Step 3: Run**

Run: `cd apps/lyron_app && flutter test test/presentation/song_editor/song_editor_screen_test.dart`

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
cd apps/lyron_app && dart format lib test && cd ..
git add apps/lyron_app/test/presentation/song_editor/song_editor_screen_test.dart
git commit -m "test(song-editor): characterize conflict dialog, edit save, summary rows"
```

---

## Task 4: Characterization — song reader gaps

**Files:**
- Test: `apps/lyron_app/test/presentation/song_reader/song_reader_screen_test.dart`

Gaps: immersive-mode dedupe, delete-song flow.

- [ ] **Step 1: Write the two tests**

Model the immersive test on the existing `'tapping the surface toggles immersive system UI mode'` (`:1750`) — it already captures `SystemChrome` channel calls; extend that capture list to assert **count**, not just last value:

```dart
  testWidgets('immersive mode is not re-applied when the state is unchanged', (
    tester,
  ) async {
    // Reuse the SystemChrome mock-channel capture from the existing immersive
    // test. Pump the reader, record the number of
    // 'SystemChrome.setEnabledSystemUIMode' calls, then force a rebuild that
    // does NOT change controls visibility (e.g. pump again / change an
    // unrelated provider), and assert the call count did not grow.
  });

  testWidgets('delete action deletes the song and refreshes the library', (
    tester,
  ) async {
    // Mirror 'edit action opens the song editor route' (:669) to open the
    // overflow menu, tap delete, confirm the dialog, then assert the fake
    // SongLibraryService recorded the delete and that songLibraryListProvider
    // was invalidated (counting override, as in the planning tests).
  });
```

Write the real bodies; the descriptions name the source tests to copy the setup from.

- [ ] **Step 2: Run**

Run: `cd apps/lyron_app && flutter test test/presentation/song_reader/song_reader_screen_test.dart`

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
cd apps/lyron_app && dart format lib test && cd ..
git add apps/lyron_app/test/presentation/song_reader/song_reader_screen_test.dart
git commit -m "test(song-reader): characterize immersive dedupe and delete flow"
```

---

## Task 5: Extract the plan detail widgets

**This is a pure move.** No logic edit is allowed in this task. If a moved method needs a value it used to read from the parent's `widget.` field, it takes it as a constructor parameter — nothing else changes.

**Files:**
- Create: `apps/lyron_app/lib/src/presentation/planning/widgets/plan_session_card.dart`
- Create: `apps/lyron_app/lib/src/presentation/planning/widgets/plan_editor_dialog.dart`
- Create: `apps/lyron_app/lib/src/presentation/planning/widgets/session_editor_dialog.dart`
- Create: `apps/lyron_app/lib/src/presentation/planning/widgets/plan_song_item_row.dart`
- Create: `apps/lyron_app/lib/src/presentation/planning/widgets/retryable_error_state.dart`
- Modify: `apps/lyron_app/lib/src/presentation/planning/plan_detail_screen.dart`

- [ ] **Step 1: Record the baseline**

```bash
cd /Users/abelbalog/Documents/Development/private/lyrica
git rev-parse HEAD > /tmp/arch3-baseline.txt
wc -l apps/lyron_app/lib/src/presentation/planning/plan_detail_screen.dart
```

Expected: 1232.

- [ ] **Step 2: Move `_RetryableErrorState` (lines 1210–1232)**

Create `widgets/retryable_error_state.dart` with the class renamed `_RetryableErrorState` → `RetryableErrorState` (public, `const` constructor kept). Delete it from the screen and import the new file. Update the one usage at `plan_detail_screen.dart:84`.

- [ ] **Step 3: Move `_SongItemRow` (lines 1118–1208)**

Create `widgets/plan_song_item_row.dart` with `_SongItemRow` → `PlanSongItemRow`. Its `_deleteItem` method and every `ref.` call move verbatim, including `ref.invalidate(planningPlanDetailProvider(planDetail.plan.id))`. Update its usage inside the session card body.

- [ ] **Step 4: Move both dialogs (lines 914–1102)**

Create `widgets/plan_editor_dialog.dart` (`_PlanEditorDialog` → `PlanEditorDialog`) and `widgets/session_editor_dialog.dart` (`_SessionEditorDialog` → `SessionEditorDialog`). The file-level helpers `_normalizeText` (1104–1107) and `_parseOptionalDateTime` (1109–1116) are used only by the plan editor dialog — move them into `plan_editor_dialog.dart` as private top-level functions. Update the two `showDialog` call sites (`:170`, `:213`) and the rename call site inside the session card.

- [ ] **Step 5: Move `_SessionCard` (lines 378–912) and `_formatScheduledFor` / `_handlePlanningAddSongError`**

Create `widgets/plan_session_card.dart` with `_SessionCard` → `PlanSessionCard` and `_SessionCardState` → `_PlanSessionCardState`. All of it moves: `_optimisticItemOrder`, `_itemReorderGeneration`, `_itemReorderTail`, `_pickerOpen`, `_addSongInFlight`, `_addSongFocusNode` and its `initState`/`dispose`, plus `_renameSession`, `_addSong`, `_deleteSession`, `_reorderItems`, `_performItemReorder`. `_handlePlanningAddSongError` (363–376) moves with it. `_formatScheduledFor` (357–361) is used by the screen header only — it stays in `plan_detail_screen.dart`. Update the `itemBuilder` at `:128`.

- [ ] **Step 6: Verify no provider drift**

```bash
cd /Users/abelbalog/Documents/Development/private/lyrica
git show "$(cat /tmp/arch3-baseline.txt)":apps/lyron_app/lib/src/presentation/planning/plan_detail_screen.dart \
  | grep -oE 'ref\.(watch|read|listen|invalidate)\([^)]*' | sort | uniq -c > /tmp/arch3-before.txt
grep -rhoE 'ref\.(watch|read|listen|invalidate)\([^)]*' \
  apps/lyron_app/lib/src/presentation/planning/plan_detail_screen.dart \
  apps/lyron_app/lib/src/presentation/planning/widgets/ | sort | uniq -c > /tmp/arch3-after.txt
diff /tmp/arch3-before.txt /tmp/arch3-after.txt
```

Expected: empty diff. Any line difference means a provider call was added, dropped, or re-scoped — fix it before continuing.

- [ ] **Step 7: Run the characterization suite unchanged**

```bash
cd apps/lyron_app && flutter analyze && flutter test test/presentation/planning/
```

Expected: analyze clean, all planning tests PASS. Then confirm the tests themselves were not touched:

```bash
cd /Users/abelbalog/Documents/Development/private/lyrica
git diff --stat "$(cat /tmp/arch3-baseline.txt)" -- apps/lyron_app/test/presentation/planning/
```

Expected: no output. If a test needed editing, the move was not behaviour-preserving — revert and redo the step.

- [ ] **Step 8: Check the size target**

```bash
wc -l apps/lyron_app/lib/src/presentation/planning/plan_detail_screen.dart
```

Expected: under 400.

- [ ] **Step 9: Commit**

```bash
cd apps/lyron_app && dart format lib test && cd ..
git add apps/lyron_app/lib/src/presentation/planning/
git commit -m "refactor(planning): extract plan detail sub-widgets

Moves the session card, both editor dialogs, the song item row and the
retryable error state into presentation/planning/widgets/, following the
existing widgets/ convention. Pure move: provider calls, their scoping and
all optimistic-reorder state stay exactly where they were, and the
characterization tests pass unchanged."
```

---

## Task 6: Extract the song editor widgets and the selection module

**Files:**
- Create: the six files under `apps/lyron_app/lib/src/presentation/song_editor/widgets/` plus `song_editor_selection.dart` (see File Structure)
- Create: `apps/lyron_app/test/presentation/song_editor/song_editor_selection_test.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_editor/song_editor_screen.dart`

- [ ] **Step 1: Create the `widgets/` directory and move lines 571–1088**

The classes at 571–1088 are already leaf presentation widgets with no `ref` usage except `_TopBar` (a `ConsumerWidget`). Move them with these renames:

| Old | New | File |
|-----|-----|------|
| `_TopBar` | `SongEditorTopBar` | `song_editor_top_bar.dart` |
| `_StatusBanner` | `SongEditorStatusBanner` | `song_editor_top_bar.dart` |
| `_TabletTabBar` | `SongEditorTabBar` | `song_editor_tab_bar.dart` |
| `_TabletTab` (enum) | `SongEditorTab` | `song_editor_tab_bar.dart` |
| `_OverviewPanel` | `SongEditorOverviewPanel` | `song_editor_panels.dart` |
| `_CanonicalPanel` | `SongEditorCanonicalPanel` | `song_editor_panels.dart` |
| `_SourcePanel` | `SongEditorSourcePanel` | `song_editor_panels.dart` |
| `_PreviewPanel` | `SongEditorPreviewPanel` | `song_editor_panels.dart` |
| `_PanelShell` | `SongEditorPanelShell` | `song_editor_panels.dart` |
| `_SummaryList` | `SongEditorSummaryList` | `song_editor_summary_list.dart` |
| `_SummaryRow` | stays private `_SummaryRow` | `song_editor_summary_list.dart` |
| `_Stepper` | `SongEditorStepper` | `song_editor_stepper.dart` |

`_tabletTab` in the screen state becomes `SongEditorTab`.

- [ ] **Step 2: Move the two dialogs (lines 277–316)**

Create `widgets/song_editor_dialogs.dart` exposing two top-level functions with the same bodies:

```dart
Future<void> showSongEditorConflictDialog(BuildContext context) async { /* body of _showConflictResolutionRequiredDialog */ }

Future<bool> confirmDiscardSongEditorChanges(BuildContext context) async { /* body of _confirmDiscardChangesIfNeeded */ }
```

`_confirmDiscardChangesIfNeeded` currently returns `true` early when `!_isDirty`. That dirty check stays in the **screen** (it is state, not dialog logic); the extracted function only shows the dialog and returns the answer. Update the three call sites (`:208`, `:319`, and the save path) so the dirty short-circuit happens before the call.

- [ ] **Step 3: Write the failing test for the selection module**

Create `apps/lyron_app/test/presentation/song_editor/song_editor_selection_test.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/presentation/song_editor/song_editor_selection.dart';

void main() {
  test('keeps the caret offset when the rewrite does not touch the prefix', () {
    const previous = '{title: A}\n[C]hello';
    const next = '{title: A}\n[D]hello';

    final selection = preserveSelectionAfterSourceRewrite(
      previousSource: previous,
      nextSource: next,
      previousSelection: const TextSelection.collapsed(offset: 3),
    );

    expect(selection.baseOffset, 3);
    expect(selection.isCollapsed, isTrue);
  });

  test('clamps the caret into range when the rewrite shortens the source', () {
    final selection = preserveSelectionAfterSourceRewrite(
      previousSource: 'abcdefgh',
      nextSource: 'abc',
      previousSelection: const TextSelection.collapsed(offset: 8),
    );

    expect(selection.baseOffset, lessThanOrEqualTo(3));
  });

  test('shared prefix and suffix lengths do not overlap', () {
    expect(sharedPrefixLength('aaa', 'aab'), 2);
    expect(sharedSuffixLength('xay', 'xby'), 1);
  });
}
```

- [ ] **Step 4: Run it and watch it fail**

Run: `cd apps/lyron_app && flutter test test/presentation/song_editor/song_editor_selection_test.dart`

Expected: FAIL — `Target of URI doesn't exist: 'package:lyron_app/src/presentation/song_editor/song_editor_selection.dart'`.

- [ ] **Step 5: Create the module by moving lines 363–419**

Create `song_editor_selection.dart` with the three functions made public and top-level:
`_preserveSelectionAfterSourceRewrite` → `preserveSelectionAfterSourceRewrite`,
`_sharedPrefixLength` → `sharedPrefixLength`,
`_sharedSuffixLength` → `sharedSuffixLength`.
Bodies are copied verbatim; the method signature keeps whatever named parameters
it has today — adjust the test above to the real signature rather than changing
the implementation. Delete them from the screen and import the module.

- [ ] **Step 6: Run both suites**

Run: `cd apps/lyron_app && flutter analyze && flutter test test/presentation/song_editor/`

Expected: PASS. Then verify the screen test file was not edited:

```bash
cd /Users/abelbalog/Documents/Development/private/lyrica
git diff --stat "$(cat /tmp/arch3-baseline.txt)" -- apps/lyron_app/test/presentation/song_editor/song_editor_screen_test.dart
```

Expected: no output.

- [ ] **Step 7: Size check and commit**

```bash
wc -l apps/lyron_app/lib/src/presentation/song_editor/song_editor_screen.dart
```

Expected: under 400.

```bash
cd apps/lyron_app && dart format lib test && cd ..
git add apps/lyron_app/lib/src/presentation/song_editor/ apps/lyron_app/test/presentation/song_editor/
git commit -m "refactor(song-editor): extract editor widgets and selection module

Moves the presentation widgets into presentation/song_editor/widgets/ and
the cursor-preservation helpers into song_editor_selection.dart, which now
has direct unit tests instead of being reachable only through a rendered
editor."
```

---

## Task 7: Extract the song reader widgets and behaviour classes

This task changes where behaviour lives, so it is the highest-risk extraction. Do the widgets first, run the suite, then the behaviour classes one at a time, running the suite after each.

**Files:**
- Create: `widgets/song_reader_app_bar.dart`, `widgets/song_reader_overflow_menu.dart`, `song_reader_zoom_persistence.dart`, `song_reader_immersive_mode.dart`, `song_reader_song_actions.dart` (all under `apps/lyron_app/lib/src/presentation/song_reader/`)
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_screen.dart`

- [ ] **Step 1: Move the overflow menu and app bar**

`_SongReaderOverflowAction` (45–51) → public `SongReaderOverflowAction` in `widgets/song_reader_overflow_menu.dart`, together with the `PopupMenuButton` construction from the app bar. The menu widget takes the available actions and one `void Function(SongReaderOverflowAction)` callback; it must not read providers — the screen decides which actions are available (capability checks stay in the screen).

`widgets/song_reader_app_bar.dart` takes the title, the warning count / warning tap callback, and the overflow menu widget.

Run: `cd apps/lyron_app && flutter analyze && flutter test test/presentation/song_reader/` — expected PASS.

- [ ] **Step 2: Extract `SongReaderImmersiveMode`**

```dart
// apps/lyron_app/lib/src/presentation/song_reader/song_reader_immersive_mode.dart
import 'package:flutter/services.dart';

/// Applies the system UI mode for the reader, skipping the platform call when
/// the requested mode already matches the last applied one.
class SongReaderImmersiveMode {
  bool? _lastApplied;

  void apply({required bool immersive}) {
    if (_lastApplied == immersive) {
      return;
    }
    _lastApplied = immersive;
    SystemChrome.setEnabledSystemUIMode(
      immersive ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  void restore() {
    _lastApplied = null;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
}
```

Replace the exact mode values above with whatever `_applyImmersiveMode` uses today — read `song_reader_screen.dart:311–330` first and copy them. The screen holds a `final _immersiveMode = SongReaderImmersiveMode();`, calls `apply(immersive: ...)` where it called `_applyImmersiveMode`, and `restore()` in `dispose()`.

Run: `cd apps/lyron_app && flutter test test/presentation/song_reader/` — expected PASS, including the dedupe test from Task 4.

- [ ] **Step 3: Extract `SongReaderZoomPersistence`**

Moves `_seedZoomFromStorage`, `_persistFontScale`, `_persistZoomTimer`, `_seededZoom`. The class takes the store future and the user/song identifiers as constructor arguments and exposes `Future<double?> seed()`, `void persist(double scale)`, and `void dispose()`. The debounce duration keeps its current value — read it from the screen, do not pick a new one. The screen keeps the `ref.read` calls that resolve the store and the user id and passes the resolved values in; the class itself must not take a `Ref`.

Run: `cd apps/lyron_app && flutter test test/presentation/song_reader/` — expected PASS, including the seed and debounce-persist tests.

- [ ] **Step 4: Extract `SongReaderSongActions`**

Moves the edit and delete flows (~500–560). This one does need `WidgetRef` and `BuildContext`, so it is a plain class whose methods take them:

```dart
class SongReaderSongActions {
  const SongReaderSongActions({required this.songId});

  final String songId;

  Future<void> edit(BuildContext context, WidgetRef ref) async { /* moved body */ }

  Future<void> delete(BuildContext context, WidgetRef ref) async { /* moved body */ }
}
```

Every `ref.read` / `ref.invalidate` inside moves verbatim, including
`ref.invalidate(songMutationEntriesProvider)` and
`ref.invalidate(songLibraryListProvider)`. Every `context.mounted` guard moves
with its await — do not drop or reorder one.

- [ ] **Step 5: Verify no provider drift and no test edits**

```bash
cd /Users/abelbalog/Documents/Development/private/lyrica
git show "$(cat /tmp/arch3-baseline.txt)":apps/lyron_app/lib/src/presentation/song_reader/song_reader_screen.dart \
  | grep -oE 'ref\.(watch|read|listen|invalidate)\([^)]*' | sort | uniq -c > /tmp/arch3-reader-before.txt
grep -rhoE 'ref\.(watch|read|listen|invalidate)\([^)]*' \
  apps/lyron_app/lib/src/presentation/song_reader/song_reader_screen.dart \
  apps/lyron_app/lib/src/presentation/song_reader/song_reader_song_actions.dart \
  apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_app_bar.dart \
  apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_overflow_menu.dart \
  | sort | uniq -c > /tmp/arch3-reader-after.txt
diff /tmp/arch3-reader-before.txt /tmp/arch3-reader-after.txt
git diff --stat "$(cat /tmp/arch3-baseline.txt)" -- apps/lyron_app/test/presentation/song_reader/song_reader_screen_test.dart
```

Expected: empty diff, no output from the second command.

- [ ] **Step 6: Size check, full suite, commit**

```bash
wc -l apps/lyron_app/lib/src/presentation/song_reader/song_reader_screen.dart
cd apps/lyron_app && flutter analyze && flutter test
```

Expected: under 400 lines, analyze clean, full suite PASS.

```bash
cd apps/lyron_app && dart format lib test && cd ..
git add apps/lyron_app/lib/src/presentation/song_reader/
git commit -m "refactor(song-reader): extract reader widgets and behaviour classes

Splits the reader screen into widgets (app bar, overflow menu) and three
behaviour classes: zoom persistence, immersive mode with last-applied
de-duplication, and the edit/delete song actions. Provider calls and their
scoping are unchanged; the characterization tests pass untouched."
```

---

## Task 8: Isolated tests for the extracted widgets

Every extracted widget now gets a test that builds it directly instead of through the screen. This is the ARCH-3 payoff and part of the definition of done.

**Files:**
- Create: `apps/lyron_app/test/presentation/planning/widgets/plan_editor_dialog_test.dart`
- Create: `apps/lyron_app/test/presentation/planning/widgets/session_editor_dialog_test.dart`
- Create: `apps/lyron_app/test/presentation/planning/widgets/plan_song_item_row_test.dart`
- Create: `apps/lyron_app/test/presentation/planning/widgets/retryable_error_state_test.dart`
- Create: `apps/lyron_app/test/presentation/song_editor/widgets/song_editor_stepper_test.dart`
- Create: `apps/lyron_app/test/presentation/song_editor/widgets/song_editor_summary_list_test.dart`
- Create: `apps/lyron_app/test/presentation/song_editor/widgets/song_editor_tab_bar_test.dart`
- Create: `apps/lyron_app/test/presentation/song_reader/widgets/song_reader_overflow_menu_test.dart`
- Create: `apps/lyron_app/test/presentation/song_reader/song_reader_immersive_mode_test.dart`

`PlanSessionCard` and `SongEditorTopBar` stay covered by the screen-level suites — they need the full provider graph, and duplicating that harness would buy nothing.

- [ ] **Step 1: Write the pure-widget tests (no providers needed)**

```dart
// test/presentation/planning/widgets/retryable_error_state_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/presentation/planning/widgets/retryable_error_state.dart';

void main() {
  testWidgets('shows the message and calls onRetry', (tester) async {
    var retries = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RetryableErrorState(
            message: 'Could not load',
            onRetry: () => retries += 1,
          ),
        ),
      ),
    );

    expect(find.text('Could not load'), findsOneWidget);

    await tester.tap(find.byType(TextButton));
    await tester.pump();

    expect(retries, 1);
  });
}
```

Follow the same shape for `song_editor_stepper_test.dart` (assert `−` and `+` fire their callbacks and the value renders), `song_editor_summary_list_test.dart` (assert one row per non-null metadata value), `song_editor_tab_bar_test.dart` (assert tapping a tab reports the right `SongEditorTab`), and `song_reader_overflow_menu_test.dart` (assert tapping an entry reports the right `SongReaderOverflowAction`). Match the real constructor parameters — read each widget file before writing its test.

- [ ] **Step 2: Write the provider-backed widget tests**

`plan_editor_dialog_test.dart`, `session_editor_dialog_test.dart` and `plan_song_item_row_test.dart` need a `ProviderScope`. Copy the minimal overrides from `plan_detail_screen_test.dart` — `activePlanningContextProvider`, `planningWriteServiceProvider`, `capabilityResolverProvider` — and nothing more. Each test asserts one thing: the dialog reports the edited draft, the rename dialog rejects blank input, the row's delete button calls `deleteSessionItem`.

- [ ] **Step 3: Write `song_reader_immersive_mode_test.dart`**

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_immersive_mode.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('applies once per state change', () async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemChrome.setEnabledSystemUIMode') {
        calls.add(call.arguments.toString());
      }
      return null;
    });

    final mode = SongReaderImmersiveMode()
      ..apply(immersive: true)
      ..apply(immersive: true)
      ..apply(immersive: false);

    await Future<void>.delayed(Duration.zero);

    expect(calls, hasLength(2));
  });
}
```

- [ ] **Step 4: Run the new tests**

Run: `cd apps/lyron_app && flutter test test/presentation/planning/widgets/ test/presentation/song_editor/widgets/ test/presentation/song_reader/widgets/ test/presentation/song_reader/song_reader_immersive_mode_test.dart`

Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
cd apps/lyron_app && dart format lib test && cd ..
git add apps/lyron_app/test/presentation/
git commit -m "test(presentation): add isolated tests for the extracted widgets

Each extracted widget is now exercised on its own instead of only through a
fully wired screen, which is the point of the ARCH-3 decomposition."
```

---

## Task 9: Clear the optimistic reorder overlay on refetch (behaviour change, TDD)

Closes gap 1 of `docs/deferred/2026-04-30-planning-reorder-optimistic-state.md`. Today the overlay is cleared only on failure, so a compatible-but-stale overlay masks the refreshed projection for the lifetime of the screen.

**Files:**
- Create: `apps/lyron_app/lib/src/application/planning/planning_reorder_overlay.dart`
- Create: `apps/lyron_app/test/application/planning/planning_reorder_overlay_test.dart`
- Modify: `apps/lyron_app/lib/src/presentation/planning/plan_detail_screen.dart`
- Modify: `apps/lyron_app/lib/src/presentation/planning/widgets/plan_session_card.dart`
- Test: `apps/lyron_app/test/presentation/planning/plan_detail_screen_test.dart`

- [ ] **Step 1: Write the failing unit test for the pure rule**

```dart
// test/application/planning/planning_reorder_overlay_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/planning_reorder_overlay.dart';

void main() {
  test('keeps the overlay while a write is in flight', () {
    expect(
      resolveReorderOverlay(
        optimisticOrder: const ['b', 'a'],
        projectionOrder: const ['b', 'a'],
        hasWriteInFlight: true,
      ),
      const ['b', 'a'],
    );
  });

  test('clears the overlay once the projection agrees and nothing is in flight', () {
    expect(
      resolveReorderOverlay(
        optimisticOrder: const ['b', 'a'],
        projectionOrder: const ['b', 'a'],
        hasWriteInFlight: false,
      ),
      isNull,
    );
  });

  test('keeps the overlay when the projection has not caught up yet', () {
    expect(
      resolveReorderOverlay(
        optimisticOrder: const ['b', 'a'],
        projectionOrder: const ['a', 'b'],
        hasWriteInFlight: false,
      ),
      const ['b', 'a'],
    );
  });

  test('clears the overlay when the projection is structurally incompatible', () {
    expect(
      resolveReorderOverlay(
        optimisticOrder: const ['b', 'a'],
        projectionOrder: const ['a', 'b', 'c'],
        hasWriteInFlight: false,
      ),
      isNull,
    );
  });

  test('is a no-op when there is no overlay', () {
    expect(
      resolveReorderOverlay(
        optimisticOrder: null,
        projectionOrder: const ['a', 'b'],
        hasWriteInFlight: false,
      ),
      isNull,
    );
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `cd apps/lyron_app && flutter test test/application/planning/planning_reorder_overlay_test.dart`

Expected: FAIL — the URI does not exist.

- [ ] **Step 3: Implement the pure rule**

```dart
// lib/src/application/planning/planning_reorder_overlay.dart

/// Decides whether an optimistic reorder overlay should survive the arrival of
/// a refreshed projection.
///
/// The overlay exists so a drag stays visible while the local write and the
/// provider invalidation settle. It must not outlive that window: once the
/// projection agrees with it, or can no longer be reconciled with it, the
/// projection is the single source of truth again.
List<String>? resolveReorderOverlay({
  required List<String>? optimisticOrder,
  required List<String> projectionOrder,
  required bool hasWriteInFlight,
}) {
  if (optimisticOrder == null) {
    return null;
  }
  if (hasWriteInFlight) {
    return optimisticOrder;
  }
  if (optimisticOrder.length != projectionOrder.length ||
      !optimisticOrder.toSet().containsAll(projectionOrder)) {
    return null;
  }
  final agrees = () {
    for (var index = 0; index < optimisticOrder.length; index++) {
      if (optimisticOrder[index] != projectionOrder[index]) {
        return false;
      }
    }
    return true;
  }();
  return agrees ? null : optimisticOrder;
}
```

- [ ] **Step 4: Run it and watch it pass**

Run: `cd apps/lyron_app && flutter test test/application/planning/planning_reorder_overlay_test.dart`

Expected: PASS (5 tests).

- [ ] **Step 5: Write the failing widget test for the screen wiring**

Add to `plan_detail_screen_test.dart`:

```dart
  testWidgets('drops the session overlay once the projection catches up', (
    tester,
  ) async {
    // 1. Pump with the three-session fixture and a write service whose
    //    reorderSessions completes immediately.
    // 2. Drag session 0 to the end; assert the optimistic order is visible.
    // 3. Emit a refreshed PlanDetail whose session order already equals the
    //    optimistic order (bump the mutable plan-detail override the harness
    //    already exposes), pump.
    // 4. Emit a second refreshed PlanDetail in the ORIGINAL order, pump.
    // 5. Assert the screen now renders the ORIGINAL order — proving the
    //    overlay was dropped in step 3 rather than masking step 4 forever.
  });
```

Write the real body using the harness's existing mutable-override mechanism (the same one `'keeps current plan detail visible while revision reloads'` at `:275` uses). Step 5 is the assertion that fails today.

- [ ] **Step 6: Run it and watch it fail**

Run: `cd apps/lyron_app && flutter test test/presentation/planning/plan_detail_screen_test.dart --plain-name 'drops the session overlay'`

Expected: FAIL — the screen still renders the stale optimistic order in step 5.

- [ ] **Step 7: Wire the rule into both overlays**

In `_PlanDetailScreenState._orderedSessions`, and in the session card's item equivalent, call `resolveReorderOverlay` when a fresh projection arrives, and clear the stored overlay field when it returns `null`. "Write in flight" is tracked by comparing the generation counter against the last completed generation — add a `_lastCompletedSessionReorderGeneration` field set in `_performSessionReorder` (both the success and the failure path), and pass `hasWriteInFlight: _sessionReorderGeneration != _lastCompletedSessionReorderGeneration`. Do the same for items.

Clearing the field during `build` is not allowed (`setState` during build). Clear it in the data callback before the list is built, guarded so it does not schedule a rebuild loop — assign the field directly and let the current build use the resolved value.

- [ ] **Step 8: Run the whole planning suite**

Run: `cd apps/lyron_app && flutter test test/presentation/planning/ test/application/planning/`

Expected: PASS, including every characterization test from Tasks 1–2 — particularly `'stale item reorder result does not clear newer order'` and `'queues session reorder requests while one is in flight'`, which pin the in-flight case this change must not break.

- [ ] **Step 9: Commit**

```bash
cd apps/lyron_app && dart format lib test && cd ..
git add apps/lyron_app/lib/src/application/planning/planning_reorder_overlay.dart \
        apps/lyron_app/test/application/planning/planning_reorder_overlay_test.dart \
        apps/lyron_app/lib/src/presentation/planning/ \
        apps/lyron_app/test/presentation/planning/plan_detail_screen_test.dart
git commit -m "fix(planning): drop the reorder overlay once the projection agrees

The optimistic session and item reorder overlays were cleared only on write
failure, so an overlay that stayed structurally compatible masked every
later projection for the lifetime of the screen. The overlay now survives
exactly as long as its write is in flight or the projection disagrees with
it, decided by a pure rule that is unit tested on its own."
```

---

## Task 10: Surface the reorder rollback to the user

Closes gap 2 of the deferred file: a failed reorder rolls back silently today.

**Files:**
- Modify: `apps/lyron_app/lib/src/shared/app_strings.dart`
- Modify: `apps/lyron_app/lib/src/presentation/planning/plan_detail_screen.dart`
- Modify: `apps/lyron_app/lib/src/presentation/planning/widgets/plan_session_card.dart`
- Test: `apps/lyron_app/test/presentation/planning/plan_detail_screen_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
  testWidgets('shows a message when the session reorder write fails', (
    tester,
  ) async {
    final writeService = _FakePlanningWriteService(
      onReorderSessions: (_) async => throw StateError('session reorder failed'),
    );

    await tester.pumpWidget(
      buildApp(
        planDetailValue: _editablePlanDetailFixture(),
        writeService: writeService,
      ),
    );
    await tester.pumpAndSettle();

    tester
        .widgetList<ReorderableListView>(find.byType(ReorderableListView))
        .first
        .onReorder(0, 3);
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.planningReorderFailedMessage), findsOneWidget);
  });
```

Add the item-level twin using `onReorderSessionItems` and the item fixture, asserting the same string.

- [ ] **Step 2: Run and watch both fail**

Run: `cd apps/lyron_app && flutter test test/presentation/planning/plan_detail_screen_test.dart --plain-name 'reorder write fails'`

Expected: FAIL — `AppStrings.planningReorderFailedMessage` does not exist yet (compile error), which is the correct first failure.

- [ ] **Step 3: Add the string**

In `lib/src/shared/app_strings.dart`, next to the other planning messages:

```dart
  static const planningReorderFailedMessage =
      'Could not save the new order. The previous order was restored.';
```

Match the surrounding style (the file is the single place strings live — do not inline English at the call site; that is finding UX-10).

- [ ] **Step 4: Show it on rollback**

In both `_reportReorderError` call sites that follow a rollback, show a `SnackBar` with that message via `ScaffoldMessenger.of(context)`, guarded by `mounted`. Keep the existing `FlutterError.reportError` call — the message is additive, the diagnostics stay.

- [ ] **Step 5: Run**

Run: `cd apps/lyron_app && flutter test test/presentation/planning/`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
cd apps/lyron_app && dart format lib test && cd ..
git add apps/lyron_app/lib/src/shared/app_strings.dart apps/lyron_app/lib/src/presentation/planning/ apps/lyron_app/test/presentation/planning/
git commit -m "fix(planning): surface a failed reorder instead of rolling back silently"
```

---

## Task 11: Documentation

**Files:**
- Create: `docs/architecture/decisions/ADR-023-optimistic-reorder-overlay-lifecycle.md`
- Modify: `docs/architecture/architecture.md`
- Modify: `docs/architecture/repository-review-2026-06-22.md`
- Delete: `docs/deferred/2026-04-30-planning-reorder-optimistic-state.md`

- [ ] **Step 1: Write ADR-023**

Follow the structure of `ADR-022-active-organization-resolver.md` (read it first). Content: context (overlay masked refreshed projections indefinitely; failures were silent), decision (the overlay lives exactly as long as its write is in flight or the projection disagrees; failure is surfaced with `AppStrings.planningReorderFailedMessage`), consequences (the rule is pure and unit tested in `planning_reorder_overlay.dart`; both session and item overlays share it), status Accepted, date 2026-07-27.

- [ ] **Step 2: Update `architecture.md`**

Add or extend the presentation-layer section with the screen/widget boundary rule: screens own orchestration and interaction state; `widgets/` holds independently testable components; extracted widgets keep the provider scope they had (ARCH-2) and resolve organization identity only through the active-context providers (ARCH-5).

- [ ] **Step 3: Strike ARCH-3 in the review doc**

Follow the existing convention exactly (see line 496 and 503 of the review doc):

```markdown
- ~~ARCH-3: decompose plan_detail / song_editor.~~ **Done (ui-decomposition-phase2).**
```

Also update the finding table row at line 76 and the narrative at line 188 so the line counts and status are no longer stale.

- [ ] **Step 4: Delete the deferred file**

```bash
git rm docs/deferred/2026-04-30-planning-reorder-optimistic-state.md
```

Per `docs/deferred/README.md`: "Remove or update the deferred entry in the same change that resolves or supersedes it."

- [ ] **Step 5: Commit**

```bash
git add docs/
git commit -m "docs(architecture): record ARCH-3 decomposition and overlay lifecycle

Adds ADR-023 for the optimistic reorder overlay lifecycle, documents the
screen/widget boundary rule, marks ARCH-3 done in the repository review,
and removes the deferred reorder-overlay entry it closes."
```

---

## Task 12: Slice verification

- [ ] **Step 1: Prove the size targets**

```bash
cd /Users/abelbalog/Documents/Development/private/lyrica
wc -l apps/lyron_app/lib/src/presentation/planning/plan_detail_screen.dart \
      apps/lyron_app/lib/src/presentation/song_editor/song_editor_screen.dart \
      apps/lyron_app/lib/src/presentation/song_reader/song_reader_screen.dart
```

Expected: each under 400.

- [ ] **Step 2: Prove the characterization tests were not rewritten to fit the refactor**

```bash
git diff "$(cat /tmp/arch3-baseline.txt)" -- apps/lyron_app/test/presentation/ | grep -E '^-\s' | grep -v '^---'
```

Expected: only deletions that belong to Tasks 9–10 (the behaviour change), none from Tasks 5–7. Any removed assertion introduced in Tasks 1–4 is a red flag — investigate before continuing.

- [ ] **Step 3: Run the full local CI**

```bash
./scripts/run-ci-locally.sh verify
```

Expected: format clean, `flutter analyze` clean, full `flutter test` suite green. Paste the tail of the output into the slice report; do not claim the slice is done without it.

- [ ] **Step 4: Do not merge**

S5 (UX-1, UX-2) lands on this same branch before the PR is finalized. Stop here and report.
