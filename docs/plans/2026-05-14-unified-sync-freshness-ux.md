# Unified Sync And Freshness UX Implementation Plan

> Status: In progress

> **For agentic workers:** Implements Slice 2 of docs/specs/2026-05-09-online-preferred-local-first-sync-contract.md. TDD discipline applies. Each step is one action; mark each checkbox as it completes. Authorization stays backend-enforced; sync activity, connectivity, and freshness remain separate dimensions.

**Goal:** Deliver one application-level sync overview, one unified manual sync command for active-organization song and planning work, foreground/resume refresh, an offline-to-online transition trigger, and one header sync control with status popup across authenticated non-reader workspaces.

**Assumptions:**
- Slice 1 (sync contract + ADR-015 + SyncOverview scaffold) is merged; this plan only adds behavior on top of the existing controllers and stores.
- `SongCatalogController`, `SongMutationSyncController`, `PlanningSyncController`, and `PlanningMutationSyncController` remain the canonical refresh/sync execution paths. The unified command orchestrates them; it does not replace them.
- No new connectivity plugin is added. Offline-to-online transitions are derived from the catalog connection status flipping out of `offlineCached`/`unavailable`.
- Sign-out warning logic already lives in `SongListScreen._signOut`; the unified provider replaces the two ad-hoc reads with one aggregate.
- Reader surfaces (song reader, session-scoped reader) intentionally do not host the header sync control.

**Architecture decisions:**
- Add an application-level `UnifiedSyncOverview` view-model owned by a single `unifiedSyncOverviewProvider` that aggregates song catalog refresh state, song mutation entries, planning sync state, and planning mutation entries into one immutable snapshot.
- Add a `UnifiedManualSyncController` that, for the active authenticated organization, sequences: song mutation sync → song catalog refresh → planning mutation sync → planning refresh. It exposes `syncNow()` with single-flight semantics and an optional queued re-run when a request arrives mid-flight. The controller only orchestrates calls to existing controllers; it does not hold or recompute authorization, capability, OCC, or conflict classification — those stay backend-enforced via the underlying refresh/sync paths.
- Add an `OnlineTransitionDetector` provider that observes `CatalogConnectionStatus` and `PlanningSyncState.connectivity` transitions; when transitioning from offline/unknown to online with pending local work, it calls `UnifiedManualSyncController.syncNow()` without forcing a full reload when no pending work exists.
- Hook the existing `AppForegroundState` stream into a foreground refresh listener provider that triggers `syncNow()` (refresh-only side effects) on resume when an authenticated active organization exists.
- Header status is computed inside `UnifiedSyncOverview` using the spec's precedence: red > yellow > green. Freshness/connectivity render as secondary text/iconography only; per the spec, they must not change the primary header color in this slice.
- The aggregator inspects BOTH entity-state enums (`CreatedConflict`, `EditedConflict`, `RemovedConflict`, `ReorderConflict`) and sync-metadata reason codes (`authorization_denied`, `dependency_blocked`, `remote_missing`, plus any other non-retryable rejection). Either one independently elevates a row to red. Spec vocabulary terms (`fresh`, `stale`, `offline_cached`, `pending_local`, `syncing`, `sync_failed`, `conflict`, `authorization_denied`, `dependency_blocked`, `remote_missing`) are mapped to Dart enum values with the standard camelCase rendering (`offlineCached`, `pendingLocal`, etc.); UI copy and serialization stay aligned with the spec's underscore labels.
- "Reader surfaces" in the spec covers both the song reader and the session-scoped reader; neither mounts the header sync control. This plan treats that as the spec's intent because the session-scoped reader is still a reading surface; sync continues in the background through providers, not in the header.
- The header sync control is a single widget `UnifiedSyncHeaderControl` rendered inside an `AuthenticatedWorkspaceHeader` wrapper. Song library, song editor, plan list, and plan detail screens mount the wrapper; reader surfaces never mount it.
- The header popup is a route-level dialog/sheet `UnifiedSyncStatusPopup` that lists only non-synced rows: song rows by title + state; planning rows grouped by plan with nested mutation summary. Failed plan creates appear as their own plan-level rows; orphan session/session-item mutations group under a recoverable plan-level fallback row.

