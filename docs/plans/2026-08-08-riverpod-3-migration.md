# Riverpod 3 Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land `flutter_riverpod` 3.4.2 with every song-reader error-path test passing with its original meaning.

**Architecture:** Riverpod 3 retries failed providers by default, so a failed provider never settles into `AsyncError` and the reader's error states never render. A named no-retry policy is declared on each async provider — `origin.retry` wins over the container and survives test overrides, so production and tests share one semantic with no wiring at the ~175 scope construction sites. Targeting 3.4.2 (not 3.3.2) pulls in the upstream `markNeedsBuild` fixes, which forces Flutter 3.44.9 and with it the `ReorderableListView.onReorder` → `onReorderItem` migration.

**Tech Stack:** Flutter 3.44.9 / Dart 3.12.2, `flutter_riverpod` 3.4.2, `flutter_test`.

**Spec:** `docs/specs/2026-08-08-riverpod-3-migration.md`

**Working directory:** all `flutter` commands run from `apps/lyron_app`. All paths below are relative to `apps/lyron_app` unless they start with `docs/` or `.github/`.

**Starting state:** the branch already carries the mechanical API migration (commit `b4477d4`) and the spec (`b3bc299`). `pubspec.yaml` and `pubspec.lock` hold an uncommitted bump to `flutter_riverpod: ^3.4.2`. Nine tests fail: eight on automatic retry, one because `plan_detail_screen_test.dart` no longer compiles under Flutter 3.44.

---

### Task 1: Pin the toolchain

**Files:**
- Modify: `pubspec.yaml`
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Widen the Dart SDK constraint**

`flutter_riverpod` 3.4.1+ requires Dart `>=3.12.0`. In `pubspec.yaml`:

```yaml
environment:
  sdk: ^3.12.0
```

The `flutter_riverpod: ^3.4.2` line is already in place from the uncommitted change.

- [ ] **Step 2: Bump the CI Flutter version**

`.github/workflows/ci.yml` pins `flutter-version: 3.38.5` in two jobs. Both become:

```yaml
          flutter-version: 3.44.9
```

Verify both were changed:

```bash
grep -c "flutter-version: 3.44.9" .github/workflows/ci.yml
```

Expected: `2`

- [ ] **Step 3: Resolve and confirm the version**

Run: `flutter pub get`
Then: `grep -A6 "^  flutter_riverpod:" pubspec.lock | grep -A1 version`
Expected: `version: "3.4.2"`

- [ ] **Step 4: Commit**

```bash
git add pubspec.yaml pubspec.lock ../../.github/workflows/ci.yml
git commit -m "chore(deps): target flutter_riverpod 3.4.2 on Flutter 3.44.9

3.4.0 and 3.4.2 fix the markNeedsBuild exception raised when a dirty
provider is flushed inside a widget's build phase, which is the sole
cause of the song_reader_flow_test failure. Taking the upstream fix
rather than working around it requires Dart >=3.12.0, so CI and the
SDK constraint move with it."
```

---

### Task 2: Migrate `onReorder` to `onReorderItem`

Flutter 3.44 deprecates `ReorderableListView.onReorder`. `onReorderItem` receives a `newIndex` already adjusted for the removal of the dragged item, and is not called at all when the adjusted indices are equal:

```dart
// packages/flutter/lib/src/widgets/reorderable_list.dart
void _handleReorderItem(int oldIndex, int newIndex) {
  if (widget.onReorder != null && oldIndex != newIndex) {
    widget.onReorder?.call(oldIndex, newIndex);
    return;
  }
  if (newIndex > oldIndex) {
    newIndex -= 1;
  }
  if (oldIndex != newIndex) {
    widget.onReorderItem?.call(oldIndex, newIndex);
  }
}
```

Both application handlers already perform that same adjustment themselves, so a bare rename would apply it twice and shift every downward drag by one. The adjustment must move out of the handlers.

