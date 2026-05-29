# Sync UI Consolidation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move all sync recovery into the unified status popup (per-song, per-plan-group, and a global discard-all), then delete the redundant per-screen sync surfaces and the song-library browse filter.

**Architecture:** The header control + popup are the single sync surface. `UnifiedSyncPlanRow` gains the aggregate references needed for group-level recovery. The popup (already a `ConsumerWidget`) calls the existing `songMutationSyncControllerProvider` / `planningMutationSyncControllerProvider`. A small new `UnifiedDiscardController` orchestrates active-organization discard-all behind a confirmation dialog. Per-screen surfaces and the browse filter are removed.

**Tech Stack:** Flutter, Riverpod, Drift, `flutter_test`. Repo runs from `apps/lyron_app`; tests via `flutter test`.

---

## Working directory

All paths are relative to `apps/lyron_app`. Run all `flutter test` commands from that directory.

## File Structure

- Modify `lib/src/application/sync/unified_sync_overview.dart` — add `UnifiedSyncPlanMutationRef` + `mutationRefs` on `UnifiedSyncPlanRow`; populate in `_buildPlanRows`.
- Create `lib/src/application/sync/unified_discard_controller.dart` — orchestrates discard-all.
- Modify `lib/src/presentation/sync/unified_sync_providers.dart` — wire `unifiedDiscardControllerProvider`.
- Modify `lib/src/presentation/sync/unified_sync_status_popup.dart` — row actions + global discard button.
- Modify `lib/src/shared/app_strings.dart` — new strings.
- Modify `lib/src/presentation/song_library/song_list_screen.dart` — delete surfaces + filter.
- Modify `lib/src/presentation/song_library/song_library_browse_state.dart`, `song_library_browse_row.dart`, `song_library_browse_controller.dart`, `song_library_providers.dart` — remove filter.
- Modify `lib/src/presentation/planning/plan_list_screen.dart`, `plan_detail_screen.dart`, `widgets/planning_workspace_shell.dart` — remove status surface; delete `widgets/planning_workspace_status_surface.dart`.
- Docs: `docs/product/sync-ux-contract.md`, `docs/specs/2026-05-15-pending-changes-cleanup.md`, `docs/specs/2026-05-29-sync-ui-consolidation.md`.

---

## Task 1: Add aggregate refs to plan rows

Plan-group recovery needs the `(aggregateType, aggregateId)` of every mutation in a group.

**Files:**
- Modify: `lib/src/application/sync/unified_sync_overview.dart`
- Test: `test/application/sync/unified_sync_overview_grouping_test.dart`

- [ ] **Step 1: Write the failing test**

Add to `test/application/sync/unified_sync_overview_grouping_test.dart` (inside `main()`):

```dart
test('plan rows carry aggregate refs for every grouped mutation', () {
  final overview = computeUnifiedSyncOverview(
    UnifiedSyncOverviewInputs(
      catalog: const CatalogSnapshotState.initial(),
      songEntries: const [],
      planning: const PlanningSyncState.initial(),
      planningEntries: [
        PlanningMutationRecord(
          aggregateId: 'plan-1',
          planId: 'plan-1',
          kind: PlanningMutationKind.planEdit,
          syncStatus: PlanningMutationSyncStatus.pending,
        ),
        PlanningMutationRecord(
          aggregateId: 'session-1',
          planId: 'plan-1',
          kind: PlanningMutationKind.sessionCreate,
          syncStatus: PlanningMutationSyncStatus.pending,
        ),
      ],
    ),
  );

  final row = overview.planRows.single;
  expect(
    row.mutationRefs.map((r) => '${r.aggregateType}:${r.aggregateId}').toSet(),
    {'plan:plan-1', 'session:session-1'},
  );
});
```