**Tech Stack:** Flutter, Riverpod, Drift, existing application controllers; tests use `flutter_test`, `fake_async`, ProviderScope overrides per testing-strategy rules.

---

### Task 1: Aggregate sync overview view-model

**Files:**
- Create: `apps/lyron_app/lib/src/application/sync/unified_sync_overview.dart`
- Test: `apps/lyron_app/test/application/sync/unified_sync_overview_test.dart`

- [ ] **Step 1: Write the failing aggregator test**

Test plain function `computeUnifiedSyncOverview` against a matrix of inputs: no pending work → green; one pending song create → yellow; one planning conflict → red; mixed yellow+red → red; offline cached with no pending → green with offline freshness flag; refreshing while clean → green with syncing activity flag; authorization denied on planning row → red.

Run:
```bash
cd apps/lyron_app && flutter test test/application/sync/unified_sync_overview_test.dart
```
Expected: FAIL (file missing).

- [ ] **Step 2: Implement `UnifiedSyncOverview` and `computeUnifiedSyncOverview`**

Create the value type:

```dart
enum UnifiedSyncHeaderStatus { synced, unsynced, conflict }
enum UnifiedSyncActivity { idle, syncing }
enum UnifiedSyncConnectivity { online, offline, unknown }
enum UnifiedSyncFreshness { fresh, stale, offlineCached, unknown }

class UnifiedSyncOverview {
  const UnifiedSyncOverview({
    required this.headerStatus,
    required this.activity,
    required this.connectivity,
    required this.freshness,
    required this.songRows,
    required this.planRows,
    required this.hasUnsyncedWork,
  });
  // ... fields, copyWith, == /hashCode
}

class UnifiedSyncSongRow { /* id, title, state label, retryable, errorCode */ }
class UnifiedSyncPlanRow { /* planId, title, nested mutation summaries, blockingReason */ }
```

`computeUnifiedSyncOverview` takes `CatalogSnapshotState`, `List<SongMutationRecord>`, `PlanningSyncState`, `List<PlanningMutationRecord>` and returns the immutable overview. Precedence rule:
1. Any row whose entity state is `CreatedConflict`/`EditedConflict`/`RemovedConflict`/`ReorderConflict` OR whose sync-metadata error code is `authorization_denied`/`dependency_blocked`/`remote_missing`/any other non-retryable rejection → header `conflict` (red).
2. Otherwise, any row with `Created`/`Edited`/`Removed`/`Reordered` entity state, or with a retryable sync_failed metadata code (connectivity, timeout, transient backend) → header `unsynced` (yellow).
3. Otherwise → header `synced` (green).
Activity reflects whether any underlying refresh/sync is in-flight; connectivity and freshness map from `CatalogConnectionStatus` and `CatalogRefreshStatus`. The row reason code retains the exact taxonomy (`conflict`, `authorization_denied`, `dependency_blocked`, `remote_missing`, …) so the popup can render the specific blocking reason rather than collapsing to a generic message.

Run:
```bash
cd apps/lyron_app && flutter test test/application/sync/unified_sync_overview_test.dart
```
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add apps/lyron_app/lib/src/application/sync/unified_sync_overview.dart \
        apps/lyron_app/test/application/sync/unified_sync_overview_test.dart
git commit -m "feat(sync): add unified sync overview model"
```

### Task 2: Plan-grouped popup row grouping

**Files:**
- Modify: `apps/lyron_app/lib/src/application/sync/unified_sync_overview.dart`
- Test: `apps/lyron_app/test/application/sync/unified_sync_overview_grouping_test.dart`

- [ ] **Step 1: Write the failing grouping test**

Cases:
1. plan create + session create under same plan → one plan row, nested "plan added", "session added".
2. failed plan create → standalone plan row with title from `name` / `slug` / `aggregateId` fallback chain.
3. session item add whose parent plan has no mutation → grouped under a `_unknown` recoverable fallback row keyed by `planId`.
4. plan row uses merged plan title from passed `Map<String, String>` planTitles when available.

Run:
```bash
cd apps/lyron_app && flutter test test/application/sync/unified_sync_overview_grouping_test.dart
```
Expected: FAIL.

- [ ] **Step 2: Implement grouping helper**

Extend `computeUnifiedSyncOverview` to accept `Map<String, String> planTitles` and group planning mutations by `planId ?? aggregateId` for plan_create rows. Title precedence: `planTitles[planId]` → `mutation.name` (set on plan_create / plan_edit drafts) → `mutation.slug` → `originSnapshot['name'] as String?` (the `PlanningMutationRecord.originSnapshot` map already carries the pre-edit plan name when present) → `aggregateId` fallback. Build nested entries describing intent (`plan edited`, `session added`, `session removed`, `session order changed`, `song added`, `song removed`, `song order changed`).

Run the test; expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add apps/lyron_app/lib/src/application/sync/unified_sync_overview.dart \
        apps/lyron_app/test/application/sync/unified_sync_overview_grouping_test.dart
git commit -m "feat(sync): group planning mutations into plan-level popup rows"
```