**Files:**
- Modify: `lib/src/presentation/planning/plan_detail_screen.dart:188` and `:322-323`
- Modify: `lib/src/presentation/planning/widgets/plan_session_card.dart:221` and `:544-545`
- Test: `test/presentation/planning/plan_detail_screen_test.dart`

- [ ] **Step 1: Write the failing index-semantics test**

Append to `test/presentation/planning/plan_detail_screen_test.dart`, inside the existing top-level `main()` group, next to the other reorder tests. It pins the contract that a downward drag of the first item past the second lands it at index 1 — the case a double adjustment would break.

```dart
  testWidgets('session item drag down lands at the adjusted index', (
    tester,
  ) async {
    final writeService = _RecordingPlanningWriteService();
    await tester.pumpWidget(
      _buildPlanDetailScreen(writeService: writeService),
    );
    await tester.pumpAndSettle();

    final itemList = tester
        .widgetList<ReorderableListView>(find.byType(ReorderableListView))
        .elementAt(1);

    // Dragging item 0 below item 1: ReorderableListView reports raw
    // newIndex 2, and hands onReorderItem the removal-adjusted 1.
    itemList.onReorderItem!(0, 1);
    await tester.pumpAndSettle();

    expect(
      writeService.reorderedSessionItemDraft!.orderedItemIds,
      ['item-2', 'item-1', 'item-3'],
    );
  });
```

If the surrounding test file uses different helper names for building the screen or for the recording write service, use the names already present in that file — do not introduce new helpers. Read the neighbouring reorder tests (around `test/presentation/planning/plan_detail_screen_test.dart:2058`) and mirror their setup and their session/item id fixtures exactly, adjusting the expected id list to match those fixtures.

- [ ] **Step 2: Run it and watch it fail to compile**

Run: `flutter test test/presentation/planning/plan_detail_screen_test.dart --plain-name "session item drag down lands at the adjusted index"`
Expected: a compile failure — `onReorderItem` is null because the widget still passes `onReorder`, and the file does not compile at all yet because of the pre-existing `unchecked_use_of_nullable_value` errors fixed in Step 4.

- [ ] **Step 3: Switch both widgets to `onReorderItem` and drop the local adjustment**

In `lib/src/presentation/planning/plan_detail_screen.dart`:

```dart
            onReorderItem: (oldIndex, newIndex) =>
                _reorderSessions(ref, oldIndex, newIndex),
```

and in `_reorderSessions`, delete these three lines:

```dart
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
```

In `lib/src/presentation/planning/widgets/plan_session_card.dart`:

```dart
              onReorderItem: (oldIndex, newIndex) =>
                  _reorderItems(ref, oldIndex, newIndex),
```

and in `_reorderItems`, delete the same three lines.

Leave the remaining guards (`newIndex < 0`, `newIndex >= currentOrder.length`, `oldIndex == newIndex`) in place; they still hold and the last one is now merely redundant with the framework's own check.

- [ ] **Step 4: Update every existing `onReorder` call in the test file**

`test/presentation/planning/plan_detail_screen_test.dart` invokes the callback directly with raw indices, which no longer compiles (`onReorder` is now nullable) and no longer means the same drag. Each call translates as:

```
itemList.onReorder(old, new)  ->  itemList.onReorderItem!(old, new > old ? new - 1 : new)
```

So `onReorder(0, 2)` becomes `onReorderItem!(0, 1)`; `onReorder(1, 0)` becomes `onReorderItem!(1, 0)`; `onReorder(0, 0)` becomes `onReorderItem!(0, 0)`.

Apply it at every call site in the file. Find them with:

```bash
grep -n "onReorder(" test/presentation/planning/plan_detail_screen_test.dart
```

- [ ] **Step 5: Verify the analyzer is clean and the reorder tests pass**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test test/presentation/planning/plan_detail_screen_test.dart`
Expected: all tests pass, including the new one.

- [ ] **Step 6: Commit**

```bash
git add lib/src/presentation/planning/plan_detail_screen.dart lib/src/presentation/planning/widgets/plan_session_card.dart test/presentation/planning/plan_detail_screen_test.dart
git commit -m "refactor(planning): move reordering onto onReorderItem

