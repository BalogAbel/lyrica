import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/application/planning/planning_sync_state.dart';
import 'package:lyron_app/src/application/song_library/catalog_connection_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_refresh_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_snapshot_state.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_types.dart';

enum UnifiedSyncHeaderStatus { synced, unsynced, conflict }

enum UnifiedSyncActivity { idle, syncing }

enum UnifiedSyncConnectivity { online, offline, unknown }

enum UnifiedSyncFreshness { fresh, stale, offlineCached, unknown }

enum UnifiedSyncRowSeverity { pending, retryableFailure, conflict }

enum UnifiedSyncReasonCode {
  pendingLocal,
  syncFailed,
  conflict,
  authorizationDenied,
  dependencyBlocked,
  remoteMissing,
  unknown,
}

class UnifiedSyncOverview {
  const UnifiedSyncOverview({
    required this.headerStatus,
    required this.activity,
    required this.connectivity,
    required this.freshness,
    required this.songRows,
    required this.planRows,
    required this.hasUnsyncedWork,
  });

  const UnifiedSyncOverview.initial()
    : this(
        headerStatus: UnifiedSyncHeaderStatus.synced,
        activity: UnifiedSyncActivity.idle,
        connectivity: UnifiedSyncConnectivity.unknown,
        freshness: UnifiedSyncFreshness.unknown,
        songRows: const [],
        planRows: const [],
        hasUnsyncedWork: false,
      );

  final UnifiedSyncHeaderStatus headerStatus;
  final UnifiedSyncActivity activity;
  final UnifiedSyncConnectivity connectivity;
  final UnifiedSyncFreshness freshness;
  final List<UnifiedSyncSongRow> songRows;
  final List<UnifiedSyncPlanRow> planRows;
  final bool hasUnsyncedWork;
}

class UnifiedSyncSongRow {
  const UnifiedSyncSongRow({
    required this.songId,
    required this.title,
    required this.entityState,
    required this.severity,
    required this.reasonCode,
    this.errorMessage,
  });

  final String songId;
  final String title;
  final SongSyncStatus entityState;
  final UnifiedSyncRowSeverity severity;
  final UnifiedSyncReasonCode reasonCode;
  final String? errorMessage;
}

class UnifiedSyncPlanRow {
  const UnifiedSyncPlanRow({
    required this.planId,
    required this.title,
    required this.severity,
    required this.reasonCode,
    required this.nestedSummaries,
    this.errorMessage,
  });

  final String planId;
  final String title;
  final UnifiedSyncRowSeverity severity;
  final UnifiedSyncReasonCode reasonCode;
  final List<String> nestedSummaries;
  final String? errorMessage;
}

class UnifiedSyncOverviewInputs {
  const UnifiedSyncOverviewInputs({
    required this.catalog,
    required this.songEntries,
    required this.planning,
    required this.planningEntries,
    this.planTitles = const {},
    this.songSyncing = false,
    this.planningSyncing = false,
  });

  final CatalogSnapshotState catalog;
  final List<SongMutationRecord> songEntries;
  final PlanningSyncState planning;
  final List<PlanningMutationRecord> planningEntries;
  final Map<String, String> planTitles;
  final bool songSyncing;
  final bool planningSyncing;
}

UnifiedSyncOverview computeUnifiedSyncOverview(UnifiedSyncOverviewInputs input) {
  final songRows = _buildSongRows(input.songEntries);
  final planRows = _buildPlanRows(
    entries: input.planningEntries,
    planTitles: input.planTitles,
  );

  final hasConflict =
      songRows.any((r) => r.severity == UnifiedSyncRowSeverity.conflict) ||
      planRows.any((r) => r.severity == UnifiedSyncRowSeverity.conflict);
  final hasPendingOrRetryable =
      songRows.any((r) => r.severity != UnifiedSyncRowSeverity.conflict) ||
      planRows.any((r) => r.severity != UnifiedSyncRowSeverity.conflict);

  final headerStatus = hasConflict
      ? UnifiedSyncHeaderStatus.conflict
      : hasPendingOrRetryable
      ? UnifiedSyncHeaderStatus.unsynced
      : UnifiedSyncHeaderStatus.synced;

  final activity =
      input.songSyncing ||
          input.planningSyncing ||
          input.catalog.refreshStatus == CatalogRefreshStatus.refreshing ||
          input.planning.refreshStatus == PlanningRefreshStatus.refreshing
      ? UnifiedSyncActivity.syncing
      : UnifiedSyncActivity.idle;

  final connectivity = switch (input.catalog.connectionStatus) {
    CatalogConnectionStatus.online => UnifiedSyncConnectivity.online,
    CatalogConnectionStatus.offlineCached => UnifiedSyncConnectivity.offline,
    CatalogConnectionStatus.unavailable => UnifiedSyncConnectivity.unknown,
  };

  final freshness = switch (input.catalog.connectionStatus) {
    CatalogConnectionStatus.online =>
      input.catalog.refreshStatus == CatalogRefreshStatus.failed
          ? UnifiedSyncFreshness.stale
          : UnifiedSyncFreshness.fresh,
    CatalogConnectionStatus.offlineCached => UnifiedSyncFreshness.offlineCached,
    CatalogConnectionStatus.unavailable => UnifiedSyncFreshness.unknown,
  };

  return UnifiedSyncOverview(
    headerStatus: headerStatus,
    activity: activity,
    connectivity: connectivity,
    freshness: freshness,
    songRows: songRows,
    planRows: planRows,
    hasUnsyncedWork: songRows.isNotEmpty || planRows.isNotEmpty,
  );
}

