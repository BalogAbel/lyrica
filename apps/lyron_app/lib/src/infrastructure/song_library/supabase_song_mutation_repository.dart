import 'dart:io';

import 'package:lyron_app/src/application/song_library/song_mutation_sync_types.dart';
import 'package:lyron_app/src/shared/connectivity_failure.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseSongMutationRemoteRepository
    implements SongMutationRemoteRepository {
  const SupabaseSongMutationRemoteRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<SongMutationRecord> fetchSong({
    required String organizationId,
    required String songId,
  }) async {
    try {
      final row = await _client
          .from('songs')
          .select('id, organization_id, slug, title, chordpro_source, version')
          .eq('organization_id', organizationId)
          .eq('id', songId)
          .maybeSingle();
      if (row == null) {
        throw const SongMutationSyncException(
          SongMutationSyncErrorCode.unknown,
        );
      }

      return _mapRow(Map<String, dynamic>.from(row));
    } on Object catch (error) {
      throw _mapError(error);
    }
  }

  @override
  Future<SongMutationRecord> overwriteSong({
    required String organizationId,
    required SongMutationRecord record,
  }) {
    return _sync(
      organizationId: organizationId,
      record: record,
      overwrite: true,
    );
  }

  @override
  Future<SongMutationRecord> syncSong({
    required String organizationId,
    required SongMutationRecord record,
  }) {
    return _sync(
      organizationId: organizationId,
      record: record,
      overwrite: false,
    );
  }

  Future<SongMutationRecord> _sync({
    required String organizationId,
    required SongMutationRecord record,
    required bool overwrite,
  }) async {
    try {
      final effectiveSyncStatus = record.syncStatus == SongSyncStatus.conflict
          ? (record.conflictSourceSyncStatus ?? SongSyncStatus.pendingUpdate)
          : record.syncStatus;
      final rpcName = switch (record.syncStatus) {
        SongSyncStatus.pendingCreate => 'create_song',
        SongSyncStatus.pendingUpdate =>
          overwrite ? 'overwrite_song_update' : 'update_song',
        SongSyncStatus.pendingDelete =>
          overwrite ? 'overwrite_song_delete' : 'delete_song',
        SongSyncStatus.conflict =>
          overwrite
              ? (effectiveSyncStatus == SongSyncStatus.pendingDelete
                    ? 'overwrite_song_delete'
                    : 'overwrite_song_update')
              : (effectiveSyncStatus == SongSyncStatus.pendingDelete
                    ? 'delete_song'
                    : 'update_song'),
        SongSyncStatus.synced => throw StateError(
          'Synced songs do not need sync',
        ),
      };

      final params = <String, dynamic>{
        'p_organization_id': organizationId,
        if (effectiveSyncStatus == SongSyncStatus.pendingCreate) ...{
          'p_song_id': record.id,
          'p_title': record.title,
          'p_chordpro_source': record.chordproSource,
          'p_requested_slug': record.slug,
        } else ...{
          'p_song_id': record.id,
          'p_base_version': record.baseVersion,
        },
        if (effectiveSyncStatus != SongSyncStatus.pendingDelete &&
            effectiveSyncStatus != SongSyncStatus.synced) ...{
          'p_title': record.title,
          'p_chordpro_source': record.chordproSource,
        },
      };

      final response = await _client.rpc(rpcName, params: params);
      return _mapRow(Map<String, dynamic>.from(response as Map));
    } on Object catch (error) {
      throw _mapError(error);
    }
  }

  SongMutationRecord _mapRow(Map<String, dynamic> row) {
    return SongMutationRecord(
      id: row['id'] as String,
      organizationId: row['organization_id'] as String,
      slug: row['slug'] as String,
      title: row['title'] as String,
      chordproSource: row['chordpro_source'] as String? ?? '',
      version: (row['version'] as num?)?.toInt() ?? 1,
      baseVersion: (row['version'] as num?)?.toInt() ?? 1,
      syncStatus: SongSyncStatus.synced,
    );
  }

  SongMutationSyncException _mapError(Object error) {
    if (error is SongMutationSyncException) {
      return error;
    }
    if (isConnectivityFailure(error) || error is SocketException) {
      return const SongMutationSyncException(
        SongMutationSyncErrorCode.connectivityFailure,
      );
    }
    if (error is PostgrestException) {
      final message = error.message.toLowerCase();
      if (error.code == '42501' ||
          message.contains('song_write_not_authorized')) {
        return SongMutationSyncException(
          SongMutationSyncErrorCode.authorizationDenied,
          message: error.message,
        );
      }
      if (error.code == '23503' ||
          message.contains('song_delete_blocked_by_session_items')) {
        return SongMutationSyncException(
          SongMutationSyncErrorCode.dependencyBlocked,
          message: error.message,
        );
      }
      if (error.code == 'P0001' || message.contains('song_version_conflict')) {
        return SongMutationSyncException(
          SongMutationSyncErrorCode.conflict,
          message: error.message,
        );
      }
    }

    return SongMutationSyncException(
      SongMutationSyncErrorCode.unknown,
      message: error.toString(),
    );
  }
}
