import 'dart:math';

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

class LocalPlanningSlugConflictException implements Exception {
  const LocalPlanningSlugConflictException();

  @override
  String toString() => 'LocalPlanningSlugConflictException()';
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
    this.errorCode,
    this.errorMessage,
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
  final PlanningMutationSyncErrorCode? errorCode;
  final String? errorMessage;
  final PlanningMutationKind kind;
  final PlanningMutationSyncStatus syncStatus;
  final int orderKey;
  final DateTime updatedAt;

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
    PlanningMutationSyncErrorCode? errorCode,
    bool clearErrorCode = false,
    String? errorMessage,
    bool clearErrorMessage = false,
    PlanningMutationKind? kind,
    PlanningMutationSyncStatus? syncStatus,
    int? orderKey,
    DateTime? updatedAt,
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
      errorCode: clearErrorCode ? null : (errorCode ?? this.errorCode),
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
      kind: kind ?? this.kind,
      syncStatus: syncStatus ?? this.syncStatus,
      orderKey: orderKey ?? this.orderKey,
      updatedAt: updatedAt ?? this.updatedAt,
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
  });

  final String planId;
  final String name;
  final String? description;
  final DateTime? scheduledFor;
  final int? baseVersion;
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
  });

  final String sessionId;
  final String planId;
  final String name;
  final int? baseVersion;
}

class PlanningSessionDeleteMutationDraft {
  const PlanningSessionDeleteMutationDraft({
    required this.sessionId,
    required this.planId,
    this.baseVersion,
  });

  final String sessionId;
  final String planId;
  final int? baseVersion;
}

class PlanningSessionReorderMutationDraft {
  const PlanningSessionReorderMutationDraft({
    required this.planId,
    required this.orderedSessionIds,
    this.baseVersion,
  });

  final String planId;
  final List<String> orderedSessionIds;
  final int? baseVersion;
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
  });

  final String sessionItemId;
  final String sessionId;
  final String planId;
  final String songId;
  final String songTitle;
  final int position;
  final int? baseVersion;
}

class PlanningSessionItemDeleteMutationDraft {
  const PlanningSessionItemDeleteMutationDraft({
    required this.sessionItemId,
    required this.sessionId,
    required this.planId,
    this.baseVersion,
  });

  final String sessionItemId;
  final String sessionId;
  final String planId;
  final int? baseVersion;
}

class PlanningSessionItemReorderMutationDraft {
  const PlanningSessionItemReorderMutationDraft({
    required this.sessionId,
    required this.planId,
    required this.orderedSessionItemIds,
    this.baseVersion,
  });

  final String sessionId;
  final String planId;
  final List<String> orderedSessionItemIds;
  final int? baseVersion;
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

  Future<void> saveSyncAttemptResult({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
    required PlanningMutationSyncStatus syncStatus,
    PlanningMutationSyncErrorCode? errorCode,
    String? errorMessage,
  });

  Future<void> retryMutation({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
  });

  Future<void> clearMutation({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
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