Flutter 3.44 deprecates ReorderableListView.onReorder. onReorderItem
receives a newIndex already adjusted for the removal of the dragged
item, so both handlers drop the adjustment they were doing themselves;
keeping it would shift every downward drag by one. A new test pins the
adjusted index for a downward drag."
```

---

### Task 3: Disable automatic provider retry

**Files:**
- Create: `lib/src/application/provider_retry_policy.dart`
- Modify: `lib/src/presentation/planning/planning_providers.dart` (5 providers)
- Modify: `lib/src/presentation/song_library/song_library_providers.dart` (6 providers)
- Modify: `lib/src/presentation/song_editor/song_editor_providers.dart` (2 providers)
- Modify: `lib/src/presentation/song_reader/session_scoped_reader_context_provider.dart` (1 provider)
- Modify: `lib/src/presentation/sync/unified_sync_providers.dart` (1 provider)
- Create: `test/application/provider_retry_policy_test.dart`

- [ ] **Step 1: Confirm the failures are still there**

Run: `flutter test test/presentation/song_reader/song_reader_screen_test.dart --plain-name "shows an unavailable state when the song cannot be found"`
Expected: FAIL — `Found 0 widgets with text "This song is unavailable."`. The provider is retrying, so it never settles into `AsyncError` and the error branch never renders.

- [ ] **Step 2: Write the policy**

Create `lib/src/application/provider_retry_policy.dart`:

```dart
/// The retry policy for every provider in this application: never retry.
///
/// Riverpod 3 retries a failed provider up to ten times with exponential
/// backoff by default. While retrying, the element stays in
/// `AsyncLoading(retrying: true)` instead of settling into `AsyncError`, so a
/// failure never reaches the UI and `await provider.future` never completes
/// with it.
///
/// That contradicts the failure contract this application already has: a
/// failure surfaces immediately, and retrying is an explicit user action. See
/// ADR-032.
///
/// Declared on the providers rather than on the container because Riverpod
/// resolves retry as `origin.retry ?? container.retry ?? defaultRetry`, and
/// `origin` survives test overrides — so production and every test share this
/// policy without wiring it into each `ProviderScope`.
Duration? noAutomaticProviderRetry(int retryCount, Object error) => null;
```

- [ ] **Step 3: Apply it to every `FutureProvider` and `StreamProvider` in `lib/`**

List them:

```bash
grep -rEn "= *(FutureProvider|StreamProvider)" lib/
```

There are fourteen, all `FutureProvider.autoDispose`. Add `retry: noAutomaticProviderRetry` as a named argument to each declaration and import the policy in each file:

```dart
import 'package:lyron_app/src/application/provider_retry_policy.dart';
```

For a plain `FutureProvider.autoDispose`:

```dart
final songLibraryListProvider = FutureProvider.autoDispose<List<SongSummary>>((
  ref,
) {
  // ... unchanged body ...
}, retry: noAutomaticProviderRetry);
```

For a `.family`:

```dart
final songLibraryReaderProvider = FutureProvider.autoDispose
    .family<SongReaderResult, String>((ref, songId) async {
      // ... unchanged body ...
    }, retry: noAutomaticProviderRetry);
