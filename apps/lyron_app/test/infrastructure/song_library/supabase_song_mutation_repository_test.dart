import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_types.dart';
import 'package:lyron_app/src/infrastructure/song_library/supabase_song_mutation_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('maps song_not_found write failures to remote-deleted classification', () async {
    final repository = SupabaseSongMutationRemoteRepository.testing(
      rpc: (name, {params}) async {
        throw const PostgrestException(
          message: 'song_not_found',
          code: 'P0002',
        );
      },
      fetchSongRow: (organizationId, songId) async => null,
    );

    await expectLater(
      () => repository.syncSong(
        organizationId: 'org-1',
        record: const SongMutationRecord(
          id: 'song-1',
          organizationId: 'org-1',
          slug: 'alpha',
          title: 'Alpha',
          chordproSource: '{title: Alpha}',
          version: 2,
          baseVersion: 2,
          syncStatus: SongSyncStatus.pendingUpdate,
        ),
      ),
      throwsA(
        isA<SongMutationSyncException>().having(
          (error) => error.code,
          'code',
          SongMutationSyncErrorCode.remoteDeleted,
        ),
      ),
    );
  });

  test('maps missing fetch row to remote-deleted classification', () async {
    final repository = SupabaseSongMutationRemoteRepository.testing(
      rpc: (name, {params}) async => throw UnimplementedError(),
      fetchSongRow: (organizationId, songId) async => null,
    );

    await expectLater(
      () => repository.fetchSong(
        organizationId: 'org-1',
        songId: 'song-1',
      ),
      throwsA(
        isA<SongMutationSyncException>().having(
          (error) => error.code,
          'code',
          SongMutationSyncErrorCode.remoteDeleted,
        ),
      ),
    );
  });

  test('routes update-sourced remote-delete keep-mine to same-id create_song rpc', () async {
    late String rpcName;
    late Map<String, dynamic> rpcParams;
    final repository = SupabaseSongMutationRemoteRepository.testing(
      rpc: (name, {params}) async {
        rpcName = name;
        rpcParams = params ?? const {};
        return {
          'id': 'song-1',
          'organization_id': 'org-1',
          'slug': 'alpha-2',
          'title': 'Alpha',
          'chordpro_source': '{title: Alpha}',
          'version': 1,
        };
      },
      fetchSongRow: (organizationId, songId) async => null,
    );

    final result = await repository.overwriteSong(
      organizationId: 'org-1',
      record: const SongMutationRecord(
        id: 'song-1',
        organizationId: 'org-1',
        slug: 'alpha',
        title: 'Alpha',
        chordproSource: '{title: Alpha}',
        version: 2,
        baseVersion: 2,
        syncStatus: SongSyncStatus.conflict,
        errorCode: SongMutationSyncErrorCode.remoteDeleted,
        conflictSourceSyncStatus: SongSyncStatus.pendingUpdate,
      ),
    );

    expect(rpcName, 'create_song');
    expect(rpcParams['p_song_id'], 'song-1');
    expect(rpcParams['p_requested_slug'], 'alpha');
    expect(result.id, 'song-1');
    expect(result.slug, 'alpha-2');
    expect(result.syncStatus, SongSyncStatus.synced);
  });
}