(If the existing test file already imports `PlanningMutationRecord`, `PlanningMutationKind`, `PlanningMutationSyncStatus`, `CatalogSnapshotState`, `PlanningSyncState`, reuse those imports; otherwise add them.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/application/sync/unified_sync_overview_grouping_test.dart`
Expected: FAIL — `mutationRefs` getter not defined on `UnifiedSyncPlanRow`.

- [ ] **Step 3: Add the ref type and field**

In `lib/src/application/sync/unified_sync_overview.dart`, add above `class UnifiedSyncPlanRow`:

```dart
class UnifiedSyncPlanMutationRef {
  const UnifiedSyncPlanMutationRef({
    required this.aggregateType,
    required this.aggregateId,
  });

  final String aggregateType;
  final String aggregateId;
}
```

Add the field to `UnifiedSyncPlanRow` (constructor + final):

```dart
class UnifiedSyncPlanRow {
  const UnifiedSyncPlanRow({
    required this.planId,
    required this.title,
    required this.severity,
    required this.reasonCode,
    required this.nestedSummaries,
    this.mutationRefs = const [],
    this.errorMessage,
  });

  final String planId;
  final String title;
  final UnifiedSyncRowSeverity severity;
  final UnifiedSyncReasonCode reasonCode;
  final List<String> nestedSummaries;
  final List<UnifiedSyncPlanMutationRef> mutationRefs;
  final String? errorMessage;
}
```

In `_buildPlanRows`, inside the `grouped.forEach`, build the refs from `groupEntries` and pass them:

```dart
final refs = groupEntries
    .map(
      (e) => UnifiedSyncPlanMutationRef(
        aggregateType: e.kind.aggregateType,
        aggregateId: e.aggregateId,
      ),
    )
    .toList(growable: false);
rows.add(
  UnifiedSyncPlanRow(
    planId: planId,
    title: title,
    severity: severity,
    reasonCode: reason,
    nestedSummaries: nested,
    mutationRefs: refs,
    errorMessage: firstWithMessage.errorMessage,
  ),
);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/application/sync/unified_sync_overview_grouping_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/application/sync/unified_sync_overview.dart test/application/sync/unified_sync_overview_grouping_test.dart
git commit -m "feat(sync): carry plan-group aggregate refs in unified overview"
```

---

## Task 2: Add app strings for discard-all

**Files:**
- Modify: `lib/src/shared/app_strings.dart`

- [ ] **Step 1: Add the strings**

After `unifiedSyncActivitySyncing` (line ~201) in `lib/src/shared/app_strings.dart`:

```dart
static const unifiedSyncDiscardAllAction = 'Discard all';
static const unifiedSyncDiscardAllTitle = 'Discard all local changes?';
static const unifiedSyncDiscardAllMessagePrefix =
    'This permanently discards all local changes for this organization';
static const unifiedSyncDiscardAllConfirmAction = 'Discard all';
static const unifiedSyncPlanRetryAction = 'Try again';
```

(`songKeepMineAction`, `songDiscardMineAction`, `retryAction` already exist and are reused.)

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/src/shared/app_strings.dart`
Expected: No issues.

- [ ] **Step 3: Commit**

```bash
git add lib/src/shared/app_strings.dart
git commit -m "feat(sync): add discard-all app strings"
```

---

## Task 3: Song row recovery actions in popup

Conflict song rows gain Keep mine / Discard mine, wired to `songMutationSyncControllerProvider`.

**Files:**
- Modify: `lib/src/presentation/sync/unified_sync_status_popup.dart`
- Test: `test/presentation/sync/unified_sync_status_popup_test.dart`

- [ ] **Step 1: Write the failing test**

Add to `test/presentation/sync/unified_sync_status_popup_test.dart`. First add a spy controller + override helper near the top of the file:

```dart
class _SpySongSyncController extends SongMutationSyncController {
  _SpySongSyncController()
    : super(
        store: _UnusedSongStore(),
        remoteRepository: _UnusedSongRemote(),
      );
  final List<String> keepMineCalls = [];
  final List<String> discardMineCalls = [];

  @override
  Future<void> keepMine(SongMutationContext context, {required String songId}) async {
    keepMineCalls.add(songId);
  }

  @override
  Future<void> discardMine(SongMutationContext context, {required String songId}) async {
    discardMineCalls.add(songId);
  }
}
```

> Note: `SongMutationSyncController` is a concrete class with required `store`/`remoteRepository`. Provide minimal no-op fakes `_UnusedSongStore`/`_UnusedSongRemote` implementing `SongMutationStore`/`SongMutationRemoteRepository` with `throw UnimplementedError()` bodies (only the overridden `keepMine`/`discardMine` run in this test). If that is heavy, instead make the popup depend on a thin callback provider — see Step 3 note.

Then the test:

```dart
testWidgets('conflict song row Discard mine calls controller', (tester) async {
  final spy = _SpySongSyncController();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        unifiedSyncOverviewProvider.overrideWithValue(
          _overview(
            status: UnifiedSyncHeaderStatus.conflict,
            songs: const [
              UnifiedSyncSongRow(
                songId: 's1',
                title: 'Hymn',
                entityState: SongSyncStatus.conflict,
                severity: UnifiedSyncRowSeverity.conflict,
                reasonCode: UnifiedSyncReasonCode.conflict,
              ),
            ],
          ),
        ),
        songMutationSyncControllerProvider.overrideWithValue(spy),
        activeCatalogContextProvider.overrideWithValue(
          const CatalogContext(userId: 'u1', organizationId: 'o1'),
        ),
      ],
      child: const MaterialApp(home: Scaffold(body: UnifiedSyncStatusPopup())),
    ),
  );
  await tester.tap(find.text(AppStrings.songDiscardMineAction));
  await tester.pump();
  expect(spy.discardMineCalls, ['s1']);
});
```

Confirm the exact `CatalogContext` constructor / class name by reading `lib/src/application/providers.dart` around `activeCatalogContextProvider` (line ~676) and its context type; match field names `userId`/`organizationId`.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/presentation/sync/unified_sync_status_popup_test.dart`
Expected: FAIL — no `Discard mine` button found.

- [ ] **Step 3: Add song row actions**

In `lib/src/presentation/sync/unified_sync_status_popup.dart`, convert `_SongRowTile` to a `ConsumerWidget` and add an action row for conflict severity. Add imports for `flutter_riverpod`, `providers.dart` (for `activeCatalogContextProvider`), and `song_mutation_sync_controller`/types via existing providers:

```dart
class _SongRowTile extends ConsumerWidget {
  const _SongRowTile({required this.row});

  final UnifiedSyncSongRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      key: ValueKey('unified-sync-song-row-${row.songId}'),
      title: Text(row.title),
      subtitle: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          _StateChip(label: _songStateLabel(row.entityState)),
          _ReasonChip(reason: row.reasonCode),
        ],
      ),
      trailing: row.severity == UnifiedSyncRowSeverity.conflict
          ? Wrap(
              spacing: 8,
              children: [
                TextButton(
                  key: ValueKey('unified-sync-song-keep-${row.songId}'),
                  onPressed: () => _keepMine(ref),
                  child: const Text(AppStrings.songKeepMineAction),
                ),
                TextButton(
                  key: ValueKey('unified-sync-song-discard-${row.songId}'),
                  onPressed: () => _discardMine(ref),
                  child: const Text(AppStrings.songDiscardMineAction),
                ),
              ],
            )
          : null,
    );
  }

  SongMutationContext? _context(WidgetRef ref) {
    final c = ref.read(activeCatalogContextProvider);
    if (c == null) return null;
    return SongMutationContext(userId: c.userId, organizationId: c.organizationId);
  }

  Future<void> _keepMine(WidgetRef ref) async {
    final ctx = _context(ref);
    if (ctx == null) return;
    await ref.read(songMutationSyncControllerProvider).keepMine(ctx, songId: row.songId);
    ref.invalidate(songMutationEntriesProvider);
    ref.invalidate(songLibraryListProvider);
  }

  Future<void> _discardMine(WidgetRef ref) async {
    final ctx = _context(ref);
    if (ctx == null) return;
    await ref.read(songMutationSyncControllerProvider).discardMine(ctx, songId: row.songId);
    ref.invalidate(songMutationEntriesProvider);
    ref.invalidate(songLibraryListProvider);
  }

  String _songStateLabel(SongSyncStatus state) { /* unchanged */ }
}
```

Keep `_songStateLabel` body unchanged. Add the required imports: `package:flutter_riverpod/flutter_riverpod.dart`, `lib/src/application/providers.dart` (`activeCatalogContextProvider`, `songMutationSyncControllerProvider`), `lib/src/presentation/song_library/song_library_providers.dart` (`songMutationEntriesProvider`, `songLibraryListProvider`), and `SongMutationContext` from `song_mutation_sync_types.dart`.

> Note: if constructing the real `SongMutationSyncController` in the test is heavy, prefer overriding the existing provider with a subclass as shown; `keepMine`/`discardMine` are overridable instance methods, so a subclass spy works without touching production wiring.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/presentation/sync/unified_sync_status_popup_test.dart`
Expected: PASS (existing popup tests still pass).

