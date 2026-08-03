import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_controller.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_controller.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_types.dart';
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

  test(
    'discardAll rejects atomically before song or planning removal when song sync owns the context',
    () async {
      const song = SongMutationRecord(
        id: 'song-1',
        organizationId: 'o1',
        slug: 'alpha',
        title: 'Alpha',
        chordproSource: '{title: Alpha}',
        version: 3,
        baseVersion: 3,
        syncStatus: SongSyncStatus.pendingUpdate,
      );
      final songStore = _FakeSongStore(const [song]);
      final remoteEntered = Completer<void>();
      final releaseRemote = Completer<void>();
      final songController = SongMutationSyncController(
        store: songStore,
        remoteRepository: _GatedSongRemote(
          onSend: () async {
            remoteEntered.complete();
            await releaseRemote.future;
          },
        ),
      );
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
      const songContext = SongMutationContext(
        userId: 'u1',
        organizationId: 'o1',
      );
      final sync = songController.syncPendingSongs(songContext);
      await remoteEntered.future;

      final controller = UnifiedDiscardController(
        activeContextReader: () =>
            const UnifiedDiscardContext(userId: 'u1', organizationId: 'o1'),
        acquireSongDiscardLease: (ctx) => songController.acquireDiscardLease(
          SongMutationContext(
            userId: ctx.userId,
            organizationId: ctx.organizationId,
          ),
        ),
        discardSongsWhileOwned: (ctx, lease) async {
          await lease.discardMine(songId: song.id);
        },
        discardSongs: (ctx) async {
          await songController.discardMine(songContext, songId: song.id);
        },
        discardPlanning: (ctx) => planningStore.clearMutation(
          userId: ctx.userId,
          organizationId: ctx.organizationId,
          aggregateType: PlanningMutationKind.planEdit.aggregateType,
          aggregateId: 'plan-1',
        ),
      );

      final result = await controller.discardAll();
      final songsDuringRemote = await songStore.readPendingSongs(
        userId: 'u1',
        organizationId: 'o1',
      );
      final planningDuringRemote = await planningStore.readAllMutations(
        userId: 'u1',
        organizationId: 'o1',
      );

      releaseRemote.complete();
      await sync;

      expect(
        (
          result: result,
          songMutationCount: songsDuringRemote.length,
          planningMutationCount: planningDuringRemote.length,
        ),
        (
          result: UnifiedDiscardResult.syncInProgress,
          songMutationCount: 1,
          planningMutationCount: 1,
        ),
      );
    },
  );

  test(
    // Spec testing item 5 (LF-7): "Discard All offline reports rather than
    // silently no-ops". Wires the real per-domain sync controllers (not
    // hand-rolled test doubles for the assertion itself) behind
    // discardSongs/discardPlanning, the same shape unified_sync_providers.dart
    // uses, with remote repositories that throw connectivityFailure on every
    // call. D1/D1-for-planning make discard local-first, so this passes by
    // construction -- the point is pinning the contract so a future
    // regression (e.g. discard needing the network again) is caught here.
    'discardAll actually clears song and planning mutations while offline, '
    'rather than silently no-op-ing',
    () async {
      final songStore = _FakeSongStore([
        const SongMutationRecord(
          id: 'song-1',
          organizationId: 'o1',
          slug: 'alpha',
          title: 'Alpha',
          chordproSource: '{title: Alpha}',
          version: 3,
          baseVersion: 3,
          syncStatus: SongSyncStatus.pendingUpdate,
        ),
      ]);
      final songController = SongMutationSyncController(
        store: songStore,
        remoteRepository: _OfflineSongRemote(),
        // No refreshCatalog wired: discardMine's best-effort refresh is
        // optional, and omitting it here proves the discard itself needs no
        // network at all.
      );

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

      final controller = UnifiedDiscardController(
        activeContextReader: () =>
            const UnifiedDiscardContext(userId: 'u1', organizationId: 'o1'),
        discardSongs: (ctx) async {
          final songContext = SongMutationContext(
            userId: ctx.userId,
            organizationId: ctx.organizationId,
          );
          final entries = [
            ...await songStore.readPendingSongs(
              userId: ctx.userId,
              organizationId: ctx.organizationId,
            ),
            ...await songStore.readConflictSongs(
              userId: ctx.userId,
              organizationId: ctx.organizationId,
            ),
          ];
          for (final entry in entries) {
            try {
              await songController.discardMine(songContext, songId: entry.id);
            } catch (_) {
              // Best-effort, mirroring unified_sync_providers.dart's wiring:
              // one entry failing must not block the rest.
            }
          }
        },
        discardPlanning: (ctx) async {
          final planningContext = ActivePlanningReadContext(
            userId: ctx.userId,
            organizationId: ctx.organizationId,
          );
          final entries = await planningStore.readAllMutations(
            userId: ctx.userId,
            organizationId: ctx.organizationId,
          );
          for (final entry in entries) {
            try {
              await planningController.discardMutation(
                planningContext,
                aggregateType: entry.kind.aggregateType,
                aggregateId: entry.aggregateId,
              );
            } catch (_) {
              // Best-effort, mirroring unified_sync_providers.dart's wiring.
            }
          }
        },
      );

      await controller.discardAll();

      final remainingSongs = [
        ...await songStore.readPendingSongs(userId: 'u1', organizationId: 'o1'),
        ...await songStore.readConflictSongs(
          userId: 'u1',
          organizationId: 'o1',
        ),
      ];
      final remainingPlanning = await planningStore.readAllMutations(
        userId: 'u1',
        organizationId: 'o1',
      );

      expect(remainingSongs, isEmpty);
      expect(remainingPlanning, isEmpty);
    },
  );
}

