import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/song_library/drift_song_mutation_store.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_controller.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_types.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_store.dart';

import '../../support/drift_test_setup.dart';

/// Adversarial coverage for MG3 of
/// `docs/specs/2026-10-21-planning-mutation-gaps.md`: a song sync run belongs
/// to one `(userId, organizationId)` catalog context. When the active catalog
/// context moves while the run is awaiting the backend, the run stops (C1) and
/// a failure answered after the move is not written as this row's verdict
/// (C6). Drives the real Drift stores, like the other song adversarial suites.
void main() {
  suppressDriftMultipleDatabaseWarnings();

  group('Song run boundary (MG3)', () {
    test('a catalog context change between songs stops the run', () async {
      final env = _TestEnv();
      addTearDown(env.close);
      await env.seedPendingUpdate('song-1');
      await env.seedPendingUpdate('song-2');

      var active = true;
      final remote = _GatedSongRemote();
      final controller = SongMutationSyncController(
        isContextActive: (_) => active,
        store: env.mutationStore,
        remoteRepository: remote,
      );

      final syncFuture = controller.syncPendingSongs(env.songContext);
      await remote.entered.future;
      active = false;
      remote.gate.complete();
      await syncFuture;

      expect(remote.calls, hasLength(1));
      final sentId = remote.calls.single.id;
      final otherId = sentId == 'song-1' ? 'song-2' : 'song-1';
      final other = await env.mutationStore.readById(
        userId: 'user-1',
        organizationId: 'org-1',
        songId: otherId,
      );
      expect(other, isNotNull);
      expect(other!.syncStatus, SongSyncStatus.pendingUpdate);
    });

    test(
      'a failure answered after a context change keeps the song pending',
      () async {
        final env = _TestEnv();
        addTearDown(env.close);
        await env.seedPendingUpdate('song-1');

        var active = true;
        final remote = _GatedSongRemote(
          failFirstWith: const SongMutationSyncException(
            SongMutationSyncErrorCode.authorizationDenied,
          ),
        );
        final controller = SongMutationSyncController(
          isContextActive: (_) => active,
          store: env.mutationStore,
          remoteRepository: remote,
        );

        final syncFuture = controller.syncPendingSongs(env.songContext);
        await remote.entered.future;
        active = false;
        remote.gate.complete();
        await syncFuture;

        final row = await env.mutationStore.readById(
          userId: 'user-1',
          organizationId: 'org-1',
          songId: 'song-1',
        );
        expect(row, isNotNull);
        expect(row!.syncStatus, SongSyncStatus.pendingUpdate);
        expect(row.syncStatus, isNot(SongSyncStatus.conflict));
      },
    );
  });
}

class _TestEnv {
  _TestEnv()
    : songDatabase = SongCatalogDatabase.inMemory(),
      planningDatabase = PlanningLocalDatabase.inMemory() {
    songStore = DriftSongCatalogStore(songDatabase);
    mutationStore = DriftSongMutationStore(
      songCatalogStore: songStore,
      planningLocalStore: DriftPlanningLocalStore(planningDatabase),
    );
  }

  final SongCatalogDatabase songDatabase;
  final PlanningLocalDatabase planningDatabase;
  late final DriftSongCatalogStore songStore;
  late final DriftSongMutationStore mutationStore;

  final songContext = const SongMutationContext(
    userId: 'user-1',
    organizationId: 'org-1',
  );

  Future<void> seedPendingUpdate(String id) => mutationStore.upsertSong(
    userId: 'user-1',
    record: SongMutationRecord(
      id: id,
      organizationId: 'org-1',
      slug: id,
      title: id,
      chordproSource: '{title: $id}',
      version: 3,
      baseVersion: 3,
      syncStatus: SongSyncStatus.pendingUpdate,
    ),
  );

  Future<void> close() async {
    await planningDatabase.close();
    await songDatabase.close();
  }
}

/// Gates exactly the FIRST `syncSong` call on [gate], signalling [entered]
/// once reached. Later calls resolve immediately.
class _GatedSongRemote implements SongMutationRemoteRepository {
  _GatedSongRemote({this.failFirstWith});

  final SongMutationSyncException? failFirstWith;

  final Completer<void> entered = Completer<void>();
  final Completer<void> gate = Completer<void>();
  final List<SongMutationRecord> calls = [];
  bool _firstCallSeen = false;

  @override
  Future<SongMutationRecord> syncSong({
    required String organizationId,
    required SongMutationRecord record,
  }) async {
    calls.add(record);
    if (!_firstCallSeen) {
      _firstCallSeen = true;
      if (!entered.isCompleted) {
        entered.complete();
      }
      await gate.future;
      final failure = failFirstWith;
      if (failure != null) {
        throw failure;
      }
    }
    return record.copyWith(
      syncStatus: SongSyncStatus.synced,
      version: 4,
      baseVersion: 4,
    );
  }

  @override
  Future<SongMutationRecord> overwriteSong({
    required String organizationId,
    required SongMutationRecord record,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<SongMutationRecord> fetchSong({
    required String organizationId,
    required String songId,
  }) {
    throw UnimplementedError();
  }
}