### Task 3: Unified manual sync controller

**Files:**
- Create: `apps/lyron_app/lib/src/application/sync/unified_manual_sync_controller.dart`
- Test: `apps/lyron_app/test/application/sync/unified_manual_sync_controller_test.dart`

- [ ] **Step 1: Write the failing controller test**

Inject fake `SongMutationSyncController`, fake `SongCatalogController`, fake `PlanningMutationSyncController`, fake `PlanningSyncController`. Assert:
1. `syncNow()` calls song mutation sync → catalog refresh → planning mutation sync → planning refresh, in order, with the active organization id.
2. Concurrent `syncNow()` calls share the in-flight future and run exactly one additional pass when requested mid-flight (queued).
3. Refresh failure in catalog refresh does not skip planning sync.
4. Planning sync failure preserves the prior planning projection (the controller does not throw; failures are reported via state).

Run:
```bash
cd apps/lyron_app && flutter test test/application/sync/unified_manual_sync_controller_test.dart
```
Expected: FAIL.

- [ ] **Step 2: Implement controller**

```dart
class UnifiedManualSyncController extends ChangeNotifier {
  UnifiedManualSyncController({ required this.songMutationSync, required this.songCatalog, required this.planningMutationSync, required this.planningSync, required this.activeOrganizationReader });

  bool _running = false;
  bool _queued = false;
  Future<void>? _inFlight;

  Future<void> syncNow() { /* single-flight + queue, runs all four steps inside try/finally */ }
}
```

Each step swallows step-local exceptions and records them in fields exposed for UI surfacing; the controller never throws to the caller.

Run the test; expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add apps/lyron_app/lib/src/application/sync/unified_manual_sync_controller.dart \
        apps/lyron_app/test/application/sync/unified_manual_sync_controller_test.dart
git commit -m "feat(sync): add unified manual sync controller"
```

### Task 4: Riverpod wiring for overview + controller

**Files:**
- Modify: `apps/lyron_app/lib/src/application/providers.dart`
- Test: `apps/lyron_app/test/application/sync/unified_sync_providers_test.dart`

- [ ] **Step 1: Write provider wiring test**

Build a `ProviderContainer` with overrides for catalog state, song mutation entries, planning sync state, planning mutation entries; read `unifiedSyncOverviewProvider` and `unifiedManualSyncControllerProvider`; assert overview matches expected aggregation and controller is non-null.

Run:
```bash
cd apps/lyron_app && flutter test test/application/sync/unified_sync_providers_test.dart
```
Expected: FAIL.

- [ ] **Step 2: Add providers**

Append to `providers.dart`:

```dart
final unifiedSyncOverviewProvider = Provider<UnifiedSyncOverview>((ref) {
  final catalog = ref.watch(catalogSnapshotStateProvider);
  final songEntries = ref.watch(songMutationEntriesProvider).valueOrNull ?? const [];
  final planningSync = ref.watch(planningSyncStateProvider);
  final planningEntries = ref.watch(planningMutationEntriesProvider).valueOrNull ?? const [];
  final planTitles = ref.watch(planningPlanTitlesProvider).valueOrNull ?? const {};
  return computeUnifiedSyncOverview(
    catalog: catalog,
    songEntries: songEntries,
    planning: planningSync,
    planningEntries: planningEntries,
    planTitles: planTitles,
  );
});

final unifiedManualSyncControllerProvider =
    ChangeNotifierProvider<UnifiedManualSyncController>((ref) { /* wire from existing controllers */ });