List<UnifiedSyncSongRow> _buildSongRows(List<SongMutationRecord> entries) {
  final rows = <UnifiedSyncSongRow>[];
  for (final entry in entries) {
    if (entry.syncStatus == SongSyncStatus.synced &&
        entry.conflictSourceSyncStatus == null) {
      continue;
    }
    final reason = _reasonFromSongEntry(entry);
    final severity = _severityFromSongEntry(entry, reason);
    rows.add(
      UnifiedSyncSongRow(
        songId: entry.id,
        title: entry.title,
        entityState: entry.effectiveSyncStatus,
        severity: severity,
        reasonCode: reason,
        errorMessage: entry.errorMessage,
      ),
    );
  }
  return rows;
}

UnifiedSyncReasonCode _reasonFromSongEntry(SongMutationRecord entry) {
  if (entry.syncStatus == SongSyncStatus.conflict) {
    return switch (entry.errorCode) {
      SongMutationSyncErrorCode.authorizationDenied =>
        UnifiedSyncReasonCode.authorizationDenied,
      SongMutationSyncErrorCode.dependencyBlocked =>
        UnifiedSyncReasonCode.dependencyBlocked,
      SongMutationSyncErrorCode.remoteDeleted =>
        UnifiedSyncReasonCode.remoteMissing,
      SongMutationSyncErrorCode.conflict ||
      null => UnifiedSyncReasonCode.conflict,
      SongMutationSyncErrorCode.connectivityFailure =>
        UnifiedSyncReasonCode.syncFailed,
      SongMutationSyncErrorCode.unknown => UnifiedSyncReasonCode.unknown,
    };
  }
  return switch (entry.errorCode) {
    SongMutationSyncErrorCode.connectivityFailure =>
      UnifiedSyncReasonCode.syncFailed,
    SongMutationSyncErrorCode.unknown => UnifiedSyncReasonCode.unknown,
    null => UnifiedSyncReasonCode.pendingLocal,
    _ => UnifiedSyncReasonCode.syncFailed,
  };
}

UnifiedSyncRowSeverity _severityFromSongEntry(
  SongMutationRecord entry,
  UnifiedSyncReasonCode reason,
) {
  if (entry.syncStatus == SongSyncStatus.conflict ||
      reason == UnifiedSyncReasonCode.authorizationDenied ||
      reason == UnifiedSyncReasonCode.dependencyBlocked ||
      reason == UnifiedSyncReasonCode.remoteMissing ||
      reason == UnifiedSyncReasonCode.conflict) {
    return UnifiedSyncRowSeverity.conflict;
  }
  if (reason == UnifiedSyncReasonCode.syncFailed ||
      reason == UnifiedSyncReasonCode.unknown) {
    return UnifiedSyncRowSeverity.retryableFailure;
  }
  return UnifiedSyncRowSeverity.pending;
}

List<UnifiedSyncPlanRow> _buildPlanRows({
  required List<PlanningMutationRecord> entries,
  required Map<String, String> planTitles,
}) {
  if (entries.isEmpty) return const [];

  final grouped = <String, List<PlanningMutationRecord>>{};
  for (final entry in entries) {
    final key = _planGroupKey(entry);
    grouped.putIfAbsent(key, () => <PlanningMutationRecord>[]).add(entry);
  }

  final rows = <UnifiedSyncPlanRow>[];
  grouped.forEach((planId, groupEntries) {
    final reason = _reasonFromPlanGroup(groupEntries);
    final severity = _severityFromPlanGroup(groupEntries, reason);
    final title = _planTitle(
      planId: planId,
      entries: groupEntries,
      planTitles: planTitles,
    );
    final nested = groupEntries
        .map(_nestedSummaryFor)
        .toList(growable: false);
    final firstWithMessage = groupEntries.firstWhere(
      (e) => e.errorMessage != null,
      orElse: () => groupEntries.first,
    );
    rows.add(
      UnifiedSyncPlanRow(
        planId: planId,
        title: title,
        severity: severity,
        reasonCode: reason,
        nestedSummaries: nested,
        errorMessage: firstWithMessage.errorMessage,
      ),
    );
  });

  rows.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  return rows;
}

String _planGroupKey(PlanningMutationRecord entry) {
  switch (entry.kind) {
    case PlanningMutationKind.planCreate:
    case PlanningMutationKind.planEdit:
      return entry.aggregateId;
    default:
      return entry.planId ?? '__orphan_${entry.aggregateId}';
  }
}