```

Change nothing else — no body edits, no signature changes.

- [ ] **Step 4: Run the eight retry-mechanism tests**

Run:

```bash
flutter test test/presentation/song_reader/song_reader_screen_test.dart test/presentation/song_reader/session_scoped_reader_context_provider_test.dart test/router/app_router_test.dart test/integration/song_reader_flow_test.dart
```

Expected: all pass. If any still fails, do not adjust an assertion — find the provider in its chain that is missing the policy.

- [ ] **Step 5: Write the guard test**

Create `test/application/provider_retry_policy_test.dart`. It reads the library sources so a newly added async provider cannot silently opt back into automatic retry:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every async provider declares the no-retry policy', () {
    final declaration = RegExp(
      r'=\s*(FutureProvider|StreamProvider)\b',
    );

    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      final source = entity.readAsStringSync();
      var searchFrom = 0;

      while (true) {
        final match = declaration.firstMatch(source.substring(searchFrom));
        if (match == null) break;

        final start = searchFrom + match.start;
        final end = _declarationEnd(source, start);
        final body = source.substring(start, end);

        if (!body.contains('retry: noAutomaticProviderRetry')) {
          final line = '\n'.allMatches(source.substring(0, start)).length + 1;
          offenders.add('${entity.path}:$line');
        }

        searchFrom = end;
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'These async providers do not declare retry: noAutomaticProviderRetry. '
          'Riverpod 3 retries failed providers by default, which keeps a '
          'failure from ever reaching the UI. See ADR-032.\n'
          '${offenders.join('\n')}',
    );
  });
}

/// Returns the offset just past the `);` that closes the provider declaration
/// starting at [start], by tracking parenthesis depth.
int _declarationEnd(String source, int start) {
  var depth = 0;
  var seenOpen = false;

  for (var i = start; i < source.length; i++) {
    final char = source[i];
    if (char == '(') {
      depth++;
      seenOpen = true;
    } else if (char == ')') {
      depth--;
      if (seenOpen && depth == 0) return i + 1;
    }
  }

  return source.length;
}
```

- [ ] **Step 6: Verify the guard passes, then verify it actually guards**

Run: `flutter test test/application/provider_retry_policy_test.dart`
Expected: PASS.

Temporarily delete `, retry: noAutomaticProviderRetry` from `songLibraryListProvider`, run the guard again, and confirm it FAILS naming that file and line. Restore the argument and confirm it passes again. A guard that cannot fail is not a guard.

- [ ] **Step 7: Commit**

```bash
git add lib/src/application/provider_retry_policy.dart lib/src/presentation test/application/provider_retry_policy_test.dart
git commit -m "fix(providers): opt out of Riverpod 3 automatic provider retry

Riverpod 3 retries a failed provider up to ten times by default. While
retrying it stays in AsyncLoading rather than settling into AsyncError,
so the song reader's failure states never rendered and awaiting a
provider's future never completed with its error.

The policy is declared on each async provider because origin.retry wins
over the container and survives test overrides, giving production and
every test the same semantic without touching the ~175 ProviderScope
construction sites. A guard test fails when a new async provider omits
it."
```

---

### Task 4: Record the decision and clear the deferred document

**Files:**
- Create: `docs/architecture/decisions/ADR-032-no-automatic-provider-retry.md`
- Delete: `docs/deferred/2026-07-30-riverpod-3-migration.md`
- Modify: `docs/architecture/architecture.md`

- [ ] **Step 1: Write ADR-032**

Create `docs/architecture/decisions/ADR-032-no-automatic-provider-retry.md`, following the structure of the neighbouring ADRs (read `ADR-031-session-scoped-catalog-refresh.md` for the house format). It must contain:

