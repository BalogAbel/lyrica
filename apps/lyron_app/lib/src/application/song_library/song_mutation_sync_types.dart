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
  /// Returns `true` if the row existed AND (when [expectedRevision] is
  /// supplied) its `localRevision` still matched it, or `false` if either
  /// condition failed:
  /// - D4 (`docs/specs/2026-08-06-in-flight-create-cancellation.md`): the
  ///   row is gone -- an ordinary concurrent-world outcome (the user deleted
  ///   a still-pending create while this exact remote attempt for it was in
  ///   flight, and the collapse branch in `SongLibraryService.deleteSong`
  ///   removed the row), not a defect;
  /// - Finding B (PR #64 review, 2026-08-06 remediation round): the row's
  ///   revision has already moved past [expectedRevision] -- a local edit
  ///   landed on this song during the remote round trip and reset the row
  ///   to a pending status with newer, never-sent content. Gated the same
  ///   way as `reconcileSyncedSong`/`markSongCreateSending` (D2 of
  ///   `docs/specs/2026-08-05-sync-snapshot-identity.md`): the condition is
  ///   the WHERE clause of a single UPDATE, never a preceding SELECT
  ///   compared in Dart.
  ///
  /// The caller must treat `false` the same as any other "did not apply"
  /// outcome either way: there is nothing left to write the status onto (or
  /// the row is already exactly where the concurrent write left it), and
  /// whatever else the sync pass was doing carries on. Omitting
  /// [expectedRevision] always applies unconditionally (the shape every
  /// caller used before this parameter existed, still used by callers that
  /// never captured a pre-send snapshot revision to gate against, e.g.
  /// `SongMutationSyncController.keepMine`).
  Future<bool> saveSyncAttemptResult({
    required String userId,
    required String organizationId,
    required String songId,
    required SongSyncStatus syncStatus,
    SongMutationSyncErrorCode? errorCode,
    String? errorMessage,
    int? expectedRevision,
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

  /// D1 (docs/specs/2026-08-06-in-flight-create-cancellation.md): durably
  /// marks a still-local (`pendingCreate`) song `sending` immediately
  /// before its remote create attempt. See
  /// `SongCatalogStore.markSongCreateSending` for the full contract and for
  /// why this is scoped to creates only, unlike planning's equivalent
  /// marker (written before every mutation kind's send).
  ///
  /// Returns the row's new `localRevision` if it applied, or `null` if it
  /// did not -- either because the row no longer exists (D4) or because
  /// [expectedRevision] no longer matched (D3: not an error, a local edit
  /// or delete landed on this song since the caller's snapshot).
  Future<int?> markCreateSending({
    required String userId,
    required String organizationId,
    required String songId,
    required int expectedRevision,
  });

  /// D3 (docs/specs/2026-08-06-in-flight-create-cancellation.md): resolves
  /// the outcome of an in-flight `pendingCreate` song whose row may have
  /// become a D2 cancellation tombstone while its remote create was in
  /// flight. See `SongCatalogStore.resolveCancelledSongCreate` for the full
  /// contract.
  ///
  /// Returns `true` if a tombstone was found and resolved, `false`
  /// otherwise (nothing to do -- see the store-level contract for why).
  Future<bool> resolveCancelledSongCreate({
    required String userId,
    required String organizationId,
    required String songId,
    required bool created,
    int? acceptedVersion,
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
