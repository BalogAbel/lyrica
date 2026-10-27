import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/song_library/active_catalog_context.dart';
import 'package:lyron_app/src/application/song_library/drift_song_mutation_store.dart';
import 'package:lyron_app/src/application/song_library/song_library_service.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_controller.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_types.dart';
import 'package:lyron_app/src/infrastructure/song_library/local_first_song_repository.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_store.dart';

import '../../support/drift_test_setup.dart';

/// MG7 (docs/specs/2026-10-21-planning-mutation-gaps.md, ADR-030 "Stranded
/// Tombstone Follow-Up"): a `cancelling` create tombstone that no run
/// resolved (the app died between the create's send and its answer) is
/// converted into a `pendingDelete` at the start of the next run. Drives the
/// real `DriftSongCatalogStore`/`DriftSongMutationStore`, like
/// `song_in_flight_create_cancellation_test.dart`.
void main() {
  suppressDriftMultipleDatabaseWarnings();

  group('Stranded song create tombstone (MG7)', () {
    test('a stranded song tombstone whose create committed is deleted by the '
        'next run', () async {
      final env = _TestEnv();
      addTearDown(env.close);
      await env.strand(env.context);
      final remote = _ScriptedSongRemote(
        (record) async => record.copyWith(syncStatus: SongSyncStatus.synced),
      );

      await env.run(remote);

      expect(remote.calls, hasLength(1));
      expect(remote.calls.single.syncStatus, SongSyncStatus.pendingDelete);
      expect(remote.calls.single.baseVersion, 1);
      expect(await env.readRow('org-1'), isNull);
    });

    test('a stranded song tombstone whose create never committed is removed '
        'on remoteDeleted', () async {
      final env = _TestEnv();
      addTearDown(env.close);
      await env.strand(env.context);
      final remote = _ScriptedSongRemote(
        (record) async => throw const SongMutationSyncException(
          SongMutationSyncErrorCode.remoteDeleted,
        ),
      );

      await env.run(remote);

      expect(remote.calls, hasLength(1));
      expect(await env.readRow('org-1'), isNull);
    });

    test('a connectivity failure keeps the converted pendingDelete', () async {
      final env = _TestEnv();
      addTearDown(env.close);
      await env.strand(env.context);
      final remote = _ScriptedSongRemote(
        (record) async => throw const SongMutationSyncException(
          SongMutationSyncErrorCode.connectivityFailure,
        ),
      );

      await env.run(remote);

      final row = await env.readRow('org-1');
      expect(row, isNotNull);
      expect(row!.syncStatus, SongSyncStatus.pendingDelete);
    });

    test('a conflict ends conflict', () async {
      final env = _TestEnv();
      addTearDown(env.close);
      await env.strand(env.context);
      final remote = _ScriptedSongRemote(
        (record) async => throw const SongMutationSyncException(
          SongMutationSyncErrorCode.conflict,
        ),
      );

      await env.run(remote);

      final row = await env.readRow('org-1');
      expect(row, isNotNull);
      expect(row!.syncStatus, SongSyncStatus.conflict);
    });

    test('a song tombstone of another context is untouched', () async {
      final env = _TestEnv();
      addTearDown(env.close);
      await env.strand(
        const ActiveCatalogContext(userId: 'user-1', organizationId: 'org-2'),
      );
      final remote = _ScriptedSongRemote((record) async => record);

      await env.run(remote);

      expect(remote.calls, isEmpty);
      final row = await env.songStore.readSongMutationBySongId(
        userId: 'user-1',
        organizationId: 'org-2',
        songId: 'song-1',
      );
      expect(row, isNotNull);
      expect(row!.syncStatus, SongSyncStatus.cancelling.value);
    });
  });
}

class _TestEnv {
  _TestEnv()
    : songDatabase = SongCatalogDatabase.inMemory(),
      planningDatabase = PlanningLocalDatabase.inMemory() {
    songStore = DriftSongCatalogStore(songDatabase);
    final planningStore = DriftPlanningLocalStore(planningDatabase);
    mutationStore = DriftSongMutationStore(
      songCatalogStore: songStore,
      planningLocalStore: planningStore,
    );
    service = SongLibraryService(
      LocalFirstSongRepository(songStore),
      mutationStore,
      () => 'song-1',
    );
  }

  final SongCatalogDatabase songDatabase;
  final PlanningLocalDatabase planningDatabase;
  late final DriftSongCatalogStore songStore;
  late final DriftSongMutationStore mutationStore;
  late final SongLibraryService service;

  final context = const ActiveCatalogContext(
    userId: 'user-1',
    organizationId: 'org-1',
  );
  final songContext = const SongMutationContext(
    userId: 'user-1',
    organizationId: 'org-1',
  );

  /// Strands a create tombstone: the create was marked `sending`, the app
  /// died before the answer, and the user deleted the song meanwhile.
  Future<void> strand(ActiveCatalogContext target) async {
    final created = await service.createSong(
      context: target,
      title: 'Alpha',
      chordproSource: '{title: Alpha}',
    );
    final stored = await songStore.readSongMutationBySongId(
      userId: target.userId,
      organizationId: target.organizationId,
      songId: created.id,
    );
    await mutationStore.markCreateSending(
      userId: target.userId,
      organizationId: target.organizationId,
      songId: created.id,
      expectedRevision: stored!.localRevision,
    );
    await service.deleteSong(context: target, songId: created.id);
    final row = await songStore.readSongMutationBySongId(
      userId: target.userId,
      organizationId: target.organizationId,
      songId: created.id,
    );
    expect(row!.syncStatus, SongSyncStatus.cancelling.value);
  }

  Future<SongMutationRecord?> readRow(String organizationId) =>
      mutationStore.readById(
        userId: 'user-1',
        organizationId: organizationId,
        songId: 'song-1',
      );

  Future<void> run(SongMutationRemoteRepository remote) {
    final controller = SongMutationSyncController(
      isContextActive: (_) => true,
      store: mutationStore,
      remoteRepository: remote,
    );
    return controller.syncPendingSongs(songContext);
  }

  Future<void> close() async {
    await planningDatabase.close();
    await songDatabase.close();
  }
}

/// Records every `syncSong` record and answers from [_answer].
class _ScriptedSongRemote implements SongMutationRemoteRepository {
  _ScriptedSongRemote(this._answer);

  final Future<SongMutationRecord> Function(SongMutationRecord record) _answer;
  final List<SongMutationRecord> calls = [];

  @override
  Future<SongMutationRecord> syncSong({
    required String organizationId,
    required SongMutationRecord record,
  }) {
    calls.add(record);
    return _answer(record);
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
