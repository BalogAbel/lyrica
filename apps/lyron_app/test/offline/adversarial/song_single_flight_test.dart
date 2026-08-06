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

    for (final unrelatedContext in const [
      SongMutationContext(userId: 'user-2', organizationId: 'org-1'),
      SongMutationContext(userId: 'user-1', organizationId: 'org-2'),
    ]) {
      test(
        'held sync user-1/org-1 allows discard for '
        '${unrelatedContext.userId}/${unrelatedContext.organizationId}',
        () async {
          const syncContext = SongMutationContext(
            userId: 'user-1',
            organizationId: 'org-1',
          );
          const syncSong = SongMutationRecord(
            id: 'sync-song',
            organizationId: 'org-1',
            slug: 'sync-song',
            title: 'Sync Song',
            chordproSource: '{title: Sync Song}',
            version: 3,
            baseVersion: 3,
            syncStatus: SongSyncStatus.pendingUpdate,
          );
          final discardSong = SongMutationRecord(
            id: 'discard-song',
            organizationId: unrelatedContext.organizationId,
            slug: 'discard-song',
            title: 'Discard Song',
            chordproSource: '{title: Discard Song}',
            version: 2,
            baseVersion: 2,
            syncStatus: SongSyncStatus.pendingUpdate,
          );
          final remoteEntered = Completer<void>();
          final releaseRemote = Completer<void>();
          final store = _GatedSongMutationStore(
            pendingSongs: [syncSong, discardSong],
            recordContexts: {
              syncSong.id: (
                userId: syncContext.userId,
                organizationId: syncContext.organizationId,
              ),
              discardSong.id: (
                userId: unrelatedContext.userId,
                organizationId: unrelatedContext.organizationId,
              ),
            },
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

          final sync = controller.syncPendingSongs(syncContext);
          await remoteEntered.future;

          final result = await controller.discardMine(
            unrelatedContext,
            songId: discardSong.id,
          );
          final discardedRecord = await store.readById(
            userId: unrelatedContext.userId,
            organizationId: unrelatedContext.organizationId,
            songId: discardSong.id,
          );

          releaseRemote.complete();
          await sync;

          expect(
            (result: result, removed: discardedRecord == null),
            (result: SongDiscardResult.discarded, removed: true),
            reason:
                'ownership must include both user and organization dimensions',
          );
        },
      );
    }

    test(
      'same-context sync calls queued behind discard share one Future and run',
      () async {
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
        final acquisition = await controller.acquireDiscardLease(context);
        final lease = acquisition.lease!;

        final first = controller.syncPendingSongs(context);
        final second = controller.syncPendingSongs(context);

        try {
          expect(store.pendingReadCount, 0);
          expect(
            identical(first, second),
            isTrue,
            reason: 'one queued sync Future must represent the discard owner',
          );
        } finally {
          lease.release();
          await Future.wait([first, second]);
        }

        expect(
          (
            pendingReadCount: store.pendingReadCount,
            sentSongCount: repository.sentSongIds.length,
          ),
          (pendingReadCount: 1, sentSongCount: 1),
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
    Map<String, ({String userId, String organizationId})> recordContexts =
        const {},
  }) : _records = {for (final record in pendingSongs) record.id: record},
       _recordContexts = recordContexts;

  final Map<String, SongMutationRecord> _records;
  final Map<String, ({String userId, String organizationId})> _recordContexts;
  final Completer<void>? clearGate;
  final Completer<void> clearEntered = Completer<void>();
  int pendingReadCount = 0;

  bool _belongsToContext(
    SongMutationRecord record, {
    required String userId,
    required String organizationId,
  }) {
    final context = _recordContexts[record.id];
    return context == null ||
        (context.userId == userId && context.organizationId == organizationId);
  }

  @override
  Future<SongMutationRecord?> readById({
    required String userId,
    required String organizationId,
    required String songId,
  }) async {
    final record = _records[songId];
    if (record == null ||
        !_belongsToContext(
          record,
          userId: userId,
          organizationId: organizationId,
        )) {
      return null;
    }
    return record;
  }

  @override
  Future<List<SongMutationRecord>> readConflictSongs({
    required String userId,
    required String organizationId,
  }) async => _records.values
      .where(
        (record) =>
            _belongsToContext(
              record,
              userId: userId,
              organizationId: organizationId,
            ) &&
            record.syncStatus == SongSyncStatus.conflict,
      )
      .toList(growable: false);

  @override
  Future<List<SongMutationRecord>> readPendingSongs({
    required String userId,
    required String organizationId,
  }) async {
    pendingReadCount += 1;
    return _records.values
        .where(
          (record) =>
              _belongsToContext(
                record,
                userId: userId,
                organizationId: organizationId,
              ) &&
              switch (record.syncStatus) {
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
  }

  @override
  Future<bool> saveSyncAttemptResult({
    required String userId,
    required String organizationId,
    required String songId,
    required SongSyncStatus syncStatus,
    SongMutationSyncErrorCode? errorCode,
    String? errorMessage,
    int? expectedRevision,
  }) async => true;

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
  Future<bool> reconcileSyncedSong({
    required String userId,
    required String organizationId,
    required SongMutationRecord record,
    int? expectedRevision,
  }) async {
    _records[record.id] = record;
    return true;
  }

  // docs/specs/2026-08-06-in-flight-create-cancellation.md (D1/D3): none of
  // the single-flight tests in this file drive a pendingCreate song through
  // syncPendingSongs -- that race is covered against the real
  // DriftSongCatalogStore/DriftSongMutationStore in
  // test/offline/adversarial/song_in_flight_create_cancellation_test.dart.
  // Applied unconditionally, ignoring expectedRevision, like
  // reconcileSyncedSong above.
  @override
  Future<int?> markCreateSending({
    required String userId,
    required String organizationId,
    required String songId,
    required int expectedRevision,
  }) async {
    final existing = _records[songId];
    if (existing == null) return null;
    final updated = existing.copyWith(syncStatus: SongSyncStatus.sending);
    _records[songId] = updated;
    return updated.localRevision;
  }

  @override
  Future<bool> resolveCancelledSongCreate({
    required String userId,
    required String organizationId,
    required String songId,
    required bool created,
    int? acceptedVersion,
  }) async {
    final existing = _records[songId];
    if (existing == null || existing.syncStatus != SongSyncStatus.cancelling) {
      return false;
    }
    if (!created) {
      _records.remove(songId);
    } else {
      _records[songId] = existing.copyWith(
        syncStatus: SongSyncStatus.pendingDelete,
        baseVersion: acceptedVersion ?? existing.baseVersion,
      );
    }
    return true;
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
