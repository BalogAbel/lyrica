import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/planning_data_revision.dart';
import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_controller.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/song_library/active_catalog_context.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_controller.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_types.dart';
import 'package:lyron_app/src/application/sync/unified_row_recovery_controller.dart';
import 'package:lyron_app/src/application/sync/unified_sync_overview.dart';
import 'package:lyron_app/src/domain/planning/plan_summary.dart';
import 'package:lyron_app/src/presentation/planning/planning_providers.dart';
import 'package:lyron_app/src/presentation/sync/unified_sync_providers.dart';

void main() {
  // Both keepMine and discardMine here take the local-only shortcut inside
  // SongMutationSyncController (LF-7: discard/keep-of-a-remote-deleted-
  // or-never-synced record never touches the network), so the fake remote
  // below throws on every call. If the controller regressed into needing
  // the network here, the test would fail with that exception rather than
  // silently passing.
  group('UnifiedRowRecoveryController via its provider', () {
    test('keepMine completes its invalidations even when the caller that '
        'started it is gone', () async {
      var songEntriesBuildCount = 0;
      var songLibraryBuildCount = 0;
      final songStore = _FakeSongStore([
        const SongMutationRecord(
          id: 'song-1',
          organizationId: 'o1',
          slug: 'alpha',
          title: 'Alpha',
          chordproSource: '{title: Alpha}',
          version: 3,
          baseVersion: 3,
          syncStatus: SongSyncStatus.conflict,
          errorCode: SongMutationSyncErrorCode.remoteDeleted,
          conflictSourceSyncStatus: SongSyncStatus.pendingDelete,
        ),
      ]);
      final songController = SongMutationSyncController(
        store: songStore,
        remoteRepository: _OfflineSongRemote(),
      );

      final container = ProviderContainer(
        overrides: [
          activeCatalogContextProvider.overrideWithValue(
            const ActiveCatalogContext(userId: 'u1', organizationId: 'o1'),
          ),
          songMutationSyncControllerProvider.overrideWithValue(songController),
          songMutationEntriesProvider.overrideWith((ref) async {
            songEntriesBuildCount++;
            return const <SongMutationRecord>[];
          }),
          songLibraryListProvider.overrideWith((ref) async {
            songLibraryBuildCount++;
            return const [];
          }),
        ],
      );
      addTearDown(container.dispose);

      await container.read(songMutationEntriesProvider.future);
      await container.read(songLibraryListProvider.future);
      expect(songEntriesBuildCount, 1);
      expect(songLibraryBuildCount, 1);

      // Model "the popup closed": the controller is read once, like a
      // widget's one-shot ref.read, with nothing left holding a
      // subscription to it afterwards. unifiedRowRecoveryControllerProvider
      // is autoDispose, so without its own keepAlive it would be torn down
      // as soon as the event loop gets a chance -- before the mutation
      // and its invalidations run. Driving it this way, with no widget in
      // the picture at all, proves the controller's completion no longer
      // depends on anything being mounted.
      final controller = container.read(unifiedRowRecoveryControllerProvider);
      final future = controller.keepMine('song-1');

      // Give any (incorrect) scheduled autoDispose a chance to fire before
      // the operation completes.
      await Future<void>.delayed(Duration.zero);

      final hadFailure = await future;

      expect(hadFailure, isFalse);
      expect(
        await songStore.readById(
          userId: 'u1',
          organizationId: 'o1',
          songId: 'song-1',
        ),
        isNull,
        reason:
            'keepMine on a remote-deleted pending-delete conflict '
            'deletes the row locally',
      );

      // The invalidations reached the providers: reading them again forces
      // a fresh build.
      await container.read(songMutationEntriesProvider.future);
      await container.read(songLibraryListProvider.future);
      expect(songEntriesBuildCount, 2);
      expect(songLibraryBuildCount, 2);
    });

    test('discardMine completes its invalidations even when the caller that '
        'started it is gone', () async {
      var songEntriesBuildCount = 0;
      var songLibraryBuildCount = 0;
      final songStore = _FakeSongStore([
        const SongMutationRecord(
          id: 'song-2',
          organizationId: 'o1',
          slug: 'beta',
          title: 'Beta',
          chordproSource: '{title: Beta}',
          version: 1,
          baseVersion: null,
          syncStatus: SongSyncStatus.pendingCreate,
        ),
      ]);
      final songController = SongMutationSyncController(
        store: songStore,
        remoteRepository: _OfflineSongRemote(),
      );

      final container = ProviderContainer(
        overrides: [
          activeCatalogContextProvider.overrideWithValue(
            const ActiveCatalogContext(userId: 'u1', organizationId: 'o1'),
          ),
          songMutationSyncControllerProvider.overrideWithValue(songController),
          songMutationEntriesProvider.overrideWith((ref) async {
            songEntriesBuildCount++;
            return const <SongMutationRecord>[];
          }),
          songLibraryListProvider.overrideWith((ref) async {
            songLibraryBuildCount++;
            return const [];
          }),
        ],
      );
      addTearDown(container.dispose);

      await container.read(songMutationEntriesProvider.future);
      await container.read(songLibraryListProvider.future);

      final controller = container.read(unifiedRowRecoveryControllerProvider);
      final future = controller.discardMineResult('song-2');
      await Future<void>.delayed(Duration.zero);
      final result = await future;

      expect(result, UnifiedRowDiscardResult.discarded);
      expect(
        await songStore.readById(
          userId: 'u1',
          organizationId: 'o1',
          songId: 'song-2',
        ),
        isNull,
        reason: 'discardMine on a pending-create record deletes it locally',
      );

      await container.read(songMutationEntriesProvider.future);
      await container.read(songLibraryListProvider.future);
      expect(songEntriesBuildCount, 2);
      expect(songLibraryBuildCount, 2);
    });

    test(
      'discardMine reports a sync-in-progress rejection so the row can show retry-after-sync guidance',
      () async {
        final songController = _SyncOwnedSongController();
        final container = ProviderContainer(
          overrides: [
            activeCatalogContextProvider.overrideWithValue(
              const ActiveCatalogContext(userId: 'u1', organizationId: 'o1'),
            ),
            songMutationSyncControllerProvider.overrideWithValue(
              songController,
            ),
          ],
        );
        addTearDown(container.dispose);

        final result = await container
            .read(unifiedRowRecoveryControllerProvider)
            .discardMineResult('song-3');

        expect(songController.discardMineCalls, ['song-3']);
        expect(
          result,
          UnifiedRowDiscardResult.syncInProgress,
          reason:
              'typed sync ownership rejection must not be swallowed as success',
        );
      },
    );

    test('applyToGroup performs all of its post-work: the '
        'planningDataRevisionProvider bump AND both invalidations', () async {
      var mutationEntriesBuildCount = 0;
      var planListBuildCount = 0;
      final planningStore = _FakePlanningStore([
        PlanningMutationRecord(
          aggregateId: 'plan-1',
          organizationId: 'o1',
          name: 'Weekend Service',
          kind: PlanningMutationKind.planEdit,
          syncStatus: PlanningMutationSyncStatus.pending,
          orderKey: 1,
          updatedAt: DateTime.utc(2026),
        ),
      ]);
      final planningController = PlanningMutationSyncController(
        mutationStore: () => planningStore,
        remoteRepository: () => _OfflinePlanningRemote(),
        refreshPlanning: () async => false,
        shouldReconcileAcceptedMutation: (_) async => true,
        reconcileAcceptedMutation: (_, _) async {},
      );

      final container = ProviderContainer(
        overrides: [
          activePlanningContextProvider.overrideWithValue(
            const ActivePlanningReadContext(userId: 'u1', organizationId: 'o1'),
          ),
          planningMutationSyncControllerProvider.overrideWithValue(
            planningController,
          ),
          planningMutationEntriesProvider.overrideWith((ref) async {
            mutationEntriesBuildCount++;
            return const <PlanningMutationRecord>[];
          }),
          planningPlanListProvider.overrideWith((ref) async {
            planListBuildCount++;
            return const <PlanSummary>[];
          }),
        ],
      );
      addTearDown(container.dispose);

      await container.read(planningMutationEntriesProvider.future);
      await container.read(planningPlanListProvider.future);
      expect(mutationEntriesBuildCount, 1);
      expect(planListBuildCount, 1);

      final revisionBefore = container.read(planningDataRevisionProvider);

      final controller = container.read(unifiedRowRecoveryControllerProvider);
      final future = controller.applyToGroup(const [
        UnifiedSyncPlanMutationRef(
          aggregateType: 'plan',
          aggregateId: 'plan-1',
        ),
      ], retry: false);
      await Future<void>.delayed(Duration.zero);
      final hadFailure = await future;

      expect(hadFailure, isFalse);

      // The revision bump is the only thing that reaches the family
      // slug/detail providers (planningPlanBySlugProvider,
      // planningPlanDetailBySlugProvider, planningPlanDetailProvider),
      // which are never invalidated directly. Dropping it in the move
      // would silently stop them refreshing, and nothing else here would
      // catch that.
      expect(container.read(planningDataRevisionProvider), revisionBefore + 1);

      await container.read(planningMutationEntriesProvider.future);
      await container.read(planningPlanListProvider.future);
      expect(mutationEntriesBuildCount, 2);
      expect(planListBuildCount, 2);
    });

    test('applyToGroup reports failure without throwing when a ref fails, '
        'and still performs the revision bump and invalidations', () async {
      var mutationEntriesBuildCount = 0;
      var planListBuildCount = 0;
      // Empty store: retryMutation on a non-existent record is a
      // best-effort no-op in the fake, so force a failure via the online
      // remote instead by seeding a pending mutation and using a remote
      // that always throws -- retryMutation surfaces a connectivity
      // failure explicitly (see PlanningMutationSyncController.retryMutation).
      final planningStore = _FakePlanningStore([
        PlanningMutationRecord(
          aggregateId: 'plan-2',
          organizationId: 'o1',
          name: 'Retry Me',
          kind: PlanningMutationKind.planEdit,
          syncStatus: PlanningMutationSyncStatus.pending,
          orderKey: 1,
          updatedAt: DateTime.utc(2026),
        ),
      ]);
      final planningController = PlanningMutationSyncController(
        mutationStore: () => planningStore,
        remoteRepository: () => _OfflinePlanningRemote(),
        refreshPlanning: () async => false,
        shouldReconcileAcceptedMutation: (_) async => true,
        reconcileAcceptedMutation: (_, _) async {},
      );

      final container = ProviderContainer(
        overrides: [
          activePlanningContextProvider.overrideWithValue(
            const ActivePlanningReadContext(userId: 'u1', organizationId: 'o1'),
          ),
          planningMutationSyncControllerProvider.overrideWithValue(
            planningController,
          ),
          planningMutationEntriesProvider.overrideWith((ref) async {
            mutationEntriesBuildCount++;
            return const <PlanningMutationRecord>[];
          }),
          planningPlanListProvider.overrideWith((ref) async {
            planListBuildCount++;
            return const <PlanSummary>[];
          }),
        ],
      );
      addTearDown(container.dispose);

      await container.read(planningMutationEntriesProvider.future);
      await container.read(planningPlanListProvider.future);
      final revisionBefore = container.read(planningDataRevisionProvider);

      final controller = container.read(unifiedRowRecoveryControllerProvider);
      final hadFailure = await controller.applyToGroup(const [
        UnifiedSyncPlanMutationRef(
          aggregateType: 'plan',
          aggregateId: 'plan-2',
        ),
      ], retry: true);

      expect(hadFailure, isTrue);
      expect(container.read(planningDataRevisionProvider), revisionBefore + 1);
      await container.read(planningMutationEntriesProvider.future);
      await container.read(planningPlanListProvider.future);
      expect(mutationEntriesBuildCount, 2);
      expect(planListBuildCount, 2);
    });
  });
}

