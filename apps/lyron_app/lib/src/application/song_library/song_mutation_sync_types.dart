import 'dart:math';

import 'package:lyron_app/src/offline/song_catalog/song_catalog_store.dart'
    show SongSyncStatus;

export 'package:lyron_app/src/offline/song_catalog/song_catalog_store.dart'
    show LocalSongSlugConflictException, SongSyncStatus;

enum SongMutationSyncErrorCode {
  authorizationDenied,
  conflict,
  dependencyBlocked,
  connectivityFailure,
  unknown,
}

class SongMutationSyncException implements Exception {
  const SongMutationSyncException(this.code, {this.message});

  final SongMutationSyncErrorCode code;
  final String? message;
}

class SongDeleteBlockedException implements Exception {
  const SongDeleteBlockedException(this.songId);

  final String songId;

  @override
  String toString() => 'SongDeleteBlockedException(songId: $songId)';
}

class SongConflictResolutionRequiredException implements Exception {
  const SongConflictResolutionRequiredException(this.songId);

  final String songId;

  @override
  String toString() =>
      'SongConflictResolutionRequiredException(songId: $songId)';
}

class SongMutationContext {
  const SongMutationContext({
    required this.userId,
    required this.organizationId,
  });

  final String userId;
  final String organizationId;
}

class SongMutationRecord {
  const SongMutationRecord({
    required this.id,
    required this.organizationId,
    required this.slug,
    required this.title,
    required this.chordproSource,
    required this.version,
    required this.baseVersion,
    required this.syncStatus,
    this.errorCode,
    this.errorMessage,
    this.conflictSourceSyncStatus,
  });

  final String id;
  final String organizationId;
  final String slug;
  final String title;
  final String chordproSource;
  final int version;
  final int? baseVersion;
  final SongSyncStatus syncStatus;
  final SongMutationSyncErrorCode? errorCode;
  final String? errorMessage;
  final SongSyncStatus? conflictSourceSyncStatus;

  SongMutationRecord copyWith({
    String? id,
    String? organizationId,
    String? slug,
    String? title,
    String? chordproSource,
    int? version,
    int? baseVersion,
    bool clearBaseVersion = false,
    SongSyncStatus? syncStatus,
    SongMutationSyncErrorCode? errorCode,
    bool clearErrorCode = false,
    String? errorMessage,
    bool clearErrorMessage = false,
    SongSyncStatus? conflictSourceSyncStatus,
    bool clearConflictSourceSyncStatus = false,
  }) {
    return SongMutationRecord(
      id: id ?? this.id,
      organizationId: organizationId ?? this.organizationId,
      slug: slug ?? this.slug,
      title: title ?? this.title,
      chordproSource: chordproSource ?? this.chordproSource,
      version: version ?? this.version,
      baseVersion: clearBaseVersion ? null : (baseVersion ?? this.baseVersion),
      syncStatus: syncStatus ?? this.syncStatus,
      errorCode: clearErrorCode ? null : (errorCode ?? this.errorCode),
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
      conflictSourceSyncStatus: clearConflictSourceSyncStatus
          ? null
          : (conflictSourceSyncStatus ?? this.conflictSourceSyncStatus),
    );
  }
}

abstract interface class SongMutationStore {
  Future<String> allocateUniqueSlug({
    required String userId,
    required String organizationId,
    required String title,
  });

  Future<void> upsertSong({
    required String userId,
    required SongMutationRecord record,
  });

  Future<SongMutationRecord?> readById({
    required String userId,
    required String organizationId,
    required String songId,
  });

  Future<List<SongMutationRecord>> readPendingSongs({
    required String userId,
    required String organizationId,
  });

  Future<List<SongMutationRecord>> readConflictSongs({
    required String userId,
    required String organizationId,
  });

  Future<void> saveSyncAttemptResult({
    required String userId,
    required String organizationId,
    required String songId,
    required SongSyncStatus syncStatus,
    SongMutationSyncErrorCode? errorCode,
    String? errorMessage,
  });

  Future<int> countReferencingSessionItems({
    required String userId,
    required String organizationId,
    required String songId,
  });

  Future<void> deleteSong({
    required String userId,
    required String organizationId,
    required String songId,
  });

  Future<void> reconcileSyncedSong({
    required String userId,
    required String organizationId,
    required SongMutationRecord record,
  });

  Future<void> clearSongMutation({
    required String userId,
    required String organizationId,
    required String songId,
  });

  Future<bool> hasUnsyncedChanges({required String userId});
}

abstract interface class SongMutationRemoteRepository {
  Future<SongMutationRecord> syncSong({
    required String organizationId,
    required SongMutationRecord record,
  });

  Future<SongMutationRecord> overwriteSong({
    required String organizationId,
    required SongMutationRecord record,
  });

  Future<SongMutationRecord> fetchSong({
    required String organizationId,
    required String songId,
  });
}

typedef SongIdGenerator = String Function();

String generateUuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;

  String hex(int value) => value.toRadixString(16).padLeft(2, '0');
  final values = bytes.map(hex).toList(growable: false);

  return '${values[0]}${values[1]}${values[2]}${values[3]}-'
      '${values[4]}${values[5]}-'
      '${values[6]}${values[7]}-'
      '${values[8]}${values[9]}-'
      '${values[10]}${values[11]}${values[12]}${values[13]}${values[14]}${values[15]}';
}