```

Add `planningPlanTitlesProvider` (returning `AsyncValue<Map<String,String>>`) that watches `planningPlanListProvider` and maps each `PlanSummary.id → PlanSummary.name`. The grouping helper from Task 2 reads from the resolved map; when the map is loading or empty, it falls back to mutation name → slug → origin snapshot title → aggregateId.

Run the test; expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add apps/lyron_app/lib/src/application/providers.dart \
        apps/lyron_app/test/application/sync/unified_sync_providers_test.dart
git commit -m "feat(sync): wire unified sync providers"
```

### Task 5: Offline-to-online transition trigger

**Files:**
- Create: `apps/lyron_app/lib/src/application/sync/online_transition_detector.dart`
- Test: `apps/lyron_app/test/application/sync/online_transition_detector_test.dart`
- Modify: `apps/lyron_app/lib/src/application/providers.dart`

- [ ] **Step 1: Write failing detector test**

Drive a `OnlineTransitionDetector` with synthetic catalog/planning state changes. Assert it triggers `onTransitionToOnline` exactly once when:
- catalog status flips `offlineCached` → `online`, OR
- planning connectivity flips offline → online.

Assert no trigger fires when no pending work exists AND `triggerWhenClean=false`. Assert duplicate online events are debounced.

Run:
```bash
cd apps/lyron_app && flutter test test/application/sync/online_transition_detector_test.dart
```
Expected: FAIL.

- [ ] **Step 2: Implement detector**

`OnlineTransitionDetector` accepts callbacks/streams for the two states and a synchronous getter for "has unsynced work". It is a plain class with `update(catalog, planning)` and emits an `onTransitionToOnline` callback. No Flutter dependency.

Run test; expected: PASS.

- [ ] **Step 3: Wire detector into providers**

Add `onlineTransitionDetectorProvider` that listens to `catalogSnapshotStateProvider` and `planningSyncStateProvider`, hands transitions to `UnifiedManualSyncController.syncNow()`.

Run:
```bash
cd apps/lyron_app && flutter test test/application/sync/unified_sync_providers_test.dart
```
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add apps/lyron_app/lib/src/application/sync/online_transition_detector.dart \
        apps/lyron_app/test/application/sync/online_transition_detector_test.dart \
        apps/lyron_app/lib/src/application/providers.dart
git commit -m "feat(sync): trigger unified sync on offline-to-online transition"
```

### Task 6: Foreground/resume refresh trigger

**Files:**
- Create: `apps/lyron_app/lib/src/application/sync/foreground_sync_listener.dart`
- Test: `apps/lyron_app/test/application/sync/foreground_sync_listener_test.dart`
- Modify: `apps/lyron_app/lib/src/application/providers.dart`

- [ ] **Step 1: Write failing test**

Drive a stream emitting `false → true` (background → foreground) and assert the listener calls `syncNow()` exactly once per transition to foreground when an authenticated organization exists, and skips when signed-out.

Run:
```bash
cd apps/lyron_app && flutter test test/application/sync/foreground_sync_listener_test.dart
```
Expected: FAIL.

- [ ] **Step 2: Implement listener**

`ForegroundSyncListener` subscribes to `AppForegroundState.watchForeground()`, debounces back-to-foreground events, and calls a `Future<void> Function()` `onResume`. Disposable.

Run test; expected: PASS.

- [ ] **Step 3: Wire provider**

Add `foregroundSyncListenerProvider` that calls `unifiedManualSyncControllerProvider.syncNow()` on resume and watches `appAuthControllerProvider` to gate signed-out state.

- [ ] **Step 4: Commit**

```bash
git add apps/lyron_app/lib/src/application/sync/foreground_sync_listener.dart \
        apps/lyron_app/test/application/sync/foreground_sync_listener_test.dart \
        apps/lyron_app/lib/src/application/providers.dart