/// Minimal in-memory SongMutationStore, matching the shape used in
/// unified_discard_controller_test.dart.
class _FakeSongStore implements SongMutationStore {
  _FakeSongStore(List<SongMutationRecord> seed)
    : _mutations = {for (final record in seed) record.id: record};

  final Map<String, SongMutationRecord> _mutations;

  @override
  Future<SongMutationRecord?> readById({
    required String userId,
    required String organizationId,
    required String songId,
  }) async => _mutations[songId];

  @override
  Future<List<SongMutationRecord>> readPendingSongs({
    required String userId,
    required String organizationId,
  }) async => _mutations.values
      .where(
        (record) => switch (record.syncStatus) {
          SongSyncStatus.pendingCreate ||
          SongSyncStatus.pendingUpdate ||
          SongSyncStatus.pendingDelete ||
          SongSyncStatus.sending => true,
          SongSyncStatus.conflict ||
          SongSyncStatus.synced ||
          SongSyncStatus.cancelling => false,
        },
      )
      .toList(growable: false);

  @override
  Future<List<SongMutationRecord>> readConflictSongs({
    required String userId,
    required String organizationId,
  }) async => _mutations.values
      .where((record) => record.syncStatus == SongSyncStatus.conflict)
      .toList(growable: false);

  @override
  Future<void> clearSongMutation({
    required String userId,
    required String organizationId,
    required String songId,
  }) async {
    _mutations.remove(songId);
  }