- [ ] **Step 5: Commit**

```bash
git add lib/src/presentation/sync/unified_sync_status_popup.dart test/presentation/sync/unified_sync_status_popup_test.dart
git commit -m "feat(sync): add song-row recovery actions to sync popup"
```

---

## Task 4: Plan-group recovery actions in popup

Conflict plan rows gain Keep mine / Discard mine; retryable plan rows gain Try again. Each acts on every mutation in the group.

**Files:**
- Modify: `lib/src/presentation/sync/unified_sync_status_popup.dart`
- Test: `test/presentation/sync/unified_sync_status_popup_test.dart`

- [ ] **Step 1: Write the failing test**

Add a planning spy. `PlanningMutationSyncController` requires several closure deps; build it with no-op closures and override the two methods:

```dart
class _SpyPlanningSyncController extends PlanningMutationSyncController {
  _SpyPlanningSyncController()
    : super(
        mutationStore: _unusedPlanningStore,
        remoteRepository: _unusedPlanningRemote,
        refreshPlanning: _alwaysTrue,
        reconcileAcceptedMutation: _noopReconcile,
        shouldReconcileAcceptedMutation: _alwaysTrueGuard,
      );
  final List<String> discardCalls = [];

  @override
  Future<void> discardMutation(
    ActivePlanningReadContext context, {
    required String aggregateType,
    required String aggregateId,
  }) async {
    discardCalls.add('$aggregateType:$aggregateId');
  }
}
```

Provide the top-level no-op helpers (`_unusedPlanningStore`, `_unusedPlanningRemote`, `_alwaysTrue`, `_noopReconcile`, `_alwaysTrueGuard`) matching the typedefs in `planning_mutation_sync_controller.dart`. Then:

