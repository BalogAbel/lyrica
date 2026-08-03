import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_controller.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_types.dart';

void main() {
  group('SongMutationSyncController single-flight', () {
    test(
      'concurrent syncPendingSongs calls coalesce into a single remote send',
      () async {
        final gate = Completer<void>();
        var sendCount = 0;
        final store = _GatedSongMutationStore(
          pendingSongs: const [
            SongMutationRecord(
              id: 'song-1',
              organizationId: 'org-1',
              slug: 'alpha',
              title: 'Alpha',
              chordproSource: '{title: Alpha}',
              version: 3,
              baseVersion: 3,
              syncStatus: SongSyncStatus.pendingUpdate,
            ),
          ],
        );
        final repository = _GatedSongMutationRemoteRepository(
          onSend: () async {
            sendCount += 1;
            await gate.future;
          },
        );
        final controller = SongMutationSyncController(
          store: store,
          remoteRepository: repository,
        );
        const context = SongMutationContext(
          userId: 'user-1',
          organizationId: 'org-1',
        );

        final first = controller.syncPendingSongs(context);
        final second = controller.syncPendingSongs(context);

        gate.complete();
        await Future.wait([first, second]);

        expect(sendCount, 1);
        expect(identical(first, second), isTrue);
      },
    );

    test(
      'concurrent syncPendingSongs for different contexts do not coalesce',
      () async {
        // Regression for the gemini-review finding: the controller is an
        // app-scoped singleton, so a global in-flight future would make a sync
        // for org-2 reuse org-1's run and skip org-2's pending songs. Keying
        // the in-flight map by context must keep the two runs independent.
        final gate = Completer<void>();
        var sendCount = 0;
        final store = _GatedSongMutationStore(
          pendingSongs: const [
            SongMutationRecord(
              id: 'song-1',
              organizationId: 'org-1',
              slug: 'alpha',
              title: 'Alpha',
              chordproSource: '{title: Alpha}',
              version: 3,
              baseVersion: 3,
              syncStatus: SongSyncStatus.pendingUpdate,
            ),
          ],
        );
        final repository = _GatedSongMutationRemoteRepository(
          onSend: () async {
            sendCount += 1;
            await gate.future;
          },
        );
        final controller = SongMutationSyncController(
          store: store,
          remoteRepository: repository,
        );

        final first = controller.syncPendingSongs(
          const SongMutationContext(userId: 'user-1', organizationId: 'org-1'),
        );
        final second = controller.syncPendingSongs(
          const SongMutationContext(userId: 'user-1', organizationId: 'org-2'),
        );

        gate.complete();
        await Future.wait([first, second]);

        expect(sendCount, 2);
        expect(identical(first, second), isFalse);
      },
    );

    test(
      'discard is rejected and leaves the mutation unchanged after same-context sync owns the remote send',
      () async {
        const pendingSong = SongMutationRecord(
          id: 'song-1',
          organizationId: 'org-1',
          slug: 'alpha',
          title: 'Alpha',
          chordproSource: '{title: Alpha}',
          version: 3,
          baseVersion: 3,
          syncStatus: SongSyncStatus.pendingUpdate,
        );
        final remoteEntered = Completer<void>();
        final releaseRemote = Completer<void>();
        final store = _GatedSongMutationStore(
          pendingSongs: const [pendingSong],
        );
        final repository = _GatedSongMutationRemoteRepository(
          onSend: () async {
            remoteEntered.complete();
            await releaseRemote.future;
          },
        );
        final controller = SongMutationSyncController(
          store: store,
          remoteRepository: repository,
        );
        const context = SongMutationContext(
          userId: 'user-1',
          organizationId: 'org-1',
        );

        final sync = controller.syncPendingSongs(context);
        await remoteEntered.future;

        final result = await controller.discardMine(
          context,
          songId: pendingSong.id,
        );
        final mutationDuringRemote = await store.readById(
          userId: context.userId,
          organizationId: context.organizationId,
          songId: pendingSong.id,
        );

        releaseRemote.complete();
        await sync;

        expect(
          (
            result: result,
            mutationUnchanged: identical(mutationDuringRemote, pendingSong),
          ),
          (result: SongDiscardResult.syncInProgress, mutationUnchanged: true),
          reason: 'sync ownership must reject discard without changing data',
        );
      },
    );

    test(
      'sync ownership rejects discard of a second song already captured by the same context snapshot',
      () async {
        const secondSong = SongMutationRecord(
          id: 'song-2',
          organizationId: 'org-1',
          slug: 'beta',
          title: 'Beta',
          chordproSource: '{title: Beta}',
          version: 2,
          baseVersion: 2,
          syncStatus: SongSyncStatus.pendingUpdate,
        );
        final remoteEntered = Completer<void>();
        final releaseFirstSong = Completer<void>();
        var sendCount = 0;
        final store = _GatedSongMutationStore(
          pendingSongs: const [
            SongMutationRecord(
              id: 'song-1',
              organizationId: 'org-1',
              slug: 'alpha',
              title: 'Alpha',
              chordproSource: '{title: Alpha}',
              version: 3,
              baseVersion: 3,
              syncStatus: SongSyncStatus.pendingUpdate,
            ),
            secondSong,
          ],
        );
        final repository = _GatedSongMutationRemoteRepository(
          onSend: () async {
            sendCount += 1;
            if (sendCount == 1) {
              remoteEntered.complete();
              await releaseFirstSong.future;
            }
          },
        );
        final controller = SongMutationSyncController(
          store: store,
          remoteRepository: repository,
        );
        const context = SongMutationContext(
          userId: 'user-1',
          organizationId: 'org-1',
        );

        final sync = controller.syncPendingSongs(context);
        await remoteEntered.future;

        final result = await controller.discardMine(
          context,
          songId: secondSong.id,
        );
        final secondMutationDuringFirstSend = await store.readById(
          userId: context.userId,
          organizationId: context.organizationId,
          songId: secondSong.id,
        );

        releaseFirstSong.complete();
        await sync;

        expect(
          (
            result: result,
            mutationUnchanged: identical(
              secondMutationDuringFirstSend,
              secondSong,
            ),
          ),
          (result: SongDiscardResult.syncInProgress, mutationUnchanged: true),
          reason: 'the lease is context-wide, not only for the active row',
        );
      },
    );

    test(
      'sync started after discard waits to snapshot and never sends the discarded mutation',
      () async {
        final releaseDiscard = Completer<void>();
        final store = _GatedSongMutationStore(
          pendingSongs: const [
            SongMutationRecord(
              id: 'song-1',
              organizationId: 'org-1',
              slug: 'alpha',
              title: 'Alpha',
              chordproSource: '{title: Alpha}',
              version: 3,
              baseVersion: 3,
              syncStatus: SongSyncStatus.pendingUpdate,
            ),
          ],
          clearGate: releaseDiscard,
        );
        final repository = _GatedSongMutationRemoteRepository(
          onSend: () async {},
        );
        final controller = SongMutationSyncController(
          store: store,
          remoteRepository: repository,
        );
        const context = SongMutationContext(
          userId: 'user-1',
          organizationId: 'org-1',
        );

        final discard = controller.discardMine(context, songId: 'song-1');
        await store.clearEntered.future;

        final sync = controller.syncPendingSongs(context);
        final pendingReadsBeforeDiscardCompleted = store.pendingReadCount;

        releaseDiscard.complete();
        final discardResult = await discard;
        await sync;

        expect(
          (
            discardResult: discardResult,
            pendingReadsBeforeDiscardCompleted:
                pendingReadsBeforeDiscardCompleted,
            sentSongCount: repository.sentSongIds.length,
          ),
          (
            discardResult: SongDiscardResult.discarded,
            pendingReadsBeforeDiscardCompleted: 0,
            sentSongCount: 0,
          ),
          reason: 'sync must not snapshot while discard owns the context',
        );
      },
    );
  });
}