git commit -m "feat(sync): refresh on app foreground resume"
```

### Task 7: Header sync control widget

**Files:**
- Create: `apps/lyron_app/lib/src/presentation/sync/unified_sync_header_control.dart`
- Create: `apps/lyron_app/lib/src/presentation/sync/unified_sync_status_popup.dart`
- Modify: `apps/lyron_app/lib/src/shared/app_strings.dart` (add `unifiedSyncSyncedLabel`, `unifiedSyncUnsyncedLabel`, `unifiedSyncConflictLabel`, `unifiedSyncNowAction`, `unifiedSyncPopupTitle`, `unifiedSyncOfflineSecondary`, `unifiedSyncStaleSecondary`, `unifiedSyncFreshSecondary`, per-state row labels per spec.)
- Test: `apps/lyron_app/test/presentation/sync/unified_sync_header_control_test.dart`
- Test: `apps/lyron_app/test/presentation/sync/unified_sync_status_popup_test.dart`

- [ ] **Step 1: Write header control widget test**

Three pumps with overridden `unifiedSyncOverviewProvider`:
- synced → label `Synced`, green semantic color.
- unsynced → label `Unsynced`, yellow.
- conflict → label `Conflict`, red.
Tapping the control opens `UnifiedSyncStatusPopup` (use `find.byType`).

Run:
```bash
cd apps/lyron_app && flutter test test/presentation/sync/unified_sync_header_control_test.dart
```
Expected: FAIL.

- [ ] **Step 2: Implement header control**

`UnifiedSyncHeaderControl` is a `ConsumerWidget` rendering a colored badge + label + secondary connectivity/freshness icon, wrapped in an `InkWell` that opens the popup. No authorization logic.

Run test; expected: PASS.

- [ ] **Step 3: Write popup test**

Cases:
- synced overview → popup shows empty-state copy, no rows listed.
- one song create + one plan conflict → popup shows song row (title, `Created`), plan row (red, `Conflict` reason chip), and a `Sync now` button.
- planning row with authorization_denied → `authorization_denied` reason chip visible, retry hidden, recovery actions visible.
- planning row with dependency_blocked → row visible, `dependency_blocked` reason chip visible.
- planning row with remote_missing → row visible, `remote_missing` reason chip visible, recovery actions present.
- song row with retryable sync_failed (connectivity) → yellow `Unsynced` row with retry action visible; reason chip shows `sync_failed`/connectivity copy. Header status stays yellow, not red.

Run:
```bash
cd apps/lyron_app && flutter test test/presentation/sync/unified_sync_status_popup_test.dart
```
Expected: FAIL.

- [ ] **Step 4: Implement popup**

`UnifiedSyncStatusPopup` is a `ConsumerWidget` rendered via `showDialog` returning a `Dialog`. Shows: header counts, `Sync now` triggering `unifiedManualSyncControllerProvider.syncNow()`, song rows (title + state chip + retry where retryable), plan rows (title + reason chip + nested mutation list + per-row recovery actions). Synced rows are omitted.

Run popup test; expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/lyron_app/lib/src/presentation/sync/unified_sync_header_control.dart \
        apps/lyron_app/lib/src/presentation/sync/unified_sync_status_popup.dart \
        apps/lyron_app/lib/src/shared/app_strings.dart \
        apps/lyron_app/test/presentation/sync/unified_sync_header_control_test.dart \
        apps/lyron_app/test/presentation/sync/unified_sync_status_popup_test.dart
git commit -m "feat(sync): add header sync control and status popup"
```