  @override
  Future<void> deleteSong({
    required String userId,
    required String organizationId,
    required String songId,
  }) async {
    _mutations.remove(songId);
  }

  @override
  Future<bool> reconcileSyncedSong({
    required String userId,
    required String organizationId,
    required SongMutationRecord record,
    int? expectedRevision,
  }) async {
    _mutations.remove(record.id);
    return true;
  }

  @override
  Future<bool> saveSyncAttemptResult({
    required String userId,
    required String organizationId,
    required String songId,
    required SongSyncStatus syncStatus,
    SongMutationSyncErrorCode? errorCode,
    String? errorMessage,
  }) async {
    final existing = _mutations[songId];
    if (existing != null) {
      _mutations[songId] = existing.copyWith(
        syncStatus: syncStatus,
        errorCode: errorCode,
        clearErrorCode: errorCode == null,
        errorMessage: errorMessage,
        clearErrorMessage: errorMessage == null,
      );
    }
    return existing != null;
  }

  @override
  Future<void> upsertSong({
    required String userId,
    required SongMutationRecord record,
  }) async {
    _mutations[record.id] = record;
  }

  @override
  Future<bool> hasUnsyncedChanges({required String userId}) async =>
      _mutations.isNotEmpty;

  @override
  Future<int> countReferencingSessionItems({
    required String userId,
    required String organizationId,
    required String songId,
  }) async => 0;