- **Context:** Riverpod 3 enables automatic retry by default — up to ten attempts, 200ms to 6.4s backoff. A retrying element emits `AsyncLoading(error: …, retrying: true)` rather than `AsyncError`, so failures never reach the UI and `await provider.future` never completes with the error, instead failing later with `disposed during loading state` once autoDispose runs.
- **Decision:** No automatic retry. `noAutomaticProviderRetry` is declared on every `FutureProvider`/`StreamProvider` in `lib/`, enforced by `test/application/provider_retry_policy_test.dart`. Provider failures surface immediately; retrying is an explicit user action.
- **Why the provider level, not the container:** Riverpod resolves `origin.retry ?? container.retry ?? defaultRetry` and `origin` survives test overrides, so one declaration covers production and all ~175 test scope constructions identically.
- **Evidence:** `test/presentation/song_reader/song_reader_screen_test.dart`, "shows a retryable backend failure state when loading fails", asserts the failure state renders with a "Try again" affordance, that tapping it reloads, and that the loader ran exactly twice. Automatic retry removes the affordance, hides the failure, and changes the count.
- **Rejected — container-level policy:** conceptually the right level for an app-wide rule, but it would have to be threaded through roughly 175 `ProviderScope`/`ProviderContainer` constructions in `test/`, and any omission silently gives that test different semantics from production.
- **Rejected — selective retry (transient errors only):** appealing, but the retryable-failure contract above is expressed with a plain `Exception`, indistinguishable from a transient one. Honouring it means not retrying that case either, which leaves the policy with nothing to do.
- **Rejected — restating the reader error taxonomy in Riverpod 3 terms:** the deferred document proposed this on the hypothesis that `ProviderException` wrapping broke the taxonomy. Reproduction disproved it: `AsyncValue.error` carries the original error, and `FutureProvider.future` resolves through `valueOrRawException`. `ProviderException` is only thrown on the synchronous read path, which this taxonomy does not use. No taxonomy change was needed.
- **Target version:** `flutter_riverpod` 3.4.2 rather than 3.3.2, because 3.4.0 and 3.4.2 fix the `markNeedsBuild`-during-build defect that otherwise required an application-side workaround. The cost is Flutter 3.44.9 and the `onReorderItem` migration.
- **Note:** this is the first ADR to pin the reader error taxonomy contract. ADR-023 and ADR-024 cover the optimistic reorder overlay and the planning edit draft, not error typing.

- [ ] **Step 2: Link the ADR from the architecture document**

`docs/architecture/architecture.md` — add ADR-032 wherever that file lists the decisions, matching the existing entry style. Check how ADR-031 is referenced and follow it.

- [ ] **Step 3: Remove the deferred document**

```bash
git rm docs/deferred/2026-07-30-riverpod-3-migration.md
```

Confirm nothing still points at it:

```bash
grep -rn "2026-07-30-riverpod-3-migration" docs/ README.md
```

Expected: no matches. If any document references it, update that reference to `ADR-032` and the spec.

- [ ] **Step 4: Commit**

```bash
git add docs/architecture/decisions/ADR-032-no-automatic-provider-retry.md docs/architecture/architecture.md
git commit -m "docs(adr): record the no-automatic-provider-retry decision

ADR-032 pins the reader failure contract that Riverpod 3's default
retry silently broke, and records the rejected alternatives: a
container-level policy, selective retry, and restating the taxonomy in
Riverpod 3 terms. It also corrects the deferred document's hypothesis
that ProviderException wrapping was the cause; it was not.

Closes the Riverpod 3 migration deferred document."
```

---

### Task 5: Verify the whole slice

- [ ] **Step 1: Analyzer**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 2: Full suite**

Run: `flutter test`
Expected: no `[E]` lines, and the run ends with `All tests passed!`. The nine originally failing tests must pass unmodified in meaning — the only test file whose assertions changed is `plan_detail_screen_test.dart`, and only to express the same drags in `onReorderItem` coordinates.

- [ ] **Step 3: Web compile job**

Run: `flutter build web`
Expected: builds without error. This is the phase 3 CI job most likely to catch a Riverpod 3 conditional-import problem.

- [ ] **Step 4: Refresh the graph**

Refresh `graphify-out/` per `docs/workflows/ai-development.md`, and commit the result.

- [ ] **Step 5: Commit the graph refresh**

```bash
git add graphify-out
git commit -m "chore(graph): refresh the codebase graph after the Riverpod 3 migration"
```

---

## Out of Scope

ARCH-4 (melos) and SEC-2 ship separately. LF-T2, LF-T5, LF-T6, the web offline end-to-end document and the reader-fit margin document stay deferred and untouched.