### Task 8: Wire header into non-reader authenticated surfaces

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_library/song_list_screen.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_editor/song_editor_screen.dart`
- Modify: `apps/lyron_app/lib/src/presentation/planning/plan_list_screen.dart`
- Modify: `apps/lyron_app/lib/src/presentation/planning/plan_detail_screen.dart`
- Modify: `apps/lyron_app/lib/src/presentation/planning/widgets/planning_workspace_shell.dart` (accept optional `headerSyncControl` slot)
- Test: `apps/lyron_app/test/presentation/sync/header_visibility_test.dart`

- [ ] **Step 1: Write header visibility test**

Pump each non-reader surface (`SongListScreen`, `SongEditorScreen`, `PlanListScreen`, `PlanDetailScreen`) inside a ProviderScope with a signed-in active organization and assert `find.byType(UnifiedSyncHeaderControl)` returns exactly one widget. Pump `SongReaderScreen` and the session-scoped reader and assert the control is absent.

Run:
```bash
cd apps/lyron_app && flutter test test/presentation/sync/header_visibility_test.dart
```
Expected: FAIL.

- [ ] **Step 2: Mount the control on song library**

In `song_list_screen.dart`, replace the existing top `IconButton(Icons.sync)` action with `UnifiedSyncHeaderControl` rendered in the `AppBar.actions` slot. Delete the now-unused `_syncNow`/`_runQueuedSync` private helpers and route the previous in-screen logic through `unifiedManualSyncControllerProvider`. Keep `_CatalogStatusSurface` and `_MutationStatusSurface` (inline badges remain per spec).

- [ ] **Step 3: Mount the control on song editor**

Add `UnifiedSyncHeaderControl` to the song editor app bar `actions` block. The spec's "future song create/edit workspace surfaces" line refers to surfaces that do not yet exist; once a dedicated song-create workspace ships, mounting follows the same pattern. No new surface is introduced in this slice.

- [ ] **Step 4: Mount the control on planning surfaces**

Extend `PlanningWorkspaceShell` with an optional `headerSyncControl` widget rendered in the header row. Mount `UnifiedSyncHeaderControl` from `plan_list_screen.dart` and `plan_detail_screen.dart` via that slot.

- [ ] **Step 5: Verify reader surfaces stay clean**

Confirm `song_reader_screen.dart` and session-scoped reader do not import the unified header control.

Run header visibility test; expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add apps/lyron_app/lib/src/presentation \
        apps/lyron_app/test/presentation/sync/header_visibility_test.dart
git commit -m "feat(sync): mount header sync control on non-reader workspaces"
```

### Task 9: Sign-out warning via unified provider

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_library/song_list_screen.dart`
- Test: `apps/lyron_app/test/presentation/song_library/song_list_signout_test.dart`

- [ ] **Step 1: Write failing test**

Override `unifiedSyncOverviewProvider` with `hasUnsyncedWork=true` and assert the sign-out flow shows the unsynced warning dialog. Override with `hasUnsyncedWork=false` and assert sign-out proceeds without the dialog. (Test the existing key strings.)

Run:
```bash
cd apps/lyron_app && flutter test test/presentation/song_library/song_list_signout_test.dart
```
Expected: FAIL or already-passing-but-via-old-providers — adjust to drive the unified provider only.

- [ ] **Step 2: Switch `_signOut` to read `unifiedSyncOverviewProvider.hasUnsyncedWork`**

Remove the two ad-hoc `await ref.read(hasUnsynced…Provider.future)` reads. Keep the dialog copy intact.

Run test; expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add apps/lyron_app/lib/src/presentation/song_library/song_list_screen.dart \
        apps/lyron_app/test/presentation/song_library/song_list_signout_test.dart
git commit -m "feat(sync): use unified overview for sign-out warning"
```

### Task 10a: Song-only and planning-only queue tests

**Files:**
- Create: `apps/lyron_app/test/application/sync/unified_manual_sync_song_only_test.dart`
- Create: `apps/lyron_app/test/application/sync/unified_manual_sync_planning_only_test.dart`

- [ ] **Step 1: Song-only queue test**

Seed only pending song mutations (no planning work). `syncNow()` calls song mutation sync + catalog refresh, leaves planning controllers untouched (asserted via call counts on fakes), and final overview status reflects only song outcomes.

Run:
```bash
cd apps/lyron_app && flutter test test/application/sync/unified_manual_sync_song_only_test.dart
```
Expected: PASS after Task 3 + Task 4.

- [ ] **Step 2: Planning-only queue test**

Seed only pending planning mutations. `syncNow()` calls planning mutation sync + planning refresh, song sync attempted but no-ops on empty queue. Final overview status reflects planning outcomes only.

Run:
```bash
cd apps/lyron_app && flutter test test/application/sync/unified_manual_sync_planning_only_test.dart
```
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add apps/lyron_app/test/application/sync/unified_manual_sync_song_only_test.dart \
        apps/lyron_app/test/application/sync/unified_manual_sync_planning_only_test.dart