  @override
  Future<String> allocateUniqueSlug({
    required String userId,
    required String organizationId,
    required String title,
  }) async => 'unused';
}

/// Every call fails as if there is no connectivity. Neither keepMine's nor
/// discardMine's scenario in this file should ever reach it -- if one does,
/// the row recovery wiring stopped taking the local-only shortcut and the
/// test fails with this exception instead of silently passing.
class _OfflineSongRemote implements SongMutationRemoteRepository {
  @override
  Future<SongMutationRecord> fetchSong({
    required String organizationId,
    required String songId,
  }) async => throw const SongMutationSyncException(
    SongMutationSyncErrorCode.connectivityFailure,
  );

  @override
  Future<SongMutationRecord> overwriteSong({
    required String organizationId,
    required SongMutationRecord record,
  }) async => throw const SongMutationSyncException(
    SongMutationSyncErrorCode.connectivityFailure,
  );

  @override
  Future<SongMutationRecord> syncSong({
    required String organizationId,
    required SongMutationRecord record,
  }) async => throw const SongMutationSyncException(
    SongMutationSyncErrorCode.connectivityFailure,
  );
}

class _SyncOwnedSongController extends SongMutationSyncController {
  _SyncOwnedSongController()
    : super(
        store: _FakeSongStore(const []),
        remoteRepository: _OfflineSongRemote(),
      );

  final List<String> discardMineCalls = [];

  @override
  Future<SongDiscardResult> discardMine(
    SongMutationContext context, {
    required String songId,
  }) async {
    discardMineCalls.add(songId);
    return SongDiscardResult.syncInProgress;
  }
}

/// Minimal in-memory PlanningMutationStore, matching the shape used in
/// unified_discard_controller_test.dart.
class _FakePlanningStore implements PlanningMutationStore {
  // Stub for docs/specs/2026-08-06-in-flight-create-cancellation.md (D3):
  // none of these tests exercise the in-flight-create-cancellation
  // tombstone path, which is covered against the real
  // DriftPlanningMutationStore in
  // test/offline/adversarial/planning_in_flight_create_cancellation_test.dart.
  @override
  Future<bool> resolveCancelledCreate({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
    required bool created,
    int? acceptedBaseVersion,
  }) async => false;
  _FakePlanningStore(List<PlanningMutationRecord> seed)
    : _mutations = {
        for (final record in seed)
          _key(record.kind.aggregateType, record.aggregateId): record,
      };

  final Map<String, PlanningMutationRecord> _mutations;

  static String _key(String aggregateType, String aggregateId) =>
      '$aggregateType:$aggregateId';