/// Minimal in-memory SongMutationStore. Unlike the fake in
/// song_mutation_sync_controller_test.dart, this one has no separate
/// snapshot table -- this test only needs to prove the mutation is gone,
/// not what it restores to (that is covered there).
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
          SongSyncStatus.pendingDelete => true,
          SongSyncStatus.conflict || SongSyncStatus.synced => false,
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
  Future<void> reconcileSyncedSong({
    required String userId,
    required String organizationId,
    required SongMutationRecord record,
  }) async {
    _mutations.remove(record.id);
  }

  @override
  Future<void> saveSyncAttemptResult({
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

/// Every call fails as if there is no connectivity. Discard must never
/// reach any of these -- if it does, the discard was not actually
/// local-first and the test's best-effort catch would mask a regression.
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

class _GatedSongRemote implements SongMutationRemoteRepository {
  _GatedSongRemote({required this.onSend});

  final Future<void> Function() onSend;

  @override
  Future<SongMutationRecord> fetchSong({
    required String organizationId,
    required String songId,
  }) => throw UnimplementedError();

  @override
  Future<SongMutationRecord> overwriteSong({
    required String organizationId,
    required SongMutationRecord record,
  }) => throw UnimplementedError();

  @override
  Future<SongMutationRecord> syncSong({
    required String organizationId,
    required SongMutationRecord record,
  }) async {
    await onSend();
    return record.copyWith(syncStatus: SongSyncStatus.synced);
  }
}

/// Minimal in-memory PlanningMutationStore, keyed the same way the real
/// aggregate (type, id) pair is.
class _FakePlanningStore implements PlanningMutationStore {
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
  Future<void> clearMutation({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
  }) async {
    _mutations.remove(_key(aggregateType, aggregateId));
  }

  @override
  Future<void> saveSyncAttemptResult({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
    required PlanningMutationSyncStatus syncStatus,
    PlanningMutationSyncErrorCode? errorCode,
    String? errorMessage,
  }) async {
    final key = _key(aggregateType, aggregateId);
    final existing = _mutations[key];
    if (existing != null) {
      _mutations[key] = existing.copyWith(
        syncStatus: syncStatus,
        errorCode: errorCode,
        clearErrorCode: errorCode == null,
        errorMessage: errorMessage,
        clearErrorMessage: errorMessage == null,
      );
    }
  }

  @override
  Future<void> retryMutation({
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