git commit -m "test(sync): cover song-only and planning-only manual sync queues"
```

### Task 10: Mixed-queue manual sync integration test

**Files:**
- Create: `apps/lyron_app/test/application/sync/unified_manual_sync_mixed_queue_test.dart`

- [ ] **Step 1: Write failing scenario test**

Drive in-memory Drift stores + fake remote with:
- one song create, one song edit conflict
- one plan create, one session add under that plan, one session reorder conflict on a different plan

Trigger `unifiedManualSyncControllerProvider.syncNow()` once and assert: pending song create accepted; song conflict preserved; pending planning work synced where accepted; reorder conflict preserved; final `UnifiedSyncOverview` shows `conflict` header status (red wins).

Run:
```bash
cd apps/lyron_app && flutter test test/application/sync/unified_manual_sync_mixed_queue_test.dart
```
Expected: FAIL → PASS after wiring.

- [ ] **Step 2: Commit**

```bash
git add apps/lyron_app/test/application/sync/unified_manual_sync_mixed_queue_test.dart
git commit -m "test(sync): cover mixed song and planning sync queue"
```

### Task 11: Reconnect + refresh-failure tests

**Files:**
- Create: `apps/lyron_app/test/application/sync/online_transition_reconnect_test.dart`
- Create: `apps/lyron_app/test/application/sync/refresh_failure_preservation_test.dart`

- [ ] **Step 1: Write reconnect test**

Start with catalog `offlineCached`, pending song mutations, planning `offline`. Flip both to online; assert the detector triggers `syncNow()` exactly once and the pending mutations are dispatched.

- [ ] **Step 2: Write refresh-failure preservation test**

Seed local catalog + planning projection. Force remote refresh to throw. Trigger `syncNow()`. Assert: prior local projections remain visible, `UnifiedSyncOverview.freshness == stale`, `headerStatus` unchanged from prior aggregate (red/yellow not promoted by refresh failure alone).

Run:
```bash
cd apps/lyron_app && flutter test test/application/sync/online_transition_reconnect_test.dart test/application/sync/refresh_failure_preservation_test.dart
```
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add apps/lyron_app/test/application/sync
git commit -m "test(sync): cover reconnect trigger and refresh-failure preservation"
```

### Task 12: Update repository docs

**Files:**
- Modify: `docs/architecture/architecture.md`
- Modify: `docs/testing/testing-strategy.md`
- Modify: `docs/deferred/2026-04-29-unified-manual-sync.md` (status note → Implemented; reference this plan)

- [ ] **Step 1: Architecture update**

Add a short paragraph under "Data Flow" describing the unified sync overview + manual sync command + foreground/online-transition triggers, the header control scope (authenticated non-reader workspaces), and that reader surfaces stay free of header-level sync UI.

Verify:
```bash
rg -n "UnifiedSync|unified sync|header sync control" docs/architecture/architecture.md
```

- [ ] **Step 2: Testing strategy update**

Add bullets under unit/widget/integration tests for: unified overview aggregation, header status precedence, popup grouping, manual sync orchestration ordering, reconnect trigger, foreground refresh trigger, refresh-failure projection preservation, sign-out warning via unified provider.

Verify:
```bash
rg -n "unified sync" docs/testing/testing-strategy.md
```

- [ ] **Step 3: Update deferred note**

Change `docs/deferred/2026-04-29-unified-manual-sync.md` status to `Implemented` and reference `docs/plans/2026-05-14-unified-sync-freshness-ux.md`.

Verify:
```bash
rg -n "Implemented|2026-05-14-unified-sync-freshness-ux" docs/deferred/2026-04-29-unified-manual-sync.md
```

- [ ] **Step 4: Commit**

```bash
git add docs/architecture/architecture.md docs/testing/testing-strategy.md docs/deferred/2026-04-29-unified-manual-sync.md
git commit -m "docs(sync): record unified sync slice in architecture, testing, deferred index"
```

### Task 13: Full local verification

- [ ] **Step 1: Run repository verify script**

Run:
```bash
./scripts/verify.sh
```
Expected: green. Fix any failure surfaced by the gate before continuing.

- [ ] **Step 2: Mark this plan Implemented**

Update the status line of this file to `Status: Implemented` and tick all checkboxes.

- [ ] **Step 3: Final commit**

```bash
git add docs/plans/2026-05-14-unified-sync-freshness-ux.md
git commit -m "docs(plan): mark unified sync freshness UX plan implemented"
```
