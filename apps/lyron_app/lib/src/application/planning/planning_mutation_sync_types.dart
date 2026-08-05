import 'dart:math';

import 'package:lyron_app/src/application/storage/local_storage_domain_rejection.dart';

enum PlanningMutationKind {
  planCreate,
  planEdit,
  sessionCreate,
  sessionRename,
  sessionDelete,
  sessionReorder,
  sessionItemCreateSong,
  sessionItemDelete,
  sessionItemReorder,
}

enum PlanningMutationSyncStatus {
  pending,
  accepted,

  /// D1 (`docs/specs/2026-08-06-in-flight-create-cancellation.md`): written
  /// durably to the record immediately BEFORE the remote call, mirroring the
  /// `accepted` marker ADR-019 already writes immediately after it. Between
  /// those two writes the record is known to be in flight.
  ///
  /// Crash semantics, and why this does not weaken ADR-019: a record left
  /// `sending` by a crash may or may not have reached the backend -- exactly
  /// the uncertainty the `accepted` marker exists to bound. On restart a
  /// `sending` record is treated as pending and resent (see the candidate
  /// filter in `PlanningMutationSyncController._run`), which is the
  /// direction ADR-019 already accepts for a crash before acceptance: the
  /// marker narrows the in-flight window, it does not widen it.
  sending,

  /// D2 (`docs/specs/2026-08-06-in-flight-create-cancellation.md`): what a
  /// `sessionCreate`/`sessionItemCreateSong` row becomes when it is deleted
  /// while `sending` -- a cancellation tombstone, kept instead of physically
  /// collapsed, because the create may already have reached the backend and
  /// the delete intent would otherwise have no local trace once it does.
  ///
  /// The `kind` field is left untouched (still the *Create kind) so
  /// `PlanningMutationSyncController._run` can recognise which delete-kind
  /// to convert it to (D3) once the in-flight create's outcome is known --
  /// see `DriftPlanningMutationStore.resolveCancelledCreate`. Deliberately
  /// excluded from `_run`'s candidate filter (nothing to send until that
  /// outcome resolves it) and from `readActionableMutations` (the user
  /// deleted it; it must not render as an existing session/item while its
  /// fate is undecided).
  cancelling,

  failedAuthorization,
  failedDependency,
  failedRemoteDelete,
  conflict,
}

enum PlanningMutationSyncErrorCode {
  authorizationDenied,
  conflict,
  dependencyBlocked,
  remoteMissing,
  connectivityFailure,
  unknown,
}

extension PlanningMutationKindX on PlanningMutationKind {
  String get value => switch (this) {
    PlanningMutationKind.planCreate => 'plan_create',
    PlanningMutationKind.planEdit => 'plan_edit',
    PlanningMutationKind.sessionCreate => 'session_create',
    PlanningMutationKind.sessionRename => 'session_rename',
    PlanningMutationKind.sessionDelete => 'session_delete',
    PlanningMutationKind.sessionReorder => 'session_reorder',
    PlanningMutationKind.sessionItemCreateSong => 'session_item_create_song',
    PlanningMutationKind.sessionItemDelete => 'session_item_delete',
    PlanningMutationKind.sessionItemReorder => 'session_item_reorder',
  };

  String get aggregateType => switch (this) {
    PlanningMutationKind.planCreate || PlanningMutationKind.planEdit => 'plan',
    PlanningMutationKind.sessionCreate ||
    PlanningMutationKind.sessionRename ||
    PlanningMutationKind.sessionDelete => 'session',
    PlanningMutationKind.sessionReorder => 'session_order',
    PlanningMutationKind.sessionItemCreateSong ||
    PlanningMutationKind.sessionItemDelete => 'session_item',
    PlanningMutationKind.sessionItemReorder => 'session_item_order',
  };
}

extension PlanningMutationSyncStatusX on PlanningMutationSyncStatus {
  String get value => switch (this) {
    PlanningMutationSyncStatus.pending => 'pending',
    PlanningMutationSyncStatus.accepted => 'accepted',
    PlanningMutationSyncStatus.sending => 'sending',
    PlanningMutationSyncStatus.cancelling => 'cancelling',
    PlanningMutationSyncStatus.failedAuthorization => 'failed_authorization',
    PlanningMutationSyncStatus.failedDependency => 'failed_dependency',
    PlanningMutationSyncStatus.failedRemoteDelete => 'failed_remote_delete',
    PlanningMutationSyncStatus.conflict => 'conflict',
  };
}