```dart
testWidgets('conflict plan row Discard mine discards every grouped mutation', (tester) async {
  final spy = _SpyPlanningSyncController();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        unifiedSyncOverviewProvider.overrideWithValue(
          _overview(
            status: UnifiedSyncHeaderStatus.conflict,
            plans: const [
              UnifiedSyncPlanRow(
                planId: 'p1',
                title: 'Service',
                severity: UnifiedSyncRowSeverity.conflict,
                reasonCode: UnifiedSyncReasonCode.conflict,
                nestedSummaries: ['plan edited', 'session added'],
                mutationRefs: [
                  UnifiedSyncPlanMutationRef(aggregateType: 'plan', aggregateId: 'p1'),
                  UnifiedSyncPlanMutationRef(aggregateType: 'session', aggregateId: 's1'),
                ],
              ),
            ],
          ),
        ),
        planningMutationSyncControllerProvider.overrideWithValue(spy),
        activePlanningContextProvider.overrideWithValue(
          const ActivePlanningReadContext(userId: 'u1', organizationId: 'o1'),
        ),
      ],
      child: const MaterialApp(home: Scaffold(body: UnifiedSyncStatusPopup())),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('unified-sync-plan-discard-p1')));
  await tester.pump();
  expect(spy.discardCalls, ['plan:p1', 'session:s1']);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/presentation/sync/unified_sync_status_popup_test.dart`
Expected: FAIL — no plan discard button key found.

- [ ] **Step 3: Add plan-group actions**

Convert `_PlanRowTile` to `ConsumerWidget`, add a trailing action cluster keyed by severity:

```dart
class _PlanRowTile extends ConsumerWidget {
  const _PlanRowTile({required this.row});

  final UnifiedSyncPlanRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      key: ValueKey('unified-sync-plan-row-${row.planId}'),
      title: Text(row.title),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ReasonChip(reason: row.reasonCode),
          for (final entry in row.nestedSummaries)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('• $entry', style: Theme.of(context).textTheme.bodySmall),
            ),
        ],
      ),
      trailing: _actions(ref),
    );
  }

  Widget? _actions(WidgetRef ref) {
    switch (row.severity) {
      case UnifiedSyncRowSeverity.conflict:
        return Wrap(
          spacing: 8,
          children: [
            TextButton(
              key: ValueKey('unified-sync-plan-keep-${row.planId}'),
              onPressed: () => _applyToGroup(ref, retry: true),
              child: const Text(AppStrings.songKeepMineAction),
            ),
            TextButton(
              key: ValueKey('unified-sync-plan-discard-${row.planId}'),
              onPressed: () => _applyToGroup(ref, retry: false),
              child: const Text(AppStrings.songDiscardMineAction),
            ),
          ],
        );
      case UnifiedSyncRowSeverity.retryableFailure:
        return TextButton(
          key: ValueKey('unified-sync-plan-retry-${row.planId}'),
          onPressed: () => _applyToGroup(ref, retry: true),
          child: const Text(AppStrings.retryAction),
        );
      case UnifiedSyncRowSeverity.pending:
        return null;
    }
  }

  Future<void> _applyToGroup(WidgetRef ref, {required bool retry}) async {
    final ctx = ref.read(activePlanningContextProvider);
    if (ctx == null) return;
    final controller = ref.read(planningMutationSyncControllerProvider);
    for (final mref in row.mutationRefs) {
      if (retry) {
        await controller.retryMutation(
          ctx,
          aggregateType: mref.aggregateType,
          aggregateId: mref.aggregateId,
        );
      } else {
        await controller.discardMutation(
          ctx,
          aggregateType: mref.aggregateType,
          aggregateId: mref.aggregateId,
        );
      }
    }
    ref.read(planningDataRevisionProvider.notifier).state += 1;
    ref.invalidate(planningMutationEntriesProvider);
    ref.invalidate(planningPlanListProvider);
  }
}
```

Add imports: `activePlanningContextProvider`, `planningMutationSyncControllerProvider` (from `providers.dart`), `planningDataRevisionProvider`, `planningMutationEntriesProvider`, `planningPlanListProvider` (from `planning_providers.dart`), and `ActivePlanningReadContext` (from `planning_local_read_repository.dart`).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/presentation/sync/unified_sync_status_popup_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/presentation/sync/unified_sync_status_popup.dart test/presentation/sync/unified_sync_status_popup_test.dart
git commit -m "feat(sync): add plan-group recovery actions to sync popup"
```

---

## Task 5: Discard-all controller

A small orchestrator: discard active-org song + planning mutations.

**Files:**
- Create: `lib/src/application/sync/unified_discard_controller.dart`
- Test: `test/application/sync/unified_discard_controller_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/application/sync/unified_discard_controller_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/sync/unified_discard_controller.dart';

