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
  });
}

class _GatedSongMutationStore implements SongMutationStore {
  _GatedSongMutationStore({List<SongMutationRecord> pendingSongs = const []})
    : _records = {for (final record in pendingSongs) record.id: record};

  final Map<String, SongMutationRecord> _records;

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
  }) async => _records.values
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

class _GatedSongMutationRemoteRepository implements SongMutationRemoteRepository {
  _GatedSongMutationRemoteRepository({required this.onSend});

  final Future<void> Function() onSend;

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
    await onSend();
    return record.copyWith(syncStatus: SongSyncStatus.synced);
  }
}
