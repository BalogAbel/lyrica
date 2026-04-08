import 'dart:convert';

import 'package:lyron_app/src/application/song_library/song_mutation_sync_types.dart';
import 'package:lyron_app/src/domain/song/song_source.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_store.dart';

class DriftSongMutationStore implements SongMutationStore {
  const DriftSongMutationStore({
    required SongCatalogStore songCatalogStore,
    required PlanningLocalStore planningLocalStore,
  }) : _songCatalogStore = songCatalogStore,
       _planningLocalStore = planningLocalStore;

  final SongCatalogStore _songCatalogStore;
  final PlanningLocalStore _planningLocalStore;

  @override
  Future<String> allocateUniqueSlug({
    required String userId,
    required String organizationId,
    required String title,
  }) {
    return _songCatalogStore.allocateAvailableSongSlug(
      userId: userId,
      organizationId: organizationId,
      title: title,
    );
  }

  @override
  Future<int> countReferencingSessionItems({
    required String userId,
    required String organizationId,
    required String songId,
  }) {
    return _planningLocalStore.countSongReferences(
      userId: userId,
      organizationId: organizationId,
      songId: songId,
    );
  }

  @override
  Future<void> deleteSong({
    required String userId,
    required String organizationId,
    required String songId,
  }) {
    return _songCatalogStore.deleteSong(
      userId: userId,
      organizationId: organizationId,
      songId: songId,
    );
  }

  @override
  Future<void> reconcileSyncedSong({
    required String userId,
    required String organizationId,
    required SongMutationRecord record,
  }) {
    return _songCatalogStore.reconcileSyncedSong(
      userId: userId,
      organizationId: organizationId,
      summary: SongSummary(
        id: record.id,
        slug: record.slug,
        title: record.title,
        version: record.version,
      ),
      source: SongSource(id: record.id, source: record.chordproSource),
    );
  }

  @override
  Future<void> clearSongMutation({
    required String userId,
    required String organizationId,
    required String songId,
  }) {
    return _songCatalogStore.clearSongMutation(
      userId: userId,
      organizationId: organizationId,
      songId: songId,
    );
  }

  @override
  Future<bool> hasUnsyncedChanges({required String userId}) {
    return _songCatalogStore.hasUnsyncedSongMutations(userId: userId);
  }

  @override
  Future<SongMutationRecord?> readById({
    required String userId,
    required String organizationId,
    required String songId,
  }) async {
    final mutation = await _songCatalogStore.readSongMutationBySongId(
      userId: userId,
      organizationId: organizationId,
      songId: songId,
    );
    if (mutation != null) {
      return _toRecord(mutation);
    }

    final summary = await _songCatalogStore.readActiveSummaryById(
      userId: userId,
      organizationId: organizationId,
      songId: songId,
    );
    if (summary == null) {
      return null;
    }

    final source = await _songCatalogStore.readActiveSource(
      userId: userId,
      organizationId: organizationId,
      songId: songId,
    );
    if (source == null) {
      return null;
    }

    return SongMutationRecord(
      id: summary.id,
      organizationId: organizationId,
      slug: summary.slug,
      title: summary.title,
      chordproSource: source.source,
      version: summary.version,
      baseVersion: summary.version,
      syncStatus: SongSyncStatus.synced,
    );
  }

  @override
  Future<List<SongMutationRecord>> readConflictSongs({
    required String userId,
    required String organizationId,
  }) async {
    final rows = await _songCatalogStore.readSongMutations(
      userId: userId,
      organizationId: organizationId,
      syncStatuses: const [SongSyncStatus.conflict],
    );
    return rows.map(_toRecord).toList(growable: false);
  }