PlanningMutationKind planningMutationKindFromValue(String value) {
  return switch (value) {
    'plan_create' => PlanningMutationKind.planCreate,
    'plan_edit' => PlanningMutationKind.planEdit,
    'session_create' => PlanningMutationKind.sessionCreate,
    'session_rename' => PlanningMutationKind.sessionRename,
    'session_delete' => PlanningMutationKind.sessionDelete,
    'session_reorder' => PlanningMutationKind.sessionReorder,
    'session_item_create_song' => PlanningMutationKind.sessionItemCreateSong,
    'session_item_delete' => PlanningMutationKind.sessionItemDelete,
    'session_item_reorder' => PlanningMutationKind.sessionItemReorder,
    _ => throw ArgumentError.value(
      value,
      'value',
      'Unknown planning mutation kind',
    ),
  };
}

PlanningMutationSyncStatus planningMutationSyncStatusFromValue(String value) {
  return switch (value) {
    'pending' => PlanningMutationSyncStatus.pending,
    'accepted' => PlanningMutationSyncStatus.accepted,
    'sending' => PlanningMutationSyncStatus.sending,
    'cancelling' => PlanningMutationSyncStatus.cancelling,
    'failed_authorization' => PlanningMutationSyncStatus.failedAuthorization,
    'failed_dependency' => PlanningMutationSyncStatus.failedDependency,
    'failed_remote_delete' => PlanningMutationSyncStatus.failedRemoteDelete,
    'conflict' => PlanningMutationSyncStatus.conflict,
    _ => throw ArgumentError.value(
      value,
      'value',
      'Unknown planning mutation sync status',
    ),
  };
}

class LocalPlanningSlugConflictException
    implements LocalStorageDomainRejection {
  const LocalPlanningSlugConflictException();

  @override
  String toString() => 'LocalPlanningSlugConflictException()';
}

/// Thrown when a new planning mutation would push the local mutation store
/// past its byte budget (LF-T3).
///
/// The remedy is to sync or discard pending work: catalog eviction cannot
/// free mutation budget, because pending mutations are never evictable.
class PlanningMutationBudgetExceededException implements Exception {
  const PlanningMutationBudgetExceededException({
    required this.mutationBytes,
    required this.refuseBytes,
  });

  final int mutationBytes;
  final int refuseBytes;

  @override
  String toString() =>
      'PlanningMutationBudgetExceededException('
      'mutationBytes: $mutationBytes, refuseBytes: $refuseBytes)';
}

class PlanningMutationSyncException implements Exception {
  const PlanningMutationSyncException(this.code, {this.message});

  final PlanningMutationSyncErrorCode code;
  final String? message;
}

class PlanningMutationContext {
  const PlanningMutationContext({
    required this.userId,
    required this.organizationId,
  });

  final String userId;
  final String organizationId;
}

class PlanningMutationRecord {
  const PlanningMutationRecord({
    required this.aggregateId,
    required this.organizationId,
    required this.kind,
    required this.syncStatus,
    required this.orderKey,
    required this.updatedAt,
    this.planId,
    this.sessionId,
    this.slug,
    this.name,
    this.description,
    this.scheduledFor,
    this.position,
    this.songId,
    this.songTitle,
    this.orderedSiblingIds,
    this.orderedSiblingPositions,
    this.baseVersion,
    this.originSnapshot,
    this.errorCode,
    this.errorMessage,
    this.localRevision = 0,
  });

  final String aggregateId;
  final String organizationId;
  final String? planId;
  final String? sessionId;
  final String? slug;
  final String? name;
  final String? description;
  final DateTime? scheduledFor;
  final int? position;
  final String? songId;
  final String? songTitle;
  final List<String>? orderedSiblingIds;
  final List<int>? orderedSiblingPositions;
  final int? baseVersion;
  final Map<String, Object?>? originSnapshot;
  final PlanningMutationSyncErrorCode? errorCode;
  final String? errorMessage;
  final PlanningMutationKind kind;
  final PlanningMutationSyncStatus syncStatus;
  final int orderKey;
  final DateTime updatedAt;

  /// Local bookkeeping only -- see `CachedPlanningMutations.localRevision`
  /// (`planning_local_tables.dart`) for why this exists and why it is not
  /// OCC. Populated when a record is read back from storage; `0` for a
  /// record a caller is about to hand to a `record*` write (the store
  /// computes the real value on write and callers never need to guess it).
  final int localRevision;