void main() {
  test('discardAll runs both domain steps with active context', () async {
    final calls = <String>[];
    final controller = UnifiedDiscardController(
      activeContextReader: () =>
          const UnifiedDiscardContext(userId: 'u1', organizationId: 'o1'),
      discardSongs: (ctx) async => calls.add('songs:${ctx.organizationId}'),
      discardPlanning: (ctx) async => calls.add('plans:${ctx.organizationId}'),
    );
    await controller.discardAll();
    expect(calls, ['songs:o1', 'plans:o1']);
  });

  test('discardAll is a no-op when no active context', () async {
    var ran = false;
    final controller = UnifiedDiscardController(
      activeContextReader: () => null,
      discardSongs: (_) async => ran = true,
      discardPlanning: (_) async => ran = true,
    );
    await controller.discardAll();
    expect(ran, isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/application/sync/unified_discard_controller_test.dart`
Expected: FAIL — file/class does not exist.

- [ ] **Step 3: Implement the controller**

Create `lib/src/application/sync/unified_discard_controller.dart`:

```dart
class UnifiedDiscardContext {
  const UnifiedDiscardContext({
    required this.userId,
    required this.organizationId,
  });

  final String userId;
  final String organizationId;
}

typedef UnifiedDiscardContextReader = UnifiedDiscardContext? Function();
typedef UnifiedDiscardStep = Future<void> Function(UnifiedDiscardContext context);

class UnifiedDiscardController {
  UnifiedDiscardController({
    required UnifiedDiscardContextReader activeContextReader,
    required UnifiedDiscardStep discardSongs,
    required UnifiedDiscardStep discardPlanning,
  }) : _activeContextReader = activeContextReader,
       _discardSongs = discardSongs,
       _discardPlanning = discardPlanning;

  final UnifiedDiscardContextReader _activeContextReader;
  final UnifiedDiscardStep _discardSongs;
  final UnifiedDiscardStep _discardPlanning;

  Future<void> discardAll() async {
    final context = _activeContextReader();
    if (context == null) return;
    await _discardSongs(context);
    await _discardPlanning(context);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/application/sync/unified_discard_controller_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/application/sync/unified_discard_controller.dart test/application/sync/unified_discard_controller_test.dart
git commit -m "feat(sync): add unified discard-all controller"
```

---

## Task 6: Wire discard-all provider

**Files:**
- Modify: `lib/src/presentation/sync/unified_sync_providers.dart`
- Test: `test/application/sync/unified_sync_providers_test.dart`

- [ ] **Step 1: Write the failing test**

Add to `test/application/sync/unified_sync_providers_test.dart`:

```dart
test('unifiedDiscardControllerProvider resolves a controller', () {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  expect(
    container.read(unifiedDiscardControllerProvider),
    isA<UnifiedDiscardController>(),
  );
});
```

Ensure imports for `unifiedDiscardControllerProvider` and `UnifiedDiscardController` are present.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/application/sync/unified_sync_providers_test.dart`
Expected: FAIL — provider undefined.

- [ ] **Step 3: Add the provider**

In `lib/src/presentation/sync/unified_sync_providers.dart`, add (import `unified_discard_controller.dart`, `song_library_providers.dart`, and the song/planning controller providers as needed):

```dart
final unifiedDiscardControllerProvider =
    Provider.autoDispose<UnifiedDiscardController>((ref) {
      return UnifiedDiscardController(
        activeContextReader: () {
          final c = ref.read(activeCatalogContextProvider);
          if (c == null) return null;
          return UnifiedDiscardContext(
            userId: c.userId,
            organizationId: c.organizationId,
          );
        },
        discardSongs: (ctx) async {
          final entries =
              await ref.read(songMutationEntriesProvider.future);
          final controller = ref.read(songMutationSyncControllerProvider);
          final songContext = SongMutationContext(
            userId: ctx.userId,
            organizationId: ctx.organizationId,
          );
          for (final entry in entries) {
            await controller.discardMine(songContext, songId: entry.id);
          }
          ref.invalidate(songMutationEntriesProvider);
          ref.invalidate(songLibraryListProvider);
        },
        discardPlanning: (ctx) async {
          final planningContext = ref.read(activePlanningContextProvider);
          if (planningContext == null ||
              planningContext.userId != ctx.userId ||
              planningContext.organizationId != ctx.organizationId) {
            return;
          }
          final entries =
              await ref.read(planningMutationEntriesProvider.future);
          final controller = ref.read(planningMutationSyncControllerProvider);
          for (final entry in entries) {
            await controller.discardMutation(
              planningContext,
              aggregateType: entry.kind.aggregateType,
              aggregateId: entry.aggregateId,
            );
          }
          ref.read(planningDataRevisionProvider.notifier).state += 1;
          ref.invalidate(planningMutationEntriesProvider);
          ref.invalidate(planningPlanListProvider);
        },
      );
    });
```

Add imports: `SongMutationContext` (song_mutation_sync_types), `songMutationEntriesProvider` + `songLibraryListProvider` (song_library_providers), `planningMutationEntriesProvider` + `planningPlanListProvider` (planning_providers — already imported), `planningDataRevisionProvider`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/application/sync/unified_sync_providers_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/presentation/sync/unified_sync_providers.dart test/application/sync/unified_sync_providers_test.dart
git commit -m "feat(sync): wire unified discard-all provider"
```

---

## Task 7: Global Discard-all button + confirmation in popup

**Files:**
- Modify: `lib/src/presentation/sync/unified_sync_status_popup.dart`
- Test: `test/presentation/sync/unified_sync_status_popup_test.dart`

- [ ] **Step 1: Write the failing test**

Add a discard spy and test:

```dart
class _SpyDiscardController extends UnifiedDiscardController {
  _SpyDiscardController()
    : super(
        activeContextReader: () => null,
        discardSongs: (_) async {},
        discardPlanning: (_) async {},
      );
  int discardAllCalls = 0;

  @override
  Future<void> discardAll() async {
    discardAllCalls += 1;
  }
}

testWidgets('Discard all confirms then calls controller', (tester) async {
  final spy = _SpyDiscardController();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        unifiedSyncOverviewProvider.overrideWithValue(
          _overview(
            status: UnifiedSyncHeaderStatus.unsynced,
            songs: const [
              UnifiedSyncSongRow(
                songId: 's1',
                title: 'Hymn',
                entityState: SongSyncStatus.pendingCreate,
                severity: UnifiedSyncRowSeverity.pending,
                reasonCode: UnifiedSyncReasonCode.pendingLocal,
              ),
            ],
          ),
        ),
        unifiedDiscardControllerProvider.overrideWithValue(spy),
      ],
      child: const MaterialApp(home: Scaffold(body: UnifiedSyncStatusPopup())),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('unified-sync-popup-discard-all')));
  await tester.pumpAndSettle();
  // Confirmation dialog appears; confirm it.
  await tester.tap(find.text(AppStrings.unifiedSyncDiscardAllConfirmAction));
  await tester.pumpAndSettle();
  expect(spy.discardAllCalls, 1);
});

testWidgets('Discard all is absent when nothing to sync', (tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [unifiedSyncOverviewProvider.overrideWithValue(_overview())],
      child: const MaterialApp(home: Scaffold(body: UnifiedSyncStatusPopup())),
    ),
  );
  expect(find.byKey(const ValueKey('unified-sync-popup-discard-all')), findsNothing);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/presentation/sync/unified_sync_status_popup_test.dart`
Expected: FAIL — discard-all key not found.

- [ ] **Step 3: Add the button + confirmation**

In `UnifiedSyncStatusPopup.build`, in the title `Row`, add a discard-all button before `Sync now`, shown only when `overview.hasUnsyncedWork`:

```dart
Row(
  children: [
    Expanded(
      child: Text(
        AppStrings.unifiedSyncPopupTitle,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    ),
    if (overview.hasUnsyncedWork)
      TextButton(
        key: const ValueKey('unified-sync-popup-discard-all'),
        style: TextButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.error,
        ),
        onPressed: () => _confirmDiscardAll(context, ref, overview),
        child: const Text(AppStrings.unifiedSyncDiscardAllAction),
      ),
    const SizedBox(width: 8),
    FilledButton.icon(
      key: const ValueKey('unified-sync-popup-sync-now'),
      onPressed: () {
        unawaited(ref.read(unifiedManualSyncControllerProvider).syncNow());
      },
      icon: const Icon(Icons.sync),
      label: const Text(AppStrings.unifiedSyncNowAction),
    ),
  ],
),
```

Add the confirmation method to `UnifiedSyncStatusPopup`:

```dart
Future<void> _confirmDiscardAll(
  BuildContext context,
  WidgetRef ref,
  UnifiedSyncOverview overview,
) async {
  final songCount = overview.songRows.length;
  final planCount = overview.planRows.length;
  final message =
      '${AppStrings.unifiedSyncDiscardAllMessagePrefix} '
      '($songCount songs, $planCount plans). This cannot be undone.';
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text(AppStrings.unifiedSyncDiscardAllTitle),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text(AppStrings.songCancelAction),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(dialogContext).colorScheme.error,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text(AppStrings.unifiedSyncDiscardAllConfirmAction),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  await ref.read(unifiedDiscardControllerProvider).discardAll();
}
```

Confirm `AppStrings.songCancelAction` exists (it is used elsewhere in the song list). Add the `unifiedDiscardControllerProvider` import.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/presentation/sync/unified_sync_status_popup_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/presentation/sync/unified_sync_status_popup.dart test/presentation/sync/unified_sync_status_popup_test.dart
git commit -m "feat(sync): add global discard-all action to sync popup"
```

---

## Task 8: Remove the song-library browse filter

**Files:**
- Modify: `lib/src/presentation/song_library/song_library_browse_state.dart`
- Modify: `lib/src/presentation/song_library/song_library_browse_controller.dart`
- Modify: `lib/src/presentation/song_library/song_library_browse_row.dart`
- Modify: `lib/src/presentation/song_library/song_library_providers.dart`
- Test: `test/presentation/song_library/song_library_browse_controller_test.dart`

- [ ] **Step 1: Update the browse-row test to drop filter**

In `test/presentation/song_library/song_library_browse_controller_test.dart` (and any browse-row test that references `SongLibraryBrowseFilter`, `setFilter`, `matchesFilter`, or `filter:`), delete those cases/assertions. Keep query + sort cases. Update calls to `filterSongLibraryBrowseRows` to drop the `filter:` argument and calls to `buildSongLibraryBrowseRows` to drop `mutationEntries:`.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/presentation/song_library/song_library_browse_controller_test.dart`
Expected: FAIL to compile — symbols still reference removed API (this confirms the test now expects the new API).

- [ ] **Step 3: Remove the filter from production code**

`song_library_browse_state.dart`: delete `enum SongLibraryBrowseFilter`; remove the `filter` field, its constructor default, `copyWith` param, and its participation in `==`/`hashCode`.

`song_library_browse_controller.dart`: delete `setFilter`.

`song_library_browse_row.dart`:
- delete `mutationRecord` field and `matchesFilter` and `_pendingStatuses`;
- `buildSongLibraryBrowseRows`: drop `mutationEntries` param and the `mutationBySongId` map; build rows as `songs.map((song) => SongLibraryBrowseRow(song: song))`;
- `filterSongLibraryBrowseRows`: drop the `filter` param and the `row.matchesFilter(filter)` check (keep query + sort);
- remove the now-unused import of `song_mutation_sync_types.dart`.

`song_library_providers.dart` (`songLibraryBrowseRowsProvider`): stop watching `songMutationEntriesProvider`; call `buildSongLibraryBrowseRows(songs: songs)` and `filterSongLibraryBrowseRows(rows: rows, query: browseState.query, sort: browseState.sort)`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/presentation/song_library/song_library_browse_controller_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/presentation/song_library/ test/presentation/song_library/song_library_browse_controller_test.dart
git commit -m "refactor(song-library): remove pending/conflict browse filter"
```

---

## Task 9: Remove song-list sync surfaces

**Files:**
- Modify: `lib/src/presentation/song_library/song_list_screen.dart`
- Test: `test/presentation/song_library/song_list_screen_test.dart`

- [ ] **Step 1: Add a guard test for the removed surfaces**

In `test/presentation/song_library/song_list_screen_test.dart`, add (and delete any existing tests that assert the filter control / mutation cards exist):

```dart
testWidgets('song list shows no segmented filter control', (tester) async {
  // Pump the screen with the standard test harness used elsewhere in this file.
  // ... existing setup ...
  expect(find.byKey(const ValueKey('song-list-filter-control')), findsNothing);
});
```

Match the existing harness/setup style already present in this test file.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/presentation/song_library/song_list_screen_test.dart`
Expected: FAIL — filter control still present.

- [ ] **Step 3: Delete the surfaces**

In `song_list_screen.dart`:
- delete the `_CatalogStatusSurface` widget class and its build-site (`_CatalogStatusSurface(state: catalogState)`);
- delete the `_MutationStatusSurface` widget class and the `mutationEntriesAsync.when(...)` block that renders it;
- delete the `SegmentedButton` `Padding` block (the `song-list-filter-control`);
- delete the `mutationStatusMessage` computation and the `if (mutationStatusMessage != null)` padding block;
- delete the `mutationRowsReady` gating branch (lines computing `mutationEntries`/`mutationRowsReady` and the early returns for `_RetryableErrorState`/loading tied to mutation entries);
- delete state `_cachedMutationEntries`, `_cachedMutationEntriesOrganizationId`, `_resolveMutationEntries`, and the `ref.listen(songMutationEntriesProvider, ...)` and `ref.listen(catalogSnapshotStateProvider...)`-driven cache resets that exist only for mutation caching;
- remove now-unused imports (`catalog_connection_status.dart` only if no longer referenced — note `CatalogConnectionStatus.unavailable` is still used in the unavailable-catalog branch, so keep it; remove `song_mutation_sync_types.dart`, `song_library_browse_state.dart` filter usages, `catalog_refresh_status.dart` only if unused).

Keep: search field, the catalog-unavailable empty state, the results list, `_signOut` (which still reads `unifiedSyncOverviewProvider`).

After edits, run analyze to catch unused imports:

Run: `flutter analyze lib/src/presentation/song_library/song_list_screen.dart`
Expected: No issues. Remove any flagged unused imports.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/presentation/song_library/song_list_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/presentation/song_library/song_list_screen.dart test/presentation/song_library/song_list_screen_test.dart
git commit -m "refactor(song-list): remove catalog banner and mutation status surfaces"
```

---

## Task 10: Remove planning status surface

**Files:**
- Delete: `lib/src/presentation/planning/widgets/planning_workspace_status_surface.dart`
- Modify: `lib/src/presentation/planning/plan_list_screen.dart`
- Modify: `lib/src/presentation/planning/plan_detail_screen.dart`
- Modify: `lib/src/presentation/planning/widgets/planning_workspace_shell.dart`
- Test: `test/presentation/planning/plan_list_screen_test.dart`, `test/presentation/planning/plan_detail_screen_test.dart`

- [ ] **Step 1: Update planning screen tests**

In `plan_list_screen_test.dart` and `plan_detail_screen_test.dart`, delete tests asserting the status surface / its retry/keep/discard buttons exist. If a test needs a removed-surface guard, add e.g.:

```dart
testWidgets('plan list renders without a status surface', (tester) async {
  // ... existing harness ...
  expect(find.byType(PlanningWorkspaceStatusSurface), findsNothing);
});
```

…but since the type is being deleted, prefer simply removing surface-specific assertions and keeping the screen-renders smoke test.

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/presentation/planning/plan_list_screen_test.dart test/presentation/planning/plan_detail_screen_test.dart`
Expected: FAIL (references to surface / its buttons).

- [ ] **Step 3: Remove the surface**

- Delete file `lib/src/presentation/planning/widgets/planning_workspace_status_surface.dart`.
- `planning_workspace_shell.dart`: remove the `statusSurface` field, constructor param, and the `if (statusSurface != null) ...` block.
- `plan_list_screen.dart`: remove the `statusSurface:` argument and the `_retryMutation` / `_keepMine` / `_discardMine` methods (now unwired); remove the `planningMutationEntriesProvider` watch if only the surface used it; remove unused imports (`planning_workspace_status_surface.dart`, `planning_mutation_sync_types.dart` if unused, `planning_data_revision.dart` if unused).
- `plan_detail_screen.dart`: remove the `statusSurface:` argument and the `_retryMutation`/`_keepMine`/`_discardMine` methods; keep the `mutationsAsync`/`planningMutationEntriesProvider` watch only if still used elsewhere — otherwise remove it; remove unused imports.

Run analyze on both screens and the shell:

Run: `flutter analyze lib/src/presentation/planning/`
Expected: No issues. Remove flagged unused imports/fields.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/presentation/planning/plan_list_screen_test.dart test/presentation/planning/plan_detail_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/presentation/planning/ test/presentation/planning/
git commit -m "refactor(planning): remove per-screen mutation status surface"
```

---

## Task 11: Update documentation

**Files:**
- Modify: `docs/product/sync-ux-contract.md`
- Modify: `docs/specs/2026-05-15-pending-changes-cleanup.md`
- Modify: `docs/specs/2026-05-29-sync-ui-consolidation.md`

- [ ] **Step 1: Update the sync UX contract**

In `docs/product/sync-ux-contract.md`:
- In "Header Status Popup", state explicitly that the popup hosts recovery actions: song rows expose Keep mine / Discard mine for conflicts; plan rows expose group-level Retry (retryable) and Keep mine / Discard mine (conflict) applied to all mutations in the plan; the popup header exposes `Sync now` and a destructive `Discard all` action scoped to the active organization, behind a confirmation.
- Replace the "Inline Status Responsibility" section: screen-level status surfaces (catalog banner, song mutation cards, planning status surface) and the pending/conflict browse filter have been removed; the header control answers "is this workspace synced?" and the popup answers "what is not synced and how do I fix it?" — the popup is the single recovery surface.

- [ ] **Step 2: Mark the predecessor spec superseded**

In `docs/specs/2026-05-15-pending-changes-cleanup.md`, add a note under the header that `PlanningWorkspaceStatusSurface` (retained as the action home by that spec) is superseded and removed by `2026-05-29-sync-ui-consolidation.md`, which relocates recovery into the unified popup.

- [ ] **Step 3: Flip spec status to Approved**

In `docs/specs/2026-05-29-sync-ui-consolidation.md`, change `**Status:** Draft` to `**Status:** Approved`.

- [ ] **Step 4: Commit**

```bash
git add docs/
git commit -m "docs(sync): document popup recovery + discard-all, retire inline surfaces"
```

---

## Task 12: Full verification

- [ ] **Step 1: Run the full app test suite**

Run: `flutter test`
Expected: All pass.

- [ ] **Step 2: Analyze the whole package**

Run: `flutter analyze`
Expected: No issues.

- [ ] **Step 3: Manual smoke (optional but recommended)**

Launch the app, create a local song edit and a plan edit offline, open the header popup, verify: per-row recovery buttons appear for conflicts, plan-group recovery acts on the group, and `Discard all` shows a confirmation with counts and clears local work on confirm. Confirm the song list no longer shows the filter/banners and plan screens no longer show the status surface.

---

## Self-Review Notes

- **Spec coverage:** Task 3 (song recovery), Task 4 (plan-group recovery), Tasks 5–7 (global discard), Tasks 8–10 (surface + filter removal), Task 11 (docs) cover all four spec decisions. Task 1 enables plan-group recovery (data model change). 
- **Type consistency:** `UnifiedSyncPlanMutationRef{aggregateType, aggregateId}`, `UnifiedDiscardContext{userId, organizationId}`, controller method names (`keepMine`/`discardMine`/`retryMutation`/`discardMutation`/`discardAll`) match across tasks.
- **Known assumptions to verify during execution:** exact `CatalogContext` class name/fields behind `activeCatalogContextProvider` (Task 3); the minimal fakes needed to subclass `SongMutationSyncController`/`PlanningMutationSyncController` in popup tests (Tasks 3–4) — if the no-op fakes are heavy, the simpler path is the subclass-spy override shown.