class _GatedSongMutationStore implements SongMutationStore {
  _GatedSongMutationStore({
    List<SongMutationRecord> pendingSongs = const [],
    this.clearGate,
  }) : _records = {for (final record in pendingSongs) record.id: record};

  final Map<String, SongMutationRecord> _records;
  final Completer<void>? clearGate;
  final Completer<void> clearEntered = Completer<void>();
  int pendingReadCount = 0;

  @override
  Future<SongMutationRecord?> readById({
    required String userId,
    required String organizationId,
    required String songId,
  }) async => _records[songId];

  @override
  Future<List<SongMutationRecord>> readConflictSongs({
    required String userId,
    required String organizationId,
  }) async => _records.values
      .where((record) => record.syncStatus == SongSyncStatus.conflict)
      .toList(growable: false);

  @override
  Future<List<SongMutationRecord>> readPendingSongs({
    required String userId,
    required String organizationId,
  }) async {
    pendingReadCount += 1;
    return _records.values
        .where(
          (record) => switch (record.syncStatus) {
            SongSyncStatus.pendingCreate ||
            SongSyncStatus.pendingUpdate ||
            SongSyncStatus.pendingDelete => true,
            SongSyncStatus.conflict || SongSyncStatus.synced => false,
          },
        )
        .toList(growable: false);
  }

  @override
  Future<void> saveSyncAttemptResult({
    required String userId,
    required String organizationId,
    required String songId,
    required SongSyncStatus syncStatus,
    SongMutationSyncErrorCode? errorCode,
    String? errorMessage,
  }) async {}

  @override
  Future<void> upsertSong({
    required String userId,
    required SongMutationRecord record,
  }) async {
    _records[record.id] = record;
  }

  @override
  Future<void> deleteSong({
    required String userId,
    required String organizationId,
    required String songId,
  }) async {
    _records.remove(songId);
  }

  @override
  Future<void> reconcileSyncedSong({
    required String userId,
    required String organizationId,
    required SongMutationRecord record,
  }) async {
    _records[record.id] = record;
  }

  @override
  Future<void> clearSongMutation({
    required String userId,
    required String organizationId,
    required String songId,
  }) async {
    if (!clearEntered.isCompleted) {
      clearEntered.complete();
    }
    await clearGate?.future;
    _records.remove(songId);
  }

  @override
  Future<bool> hasUnsyncedChanges({required String userId}) async => false;

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

class _GatedSongMutationRemoteRepository
    implements SongMutationRemoteRepository {
  _GatedSongMutationRemoteRepository({required this.onSend});

  final Future<void> Function() onSend;
  final List<String> sentSongIds = [];

  @override
  Future<SongMutationRecord> fetchSong({
    required String organizationId,
    required String songId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<SongMutationRecord> overwriteSong({
    required String organizationId,
    required SongMutationRecord record,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<SongMutationRecord> syncSong({
    required String organizationId,
    required SongMutationRecord record,
  }) async {
    sentSongIds.add(record.id);
    await onSend();
    return record.copyWith(syncStatus: SongSyncStatus.synced);
  }
}