  PlanningMutationRecord copyWith({
    String? aggregateId,
    String? organizationId,
    String? planId,
    bool clearPlanId = false,
    String? sessionId,
    bool clearSessionId = false,
    String? slug,
    bool clearSlug = false,
    String? name,
    bool clearName = false,
    String? description,
    bool clearDescription = false,
    DateTime? scheduledFor,
    bool clearScheduledFor = false,
    int? position,
    bool clearPosition = false,
    String? songId,
    bool clearSongId = false,
    String? songTitle,
    bool clearSongTitle = false,
    List<String>? orderedSiblingIds,
    bool clearOrderedSiblingIds = false,
    List<int>? orderedSiblingPositions,
    bool clearOrderedSiblingPositions = false,
    int? baseVersion,
    bool clearBaseVersion = false,
    Map<String, Object?>? originSnapshot,
    bool clearOriginSnapshot = false,
    PlanningMutationSyncErrorCode? errorCode,
    bool clearErrorCode = false,
    String? errorMessage,
    bool clearErrorMessage = false,
    PlanningMutationKind? kind,
    PlanningMutationSyncStatus? syncStatus,
    int? orderKey,
    DateTime? updatedAt,
    int? localRevision,
  }) {
    return PlanningMutationRecord(
      aggregateId: aggregateId ?? this.aggregateId,
      organizationId: organizationId ?? this.organizationId,
      planId: clearPlanId ? null : (planId ?? this.planId),
      sessionId: clearSessionId ? null : (sessionId ?? this.sessionId),
      slug: clearSlug ? null : (slug ?? this.slug),
      name: clearName ? null : (name ?? this.name),
      description: clearDescription ? null : (description ?? this.description),
      scheduledFor: clearScheduledFor
          ? null
          : (scheduledFor ?? this.scheduledFor),
      position: clearPosition ? null : (position ?? this.position),
      songId: clearSongId ? null : (songId ?? this.songId),
      songTitle: clearSongTitle ? null : (songTitle ?? this.songTitle),
      orderedSiblingIds: clearOrderedSiblingIds
          ? null
          : (orderedSiblingIds ?? this.orderedSiblingIds),
      orderedSiblingPositions: clearOrderedSiblingPositions
          ? null
          : (orderedSiblingPositions ?? this.orderedSiblingPositions),
      baseVersion: clearBaseVersion ? null : (baseVersion ?? this.baseVersion),
      originSnapshot: clearOriginSnapshot
          ? null
          : (originSnapshot ?? this.originSnapshot),
      errorCode: clearErrorCode ? null : (errorCode ?? this.errorCode),
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
      kind: kind ?? this.kind,
      syncStatus: syncStatus ?? this.syncStatus,
      orderKey: orderKey ?? this.orderKey,
      updatedAt: updatedAt ?? this.updatedAt,
      localRevision: localRevision ?? this.localRevision,
    );
  }
}

class PlanningPlanCreateMutationDraft {
  const PlanningPlanCreateMutationDraft({
    required this.planId,
    required this.slug,
    required this.name,
    this.description,
    this.scheduledFor,
  });

  final String planId;
  final String slug;
  final String name;
  final String? description;
  final DateTime? scheduledFor;
}

class PlanningPlanEditMutationDraft {
  const PlanningPlanEditMutationDraft({
    required this.planId,
    required this.name,
    this.description,
    this.scheduledFor,
    this.baseVersion,
    this.originSnapshot,
  });

  final String planId;
  final String name;
  final String? description;
  final DateTime? scheduledFor;
  final int? baseVersion;
  final Map<String, Object?>? originSnapshot;
}

class PlanningSessionCreateMutationDraft {
  const PlanningSessionCreateMutationDraft({
    required this.sessionId,
    required this.planId,
    required this.slug,
    required this.name,
    required this.position,
  });

  final String sessionId;
  final String planId;
  final String slug;
  final String name;
  final int position;
}

class PlanningSessionRenameMutationDraft {
  const PlanningSessionRenameMutationDraft({
    required this.sessionId,
    required this.planId,
    required this.name,
    this.baseVersion,
    this.originSnapshot,
  });

