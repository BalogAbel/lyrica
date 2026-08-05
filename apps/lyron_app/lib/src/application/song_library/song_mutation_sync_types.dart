import 'dart:math';

import 'package:lyron_app/src/offline/song_catalog/song_catalog_store.dart'
    show SongSyncStatus;

export 'package:lyron_app/src/offline/song_catalog/song_catalog_store.dart'
    show LocalSongSlugConflictException, SongSyncStatus;

enum SongMutationSyncErrorCode {
  authorizationDenied,
  conflict,
  dependencyBlocked,
  remoteDeleted,
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
    this.localRevision = 0,
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

  /// Local bookkeeping only -- see `CachedCatalogSongMutations.localRevision`
  /// (`song_catalog_tables.dart`) for why this exists and why it is not OCC.
  /// Populated when a record is read back from storage; `0` for a record a
  /// caller is about to hand to `upsertSong` (the store computes the real
  /// value on write and callers never need to guess it) or for the synced
  /// fallback `readById` synthesizes when no mutation row exists.
  final int localRevision;

  SongSyncStatus get effectiveSyncStatus =>
      conflictSourceSyncStatus ?? syncStatus;

  bool get isRemoteDeletedConflict =>
      syncStatus == SongSyncStatus.conflict &&
      errorCode == SongMutationSyncErrorCode.remoteDeleted;

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
    int? localRevision,
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
      localRevision: localRevision ?? this.localRevision,
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

  /// Writes the outcome of a remote sync attempt onto the song's mutation
  /// row.
  ///
  /// Returns `true` if the row existed and was updated, or `false` if it
  /// did not (D4,
  /// `docs/specs/2026-08-06-in-flight-create-cancellation.md`: an ordinary
  /// concurrent-world outcome -- the user deleted a still-pending create
  /// while this exact remote attempt for it was in flight, and the
  /// collapse branch in `SongLibraryService.deleteSong` removed the row;
  /// not a defect). The caller must treat `false` the same as any other
  /// "did not apply" outcome: there is nothing left to write the status
  /// onto, and whatever else the sync pass was doing carries on.
  Future<bool> saveSyncAttemptResult({
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

  /// Concludes a successful sync: reconciles the cached snapshot with
  /// [record] and drops the song's mutation row.
  ///
  /// D2 (docs/specs/2026-08-05-sync-snapshot-identity.md): when
  /// [expectedRevision] is supplied, the whole reconcile -- including the
  /// snapshot update, not only the mutation-row delete -- applies only if
  /// the row's CURRENT `localRevision` still matches it, checked atomically
  /// inside the storage boundary (never a preceding read compared in Dart).
  /// Returns `true` if it applied, `false` if the row's revision had already
  /// moved (D3: not an error -- a local edit landed on this song during the
  /// remote round trip, and that edit already reset the row to pending with
  /// the newer content, so the next sync sends it). Omitting
  /// [expectedRevision] always applies unconditionally (and returns `true`),
  /// matching this method's shape before the D2 gate existed.
  Future<bool> reconcileSyncedSong({
    required String userId,
    required String organizationId,
    required SongMutationRecord record,
    int? expectedRevision,
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