  @override
  Future<List<SongMutationRecord>> readPendingSongs({
    required String userId,
    required String organizationId,
  }) async {
    final rows = await _songCatalogStore.readSongMutations(
      userId: userId,
      organizationId: organizationId,
      syncStatuses: const [
        SongSyncStatus.pendingCreate,
        SongSyncStatus.pendingUpdate,
        SongSyncStatus.pendingDelete,
      ],
    );
    return rows.map(_toRecord).toList(growable: false);
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
    final existing = await readById(
      userId: userId,
      organizationId: organizationId,
      songId: songId,
    );
    if (existing == null) {
      throw StateError('Song mutation record not found: $songId');
    }

    await upsertSong(
      userId: userId,
      record: existing.copyWith(
        syncStatus: syncStatus,
        errorCode: errorCode,
        errorMessage: errorMessage,
        conflictSourceSyncStatus: syncStatus == SongSyncStatus.conflict
            ? existing.syncStatus
            : null,
        clearConflictSourceSyncStatus: syncStatus != SongSyncStatus.conflict,
      ),
    );
  }

  @override
  Future<void> upsertSong({
    required String userId,
    required SongMutationRecord record,
  }) async {
    try {
      await _songCatalogStore.saveSongMutation(
        SongCatalogMutationDraft(
          userId: userId,
          organizationId: record.organizationId,
          songId: record.id,
          slug: record.slug,
          title: record.title,
          source: record.chordproSource,
          version: record.version,
          syncStatus: record.syncStatus,
          baseVersion: record.baseVersion,
          syncErrorContext: _encodeError(
            code: record.errorCode,
            message: record.errorMessage,
            conflictSourceSyncStatus: record.conflictSourceSyncStatus,
          ),
        ),
      );
    } on Object catch (error) {
      if (_isLocalSlugUniquenessViolation(error)) {
        throw const LocalSongSlugConflictException();
      }
      rethrow;
    }
  }

  static bool _isLocalSlugUniquenessViolation(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('local song slug is already reserved') ||
        message.contains('unique constraint');
  }

  SongMutationRecord _toRecord(CachedCatalogSongMutation row) {
    final error = _decodeError(row.syncErrorContext);
    return SongMutationRecord(
      id: row.songId,
      organizationId: row.organizationId,
      slug: row.slug,
      title: row.title,
      chordproSource: row.source,
      version: row.version,
      baseVersion: row.baseVersion,
      syncStatus: _fromStoreStatus(row.syncStatus),
      errorCode: error.$1,
      errorMessage: error.$2,
      conflictSourceSyncStatus: error.$3,
    );
  }

  SongSyncStatus _fromStoreStatus(String value) {
    return switch (value) {
      'pending_create' => SongSyncStatus.pendingCreate,
      'pending_update' => SongSyncStatus.pendingUpdate,
      'pending_delete' => SongSyncStatus.pendingDelete,
      'synced' => SongSyncStatus.synced,
      'conflict' => SongSyncStatus.conflict,
      _ => throw ArgumentError.value(
        value,
        'value',
        'Unknown song sync status',
      ),
    };
  }

  String? _encodeError({
    SongMutationSyncErrorCode? code,
    String? message,
    SongSyncStatus? conflictSourceSyncStatus,
  }) {
    if (code == null && message == null && conflictSourceSyncStatus == null) {
      return null;
    }
    final payload = <String, String>{};
    if (code != null) {
      payload['code'] = code.name;
    }
    if (message != null) {
      payload['message'] = message;
    }
    if (conflictSourceSyncStatus != null) {
      payload['conflictSourceSyncStatus'] = conflictSourceSyncStatus.value;
    }
    return jsonEncode(payload);
  }

  (SongMutationSyncErrorCode?, String?, SongSyncStatus?) _decodeError(
    String? value,
  ) {
    if (value == null || value.isEmpty) {
      return (null, null, null);
    }

    final decoded = jsonDecode(value);
    if (decoded is! Map<String, dynamic>) {
      return (null, value, null);
    }

    final codeName = decoded['code'] as String?;
    final message = decoded['message'] as String?;
    final conflictSourceSyncStatusValue =
        decoded['conflictSourceSyncStatus'] as String?;
    final code = codeName == null
        ? null
        : SongMutationSyncErrorCode.values.firstWhere(
            (candidate) => candidate.name == codeName,
            orElse: () => SongMutationSyncErrorCode.unknown,
          );
    final conflictSourceSyncStatus = conflictSourceSyncStatusValue == null
        ? null
        : _fromStoreStatus(conflictSourceSyncStatusValue);
    return (code, message, conflictSourceSyncStatus);
  }
}