  final String sessionId;
  final String planId;
  final String name;
  final int? baseVersion;
  final Map<String, Object?>? originSnapshot;
}

class PlanningSessionDeleteMutationDraft {
  const PlanningSessionDeleteMutationDraft({
    required this.sessionId,
    required this.planId,
    this.baseVersion,
    this.originSnapshot,
  });

  final String sessionId;
  final String planId;
  final int? baseVersion;
  final Map<String, Object?>? originSnapshot;
}

class PlanningSessionReorderMutationDraft {
  const PlanningSessionReorderMutationDraft({
    required this.planId,
    required this.orderedSessionIds,
    this.baseVersion,
    this.originSnapshot,
  });

  final String planId;
  final List<String> orderedSessionIds;
  final int? baseVersion;
  final Map<String, Object?>? originSnapshot;
}

class PlanningSessionItemCreateSongMutationDraft {
  const PlanningSessionItemCreateSongMutationDraft({
    required this.sessionItemId,
    required this.sessionId,
    required this.planId,
    required this.songId,
    required this.songTitle,
    required this.position,
    this.baseVersion,
    this.originSnapshot,
  });

  final String sessionItemId;
  final String sessionId;
  final String planId;
  final String songId;
  final String songTitle;
  final int position;
  final int? baseVersion;
  final Map<String, Object?>? originSnapshot;
}

class PlanningSessionItemDeleteMutationDraft {
  const PlanningSessionItemDeleteMutationDraft({
    required this.sessionItemId,
    required this.sessionId,
    required this.planId,
    this.baseVersion,
    this.originSnapshot,
  });

  final String sessionItemId;
  final String sessionId;
  final String planId;
  final int? baseVersion;
  final Map<String, Object?>? originSnapshot;
}

class PlanningSessionItemReorderMutationDraft {
  const PlanningSessionItemReorderMutationDraft({
    required this.sessionId,
    required this.planId,
    required this.orderedSessionItemIds,
    this.baseVersion,
    this.originSnapshot,
  });

  final String sessionId;
  final String planId;
  final List<String> orderedSessionItemIds;
  final int? baseVersion;
  final Map<String, Object?>? originSnapshot;
}

abstract interface class PlanningMutationStore {
  Future<void> recordPlanCreate({
    required PlanningMutationContext context,
    required PlanningPlanCreateMutationDraft draft,
  });

  Future<void> recordPlanEdit({
    required PlanningMutationContext context,
    required PlanningPlanEditMutationDraft draft,
  });

  Future<void> recordSessionCreate({
    required PlanningMutationContext context,
    required PlanningSessionCreateMutationDraft draft,
  });

  Future<void> recordSessionRename({
    required PlanningMutationContext context,
    required PlanningSessionRenameMutationDraft draft,
  });

  Future<void> recordSessionDelete({
    required PlanningMutationContext context,
    required PlanningSessionDeleteMutationDraft draft,
  });

  Future<void> recordSessionReorder({
    required PlanningMutationContext context,
    required PlanningSessionReorderMutationDraft draft,
  });

  Future<void> recordSessionItemCreateSong({
    required PlanningMutationContext context,
    required PlanningSessionItemCreateSongMutationDraft draft,
  });

  Future<void> recordSessionItemDelete({
    required PlanningMutationContext context,
    required PlanningSessionItemDeleteMutationDraft draft,
  });

  Future<void> recordSessionItemReorder({
    required PlanningMutationContext context,
    required PlanningSessionItemReorderMutationDraft draft,
  });

  Future<List<PlanningMutationRecord>> readPendingMutations({
    required String userId,
    required String organizationId,
  });

  Future<List<PlanningMutationRecord>> readActionableMutations({
    required String userId,
    required String organizationId,
  });

  Future<List<PlanningMutationRecord>> readAllMutations({
    required String userId,
    required String organizationId,
  });

  Future<PlanningMutationRecord?> readMutation({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
  });

  Future<String> allocatePlanSlug({
    required String userId,
    required String organizationId,
    required String name,
  });

  Future<String> allocateSessionSlug({
    required String userId,
    required String organizationId,
    required String planId,
    required String name,
  });

  Future<bool> hasUnsyncedMutations({required String userId});

