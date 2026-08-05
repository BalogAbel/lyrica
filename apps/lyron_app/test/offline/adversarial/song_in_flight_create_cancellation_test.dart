import 'dart:async';

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

/// Adversarial coverage for the song/catalog half of
/// `docs/specs/2026-08-06-in-flight-create-cancellation.md` (D1/D2/D3):
/// `SongMutationSyncController._runSync` sends a `pendingCreate` song and
/// awaits the backend. `SongLibraryService.deleteSong`'s `pendingCreate`
/// branch physically removes the mutation row (the collapse ADR-028 D10
/// deliberately admits) with no regard for whether a remote create attempt
/// for that exact row is in flight right now. If the user deletes while
/// that call is in flight and the create then succeeds, the song exists on
/// the server and nothing local is ever left to delete it.
///
/// This is the planning-side fix's twin
/// (`planning_in_flight_create_cancellation_test.dart`), mirrored onto the
/// song/catalog domain. It drives the real `DriftSongCatalogStore`/
/// `DriftSongMutationStore` (not a hand-rolled fake), the same reasoning
/// `song_sync_snapshot_identity_test.dart` documents: the fix lives inside
/// the storage boundary and the service/controller wiring, not something a
/// fake could "pass" by encoding the desired behaviour directly.
void main() {
  suppressDriftMultipleDatabaseWarnings();

  group('In-flight create cancellation (D1/D2/D3, song/catalog)', () {
    test('deleting a pendingCreate song while its create is in flight '
        'survives as a pending delete once the create succeeds', () async {
      final env = _TestEnv();
      addTearDown(env.close);

      await env.service.createSong(
        context: env.context,
        title: 'Alpha',
        chordproSource: '{title: Alpha}',
      );

      final remote = _GatedSongRemote();
      final controller = SongMutationSyncController(
        store: env.mutationStore,
        remoteRepository: remote,
      );

      final syncFuture = controller.syncPendingSongs(env.songContext);

      // Wait until the remote call for the create has actually been
      // reached -- the create's send is genuinely in flight.
      await remote.entered.future;

      // The user deletes the song while that create is still in flight.
      await env.service.deleteSong(context: env.context, songId: 'song-1');

      // Release the gate: the create succeeds on the backend.
      remote.gate.complete();
      await syncFuture;

      final afterSync = await env.mutationStore.readById(
        userId: 'user-1',
        organizationId: 'org-1',
        songId: 'song-1',
      );

      expect(
        afterSync,
        isNotNull,
        reason:
            'the delete intent must survive -- the song now exists on the '
            'backend, and nothing will ever delete it if this row is lost',
      );
      expect(afterSync!.syncStatus, SongSyncStatus.pendingDelete);

      // The next sync sends the delete.
      await controller.syncPendingSongs(env.songContext);
      final deleteCalls = remote.calls.where(
        (record) => record.syncStatus == SongSyncStatus.pendingDelete,
      );
      expect(
        deleteCalls,
        hasLength(1),
        reason: 'the survived delete intent must actually be sent',
      );
    });

    test('when the in-flight create fails instead, the tombstone resolves '
        'locally and no delete is ever sent', () async {
      final env = _TestEnv();
      addTearDown(env.close);

      await env.service.createSong(
        context: env.context,
        title: 'Alpha',
        chordproSource: '{title: Alpha}',
      );

      final remote = _GatedSongRemote(
        failFirstWith: const SongMutationSyncException(
          SongMutationSyncErrorCode.authorizationDenied,
        ),
      );
      final controller = SongMutationSyncController(
        store: env.mutationStore,
        remoteRepository: remote,
      );

      final syncFuture = controller.syncPendingSongs(env.songContext);
      await remote.entered.future;

      await env.service.deleteSong(context: env.context, songId: 'song-1');

      remote.gate.complete();
      await syncFuture;

      final afterSync = await env.mutationStore.readById(
        userId: 'user-1',
        organizationId: 'org-1',
        songId: 'song-1',
      );
      expect(
        afterSync,
        isNull,
        reason:
            'the create never reached the backend, so the tombstone must '
            'resolve locally with no trace left -- exactly like a plain '
            'collapse',
      );

      await controller.syncPendingSongs(env.songContext);
      final deleteCalls = remote.calls.where(
        (record) => record.syncStatus == SongSyncStatus.pendingDelete,
      );
      expect(
        deleteCalls,
        isEmpty,
        reason:
            'a song that never existed remotely must never be sent a delete',
      );
    });

    test('no regression: deleting a pendingCreate song with no sync in '
        'flight still collapses physically (ADR-028 D10 unchanged)', () async {
      final env = _TestEnv();
      addTearDown(env.close);

      await env.service.createSong(
        context: env.context,
        title: 'Alpha',
        chordproSource: '{title: Alpha}',
      );

      await env.service.deleteSong(context: env.context, songId: 'song-1');

      final afterDelete = await env.mutationStore.readById(
        userId: 'user-1',
        organizationId: 'org-1',
        songId: 'song-1',
      );
      expect(
        afterDelete,
        isNull,
        reason:
            'no sync was ever in flight, so this must still be a plain '
            'physical collapse -- no tombstone',
      );
    });

    test('crash recovery: a record left `sending` is treated as pending on '
        'a fresh pass and resent', () async {
      final env = _TestEnv();
      addTearDown(env.close);

      final created = await env.service.createSong(
        context: env.context,
        title: 'Alpha',
        chordproSource: '{title: Alpha}',
      );

      // Simulate a crash that happened after a prior run durably wrote the
      // D1 `sending` marker but never got a response back: the record is
      // left `sending` with no in-flight call actually alive anymore.
      await env.mutationStore.upsertSong(
        userId: 'user-1',
        record: created.copyWith(syncStatus: SongSyncStatus.sending),
      );

      final remote = _GatedSongRemote();
      remote.gate.complete();
      final controller = SongMutationSyncController(
        store: env.mutationStore,
        remoteRepository: remote,
      );

      await controller.syncPendingSongs(env.songContext);

      expect(
        remote.calls,
        hasLength(1),
        reason:
            'a record left `sending` by a crash must be resent, not '
            'stranded forever',
      );
      expect(remote.calls.single.id, 'song-1');

      final afterSync = await env.mutationStore.readById(
        userId: 'user-1',
        organizationId: 'org-1',
        songId: 'song-1',
      );
      expect(
        afterSync!.syncStatus,
        SongSyncStatus.synced,
        reason:
            'once resent and accepted, it reconciles normally, exactly '
            'like an ordinary pending record',
      );
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

  Future<void> close() async {
    await planningDatabase.close();
    await songDatabase.close();
  }
}

/// Gates exactly the FIRST `syncSong` call on [gate], signalling [entered]
/// once that call has been reached (so a test can race a local write
/// against it deterministically). Every later call resolves immediately, so
/// a test can drive a second sync run (e.g. sending the delete a tombstone
/// resolved into) without re-gating.
class _GatedSongRemote implements SongMutationRemoteRepository {
  _GatedSongRemote({this.failFirstWith});

  /// If set, the gated first call throws this once released instead of
  /// succeeding.
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
      version: 1,
      baseVersion: 1,
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