String _planTitle({
  required String planId,
  required List<PlanningMutationRecord> entries,
  required Map<String, String> planTitles,
}) {
  final fromMap = planTitles[planId];
  if (fromMap != null && fromMap.isNotEmpty) return fromMap;

  for (final candidate in entries) {
    if (candidate.kind == PlanningMutationKind.planCreate ||
        candidate.kind == PlanningMutationKind.planEdit) {
      final name = candidate.name;
      if (name != null && name.isNotEmpty) return name;
      final slug = candidate.slug;
      if (slug != null && slug.isNotEmpty) return slug;
      final originName = candidate.originSnapshot?['name'];
      if (originName is String && originName.isNotEmpty) return originName;
    }
  }

  for (final candidate in entries) {
    final originName = candidate.originSnapshot?['name'];
    if (originName is String && originName.isNotEmpty) return originName;
  }

  return planId;
}

UnifiedSyncReasonCode _reasonFromPlanGroup(List<PlanningMutationRecord> entries) {
  UnifiedSyncReasonCode? worst;
  for (final entry in entries) {
    final reason = _reasonFromPlanningEntry(entry);
    worst = _maxReason(worst, reason);
  }
  return worst ?? UnifiedSyncReasonCode.pendingLocal;
}

UnifiedSyncReasonCode _reasonFromPlanningEntry(PlanningMutationRecord entry) {
  if (entry.syncStatus == PlanningMutationSyncStatus.failedAuthorization ||
      entry.errorCode == PlanningMutationSyncErrorCode.authorizationDenied) {
    return UnifiedSyncReasonCode.authorizationDenied;
  }
  if (entry.syncStatus == PlanningMutationSyncStatus.failedDependency ||
      entry.errorCode == PlanningMutationSyncErrorCode.dependencyBlocked) {
    return UnifiedSyncReasonCode.dependencyBlocked;
  }
  if (entry.syncStatus == PlanningMutationSyncStatus.failedRemoteDelete ||
      entry.errorCode == PlanningMutationSyncErrorCode.remoteMissing) {
    return UnifiedSyncReasonCode.remoteMissing;
  }
  if (entry.syncStatus == PlanningMutationSyncStatus.conflict ||
      entry.errorCode == PlanningMutationSyncErrorCode.conflict) {
    return UnifiedSyncReasonCode.conflict;
  }
  if (entry.errorCode == PlanningMutationSyncErrorCode.connectivityFailure) {
    return UnifiedSyncReasonCode.syncFailed;
  }
  if (entry.errorCode == PlanningMutationSyncErrorCode.unknown) {
    return UnifiedSyncReasonCode.unknown;
  }
  return UnifiedSyncReasonCode.pendingLocal;
}

UnifiedSyncReasonCode _maxReason(
  UnifiedSyncReasonCode? a,
  UnifiedSyncReasonCode b,
) {
  if (a == null) return b;
  return _reasonRank(b) > _reasonRank(a) ? b : a;
}

int _reasonRank(UnifiedSyncReasonCode reason) => switch (reason) {
  UnifiedSyncReasonCode.pendingLocal => 0,
  UnifiedSyncReasonCode.syncFailed => 1,
  UnifiedSyncReasonCode.unknown => 2,
  UnifiedSyncReasonCode.conflict => 3,
  UnifiedSyncReasonCode.remoteMissing => 4,
  UnifiedSyncReasonCode.dependencyBlocked => 5,
  UnifiedSyncReasonCode.authorizationDenied => 6,
};

UnifiedSyncRowSeverity _severityFromPlanGroup(
  List<PlanningMutationRecord> entries,
  UnifiedSyncReasonCode reason,
) {
  if (reason == UnifiedSyncReasonCode.conflict ||
      reason == UnifiedSyncReasonCode.authorizationDenied ||
      reason == UnifiedSyncReasonCode.dependencyBlocked ||
      reason == UnifiedSyncReasonCode.remoteMissing) {
    return UnifiedSyncRowSeverity.conflict;
  }
  if (reason == UnifiedSyncReasonCode.syncFailed ||
      reason == UnifiedSyncReasonCode.unknown) {
    return UnifiedSyncRowSeverity.retryableFailure;
  }
  return UnifiedSyncRowSeverity.pending;
}

String _nestedSummaryFor(PlanningMutationRecord entry) {
  return switch (entry.kind) {
    PlanningMutationKind.planCreate => 'plan added',
    PlanningMutationKind.planEdit => 'plan edited',
    PlanningMutationKind.sessionCreate => 'session added',
    PlanningMutationKind.sessionRename => 'session renamed',
    PlanningMutationKind.sessionDelete => 'session removed',
    PlanningMutationKind.sessionReorder => 'session order changed',
    PlanningMutationKind.sessionItemCreateSong => 'song added',
    PlanningMutationKind.sessionItemDelete => 'song removed',
    PlanningMutationKind.sessionItemReorder => 'song order changed',
  };
}