  /// Writes the outcome of a remote sync attempt onto the mutation row.
  ///
  /// [expectedRevision], when supplied, gates the write: it is compared
  /// against the row's CURRENT `localRevision` as part of the same storage
  /// statement (D2, `docs/specs/2026-08-05-sync-snapshot-identity.md`), and
  /// the write applies only if they still match. A `null` [expectedRevision]
  /// writes unconditionally (used by the non-accept status paths, which are
  /// not part of the D2 snapshot-identity contract).
  ///
  /// Returns the row's new `localRevision` if the write applied, or `null`
  /// if it did not apply -- either because [expectedRevision] no longer
  /// matched (meaning a local edit landed on this aggregate after the
  /// snapshot that was sent, so the outcome is stale; D3: not an error), or
  /// because the row no longer exists at all (D4,
  /// `docs/specs/2026-08-06-in-flight-create-cancellation.md`: the user
  /// deleted a still-pending create while its remote call was in flight,
  /// and the collapse path removed the row; also not an error). Either way
  /// the caller must leave things as they are and must not proceed to
  /// [clearMutation] or reconcile it.
  Future<int?> saveSyncAttemptResult({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
    required PlanningMutationSyncStatus syncStatus,
    PlanningMutationSyncErrorCode? errorCode,
    String? errorMessage,
    int? expectedRevision,
  });

  /// Resets a failed mutation back to `pending` so the next sync resends it.
  ///
  /// Returns `true` if the row existed and was reset, or `false` if it did
  /// not exist (D4,
  /// `docs/specs/2026-08-06-in-flight-create-cancellation.md`: an ordinary
  /// concurrent-world outcome -- the row vanished before this retry ran --
  /// not an error). There is nothing to retry in that case.
  Future<bool> retryMutation({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
  });

  /// Deletes the mutation row concluding a sync.
  ///
  /// [expectedRevision], when supplied, gates the delete the same way it
  /// gates [saveSyncAttemptResult] (D2): the row is removed only if its
  /// CURRENT `localRevision` still matches, as part of the same storage
  /// statement. A `null` [expectedRevision] deletes unconditionally (used by
  /// explicit user discard, which is not part of the D2 contract -- the user
  /// wants whatever is there gone).
  ///
  /// Returns `true` if the row was deleted, `false` if [expectedRevision] no
  /// longer matched -- the row is left pending with its newer content (D3:
  /// not an error), and the next sync will send it.
  Future<bool> clearMutation({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
    int? expectedRevision,
  });

  /// D3 (`docs/specs/2026-08-06-in-flight-create-cancellation.md`): resolves
  /// the outcome of an in-flight `sessionCreate`/`sessionItemCreateSong`
  /// whose row may have become a D2 cancellation tombstone
  /// (`PlanningMutationSyncStatus.cancelling`) while its remote call was in
  /// flight.
  ///
  /// Only acts if the row currently exists AND is a tombstone; any other
  /// state (no row, or a row whose status is something other than
  /// `cancelling`) means this call has nothing to do -- either the row was
  /// never cancelled (an ordinary local edit landed instead, already
  /// resolved by the caller's own D3 stale-revision handling) or a previous
  /// call already resolved it -- and this is then a no-op that returns
  /// `false`. The check and the write happen inside a single storage
  /// transaction so a concurrent write cannot land in between.
  ///
  /// When [created] is `true` the create reached the backend, so the
  /// tombstone becomes a real pending delete: `kind` flips to the matching
  /// `*Delete` kind, `syncStatus` resets to `pending`, and `baseVersion` is
  /// rebased on [acceptedBaseVersion] (the version the backend just
  /// assigned the created row) so the delete RPC's OCC check targets the
  /// content that actually exists remotely. The next sync sends it. The
  /// already-accepted remote create is never undone -- the delete is a
  /// subsequent operation, which is what the user asked for.
  ///
  /// When [created] is `false` the create never reached the backend, so the
  /// object never existed remotely: the tombstone is discarded outright,
  /// with no further backend call -- exactly the physical collapse a plain,
  /// not-in-flight delete would have performed (ADR-028 D10).
  ///
  /// Returns `true` if a tombstone was found and resolved, `false`
  /// otherwise.
  Future<bool> resolveCancelledCreate({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
    required bool created,
    int? acceptedBaseVersion,
  });
}

typedef PlanningIdGenerator = String Function();

String generatePlanningUuidV4() {
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

abstract interface class PlanningMutationRemoteRepository {
  Future<PlanningMutationRecord> syncMutation({
    required String organizationId,
    required PlanningMutationRecord record,
  });
}
