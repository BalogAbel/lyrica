import 'package:drift/drift.dart';
import 'package:lyron_app/src/domain/planning/plan_detail.dart';
import 'package:lyron_app/src/domain/planning/plan_summary.dart';
import 'package:lyron_app/src/domain/planning/session_item_summary.dart';
import 'package:lyron_app/src/domain/planning/session_summary.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';

class CachedPlanRecord {
  const CachedPlanRecord({
    required this.id,
    required this.name,
    required this.description,
    required this.scheduledFor,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String? description;
  final DateTime? scheduledFor;
  final DateTime updatedAt;
}

class CachedSessionRecord {
  const CachedSessionRecord({
    required this.id,
    required this.planId,
    required this.position,
    required this.name,
  });

  final String id;
  final String planId;
  final int position;
  final String name;
}

class CachedSessionItemRecord {
  const CachedSessionItemRecord({
    required this.id,
    required this.planId,
    required this.sessionId,
    required this.position,
    required this.songId,
    required this.songTitle,
  });

  final String id;
  final String planId;
  final String sessionId;
  final int position;
  final String songId;
  final String songTitle;
}

abstract interface class PlanningLocalStore {
  Future<void> replaceActiveProjection({
    required String userId,
    required String organizationId,
    required List<CachedPlanRecord> plans,
    required List<CachedSessionRecord> sessions,
    required List<CachedSessionItemRecord> items,
    required DateTime refreshedAt,
  });

  Future<List<PlanSummary>> readPlanSummaries({
    required String userId,
    required String organizationId,
  });

  Future<PlanDetail?> readPlanDetail({
    required String userId,
    required String organizationId,
    required String planId,
  });

  Future<bool> hasProjection({
    required String userId,
    required String organizationId,
  });

  Future<String?> readLatestCachedOrganizationId({required String userId});

  Future<void> deletePlanningData({
    required String userId,
    required String organizationId,
  });

  Future<void> deletePlanningDataForUser({required String userId});
}

class DriftPlanningLocalStore implements PlanningLocalStore {
  const DriftPlanningLocalStore(this._database);

  final PlanningLocalDatabase _database;

  @override
  Future<void> replaceActiveProjection({
    required String userId,
    required String organizationId,
    required List<CachedPlanRecord> plans,
    required List<CachedSessionRecord> sessions,
    required List<CachedSessionItemRecord> items,
    required DateTime refreshedAt,
  }) async {
    _validateProjection(plans: plans, sessions: sessions, items: items);

    await _database.transaction(() async {
      final currentOwner =
          await (_database.select(_database.planningProjectionOwners)..where(
                (table) =>
                    table.userId.equals(userId) &
                    table.organizationId.equals(organizationId),
              ))
              .getSingleOrNull();
      final nextSnapshotVersion = (currentOwner?.snapshotVersion ?? 0) + 1;

      await deletePlanningData(userId: userId, organizationId: organizationId);

      await _database
          .into(_database.planningProjectionOwners)
          .insert(
            PlanningProjectionOwnersCompanion.insert(
              userId: userId,
              organizationId: organizationId,
              snapshotVersion: nextSnapshotVersion,
              refreshedAt: refreshedAt.toUtc(),
            ),
          );

      await _database.batch((batch) {
        batch.insertAll(
          _database.cachedPlanningPlans,
          plans
              .map(
                (plan) => CachedPlanningPlansCompanion.insert(
                  userId: userId,
                  organizationId: organizationId,
                  snapshotVersion: nextSnapshotVersion,
                  planId: plan.id,
                  name: plan.name,
                  description: Value(plan.description),
                  scheduledFor: Value(plan.scheduledFor?.toUtc()),
                  updatedAt: plan.updatedAt.toUtc(),
                ),
              )
              .toList(growable: false),
        );
        batch.insertAll(
          _database.cachedPlanningSessions,
          sessions
              .map(
                (session) => CachedPlanningSessionsCompanion.insert(
                  userId: userId,
                  organizationId: organizationId,
                  snapshotVersion: nextSnapshotVersion,
                  sessionId: session.id,
                  planId: session.planId,
                  position: session.position,
                  name: session.name,
                ),
              )
              .toList(growable: false),
        );
        batch.insertAll(
          _database.cachedPlanningSessionItems,
          items
              .map(
                (item) => CachedPlanningSessionItemsCompanion.insert(
                  userId: userId,
                  organizationId: organizationId,
                  snapshotVersion: nextSnapshotVersion,
                  sessionItemId: item.id,
                  planId: item.planId,
                  sessionId: item.sessionId,
                  position: item.position,
                  songId: item.songId,
                  songTitle: item.songTitle,
                ),
              )
              .toList(growable: false),
        );
      });
    });
  }

  @override
  Future<List<PlanSummary>> readPlanSummaries({
    required String userId,
    required String organizationId,
  }) async {
    final owner = await _readOwner(
      userId: userId,
      organizationId: organizationId,
    );
    if (owner == null) {
      return const [];
    }

    final rows =
        await (_database.select(_database.cachedPlanningPlans)..where(
              (table) =>
                  table.userId.equals(userId) &
                  table.organizationId.equals(organizationId) &
                  table.snapshotVersion.equals(owner.snapshotVersion),
            ))
            .get();

    final plans = rows.map(_toPlanSummary).toList(growable: false)
      ..sort(_comparePlans);
    return plans;
  }

  @override
  Future<PlanDetail?> readPlanDetail({
    required String userId,
    required String organizationId,
    required String planId,
  }) async {
    final owner = await _readOwner(
      userId: userId,
      organizationId: organizationId,
    );
    if (owner == null) {
      return null;
    }

    final planRow =
        await (_database.select(_database.cachedPlanningPlans)..where(
              (table) =>
                  table.userId.equals(userId) &
                  table.organizationId.equals(organizationId) &
                  table.snapshotVersion.equals(owner.snapshotVersion) &
                  table.planId.equals(planId),
            ))
            .getSingleOrNull();
    if (planRow == null) {
      return null;
    }

    final sessionRows =
        await (_database.select(_database.cachedPlanningSessions)..where(
              (table) =>
                  table.userId.equals(userId) &
                  table.organizationId.equals(organizationId) &
                  table.snapshotVersion.equals(owner.snapshotVersion) &
                  table.planId.equals(planId),
            ))
            .get();
    sessionRows.sort(
      (left, right) => left.position != right.position
          ? left.position.compareTo(right.position)
          : left.sessionId.compareTo(right.sessionId),
    );

    final itemRows =
        await (_database.select(_database.cachedPlanningSessionItems)..where(
              (table) =>
                  table.userId.equals(userId) &
                  table.organizationId.equals(organizationId) &
                  table.snapshotVersion.equals(owner.snapshotVersion) &
                  table.planId.equals(planId),
            ))
            .get();

    final itemsBySessionId = <String, List<CachedPlanningSessionItem>>{};
    for (final row in itemRows) {
      itemsBySessionId.putIfAbsent(row.sessionId, () => []).add(row);
    }
    for (final rows in itemsBySessionId.values) {
      rows.sort(
        (left, right) => left.position != right.position
            ? left.position.compareTo(right.position)
            : left.sessionItemId.compareTo(right.sessionItemId),
      );
    }

    return PlanDetail(
      plan: _toPlanSummary(planRow),
      sessions: sessionRows
          .map(
            (session) => SessionSummary(
              id: session.sessionId,
              name: session.name,
              position: session.position,
              items: (itemsBySessionId[session.sessionId] ?? const [])
                  .map(
                    (item) => SessionItemSummary(
                      id: item.sessionItemId,
                      position: item.position,
                      song: SongSummary(id: item.songId, title: item.songTitle),
                    ),
                  )
                  .toList(growable: false),
            ),
          )
          .toList(growable: false),
    );
  }

  @override
  Future<bool> hasProjection({
    required String userId,
    required String organizationId,
  }) async {
    final owner = await _readOwner(
      userId: userId,
      organizationId: organizationId,
    );
    return owner != null;
  }

  @override
  Future<String?> readLatestCachedOrganizationId({
    required String userId,
  }) async {
    final row =
        await (_database.select(_database.planningProjectionOwners)
              ..where((table) => table.userId.equals(userId))
              ..orderBy([(table) => OrderingTerm.desc(table.refreshedAt)])
              ..limit(1))
            .getSingleOrNull();

    return row?.organizationId;
  }

  @override
  Future<void> deletePlanningData({
    required String userId,
    required String organizationId,
  }) async {
    await _database.transaction(() async {
      await (_database.delete(_database.cachedPlanningSessionItems)..where(
            (table) =>
                table.userId.equals(userId) &
                table.organizationId.equals(organizationId),
          ))
          .go();
      await (_database.delete(_database.cachedPlanningSessions)..where(
            (table) =>
                table.userId.equals(userId) &
                table.organizationId.equals(organizationId),
          ))
          .go();
      await (_database.delete(_database.cachedPlanningPlans)..where(
            (table) =>
                table.userId.equals(userId) &
                table.organizationId.equals(organizationId),
          ))
          .go();
      await (_database.delete(_database.planningProjectionOwners)..where(
            (table) =>
                table.userId.equals(userId) &
                table.organizationId.equals(organizationId),
          ))
          .go();
    });
  }

  @override
  Future<void> deletePlanningDataForUser({required String userId}) async {
    await _database.transaction(() async {
      await (_database.delete(
        _database.cachedPlanningSessionItems,
      )..where((table) => table.userId.equals(userId))).go();
      await (_database.delete(
        _database.cachedPlanningSessions,
      )..where((table) => table.userId.equals(userId))).go();
      await (_database.delete(
        _database.cachedPlanningPlans,
      )..where((table) => table.userId.equals(userId))).go();
      await (_database.delete(
        _database.planningProjectionOwners,
      )..where((table) => table.userId.equals(userId))).go();
    });
  }

  Future<PlanningProjectionOwner?> _readOwner({
    required String userId,
    required String organizationId,
  }) {
    return (_database.select(_database.planningProjectionOwners)..where(
          (table) =>
              table.userId.equals(userId) &
              table.organizationId.equals(organizationId),
        ))
        .getSingleOrNull();
  }

  PlanSummary _toPlanSummary(CachedPlanningPlan row) {
    return PlanSummary(
      id: row.planId,
      name: row.name,
      description: row.description,
      scheduledFor: row.scheduledFor?.toUtc(),
      updatedAt: row.updatedAt.toUtc(),
    );
  }

  int _comparePlans(PlanSummary left, PlanSummary right) {
    final leftScheduled = left.scheduledFor;
    final rightScheduled = right.scheduledFor;
    if (leftScheduled == null && rightScheduled != null) {
      return 1;
    }
    if (leftScheduled != null && rightScheduled == null) {
      return -1;
    }
    if (leftScheduled != null && rightScheduled != null) {
      final scheduledComparison = leftScheduled.compareTo(rightScheduled);
      if (scheduledComparison != 0) {
        return scheduledComparison;
      }
    }

    final updatedComparison = right.updatedAt.compareTo(left.updatedAt);
    if (updatedComparison != 0) {
      return updatedComparison;
    }

    return left.id.compareTo(right.id);
  }

  void _validateProjection({
    required List<CachedPlanRecord> plans,
    required List<CachedSessionRecord> sessions,
    required List<CachedSessionItemRecord> items,
  }) {
    final planIds = plans.map((plan) => plan.id).toSet();
    final sessionIds = sessions.map((session) => session.id).toSet();
    final duplicatePlanIds = plans.length != planIds.length;
    final duplicateSessionIds = sessions.length != sessionIds.length;
    final duplicateItemIds =
        items.length != items.map((item) => item.id).toSet().length;
    if (duplicatePlanIds || duplicateSessionIds || duplicateItemIds) {
      throw ArgumentError(
        'Planning projection IDs must be unique within a snapshot.',
      );
    }

    final sessionPlanById = {
      for (final session in sessions) session.id: session.planId,
    };

    for (final session in sessions) {
      if (!planIds.contains(session.planId)) {
        throw ArgumentError(
          'Session ${session.id} references missing plan ${session.planId}.',
        );
      }
    }

    for (final item in items) {
      if (!planIds.contains(item.planId)) {
        throw ArgumentError(
          'Session item ${item.id} references missing plan ${item.planId}.',
        );
      }

      final sessionPlanId = sessionPlanById[item.sessionId];
      if (sessionPlanId == null) {
        throw ArgumentError(
          'Session item ${item.id} references missing session ${item.sessionId}.',
        );
      }
      if (sessionPlanId != item.planId) {
        throw ArgumentError(
          'Session item ${item.id} plan ${item.planId} does not match its parent session plan $sessionPlanId.',
        );
      }
    }
  }
}