  @override
  Future<List<PlanningMutationRecord>> readAllMutations({
    required String userId,
    required String organizationId,
  }) async => _mutations.values.toList(growable: false);

  @override
  Future<List<PlanningMutationRecord>> readActionableMutations({
    required String userId,
    required String organizationId,
  }) async => _mutations.values
      .where(
        (record) =>
            record.syncStatus == PlanningMutationSyncStatus.pending ||
            record.syncStatus == PlanningMutationSyncStatus.accepted,
      )
      .toList(growable: false);

  @override
  Future<List<PlanningMutationRecord>> readPendingMutations({
    required String userId,
    required String organizationId,
  }) async => _mutations.values
      .where(
        (record) => record.syncStatus == PlanningMutationSyncStatus.pending,
      )
      .toList(growable: false);

  @override
  Future<PlanningMutationRecord?> readMutation({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
  }) async => _mutations[_key(aggregateType, aggregateId)];

  @override
  Future<bool> clearMutation({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
    int? expectedRevision,
  }) async {
    return _mutations.remove(_key(aggregateType, aggregateId)) != null;
  }

  @override
  Future<int?> saveSyncAttemptResult({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
    required PlanningMutationSyncStatus syncStatus,
    PlanningMutationSyncErrorCode? errorCode,
    String? errorMessage,
    int? expectedRevision,
  }) async {
    final key = _key(aggregateType, aggregateId);
    final existing = _mutations[key];
    if (existing == null) {
      return null;
    }
    _mutations[key] = existing.copyWith(
      syncStatus: syncStatus,
      errorCode: errorCode,
      clearErrorCode: errorCode == null,
      errorMessage: errorMessage,
      clearErrorMessage: errorMessage == null,
    );
    return 1;
  }

  @override
  Future<bool> retryMutation({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
  }) async {
    final key = _key(aggregateType, aggregateId);
    final existing = _mutations[key];
    if (existing != null) {
      _mutations[key] = existing.copyWith(
        syncStatus: PlanningMutationSyncStatus.pending,
        clearErrorCode: true,
        clearErrorMessage: true,
      );
    }
    return existing != null;
  }

  @override
  Future<bool> hasUnsyncedMutations({required String userId}) async =>
      _mutations.isNotEmpty;

  @override
  Future<String> allocatePlanSlug({
    required String userId,
    required String organizationId,
    required String name,
  }) async => 'unused';

  @override
  Future<String> allocateSessionSlug({
    required String userId,
    required String organizationId,
    required String planId,
    required String name,
  }) async => 'unused';

  @override
  Future<void> recordPlanCreate({
    required PlanningMutationContext context,
    required PlanningPlanCreateMutationDraft draft,
  }) async {}

  @override
  Future<void> recordPlanEdit({
    required PlanningMutationContext context,
    required PlanningPlanEditMutationDraft draft,
  }) async {}

  @override
  Future<void> recordSessionCreate({
    required PlanningMutationContext context,
    required PlanningSessionCreateMutationDraft draft,
  }) async {}

  @override
  Future<void> recordSessionDelete({
    required PlanningMutationContext context,
    required PlanningSessionDeleteMutationDraft draft,
  }) async {}

  @override
  Future<void> recordSessionItemCreateSong({
    required PlanningMutationContext context,
    required PlanningSessionItemCreateSongMutationDraft draft,
  }) async {}

  @override
  Future<void> recordSessionItemDelete({
    required PlanningMutationContext context,
    required PlanningSessionItemDeleteMutationDraft draft,
  }) async {}

  @override
  Future<void> recordSessionItemReorder({
    required PlanningMutationContext context,
    required PlanningSessionItemReorderMutationDraft draft,
  }) async {}

  @override
  Future<void> recordSessionReorder({
    required PlanningMutationContext context,
    required PlanningSessionReorderMutationDraft draft,
  }) async {}

  @override
  Future<void> recordSessionRename({
    required PlanningMutationContext context,
    required PlanningSessionRenameMutationDraft draft,
  }) async {}
}

/// Every call fails as if there is no connectivity, for the same reason as
/// _OfflineSongRemote above.
class _OfflinePlanningRemote implements PlanningMutationRemoteRepository {
  @override
  Future<PlanningMutationRecord> syncMutation({
    required String organizationId,
    required PlanningMutationRecord record,
  }) async => throw const PlanningMutationSyncException(
    PlanningMutationSyncErrorCode.connectivityFailure,
  );
}
