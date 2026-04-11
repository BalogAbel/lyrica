import 'package:drift/drift.dart';
import 'package:lyron_app/src/domain/planning/plan_detail.dart';
import 'package:lyron_app/src/domain/planning/plan_summary.dart';
import 'package:lyron_app/src/domain/planning/session_item_summary.dart';
import 'package:lyron_app/src/domain/planning/session_summary.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';

class PlanningProjectionAbortedException implements Exception {
  const PlanningProjectionAbortedException();
}

class CachedPlanRecord {
  const CachedPlanRecord({
    required this.id,
    required this.name,
    required this.description,
    required this.scheduledFor,
    required this.updatedAt,
    int? version,
    String? slug,
  }) : slug = slug ?? id,
       version = version ?? 1;

  final String id;
  final String slug;
  final String name;
  final String? description;
  final DateTime? scheduledFor;
  final DateTime updatedAt;
  final int version;
}

class CachedSessionRecord {
  const CachedSessionRecord({
    required this.id,
    required this.planId,
    required this.position,
    required this.name,
    int? version,
    String? slug,
  }) : slug = slug ?? id,
       version = version ?? 1;

  final String id;
  final String planId;
  final String slug;
  final int position;
  final String name;
  final int version;
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
    bool Function()? shouldContinue,
  });

  Future<List<PlanSummary>> readPlanSummaries({
    required String userId,
    required String organizationId,
  });

  Future<PlanSummary?> readPlanSummaryBySlug({
    required String userId,
    required String organizationId,
    required String planSlug,
  });

  Future<PlanDetail?> readPlanDetail({
    required String userId,
    required String organizationId,
    required String planId,
  });

  Future<PlanDetail?> readPlanDetailBySlug({
    required String userId,
    required String organizationId,
    required String planSlug,
  });

  Future<bool> hasProjection({
    required String userId,
    required String organizationId,
  });

  Future<int> countSongReferences({
    required String userId,
    required String organizationId,
    required String songId,
  });

  Future<String?> readLatestCachedOrganizationId({required String userId});

  Future<void> deletePlanningData({
    required String userId,
    required String organizationId,
    bool Function()? shouldContinue,
  });

  Future<void> deletePlanningDataForUser({
    required String userId,
    bool Function()? shouldContinue,
  });

  Future<void> upsertSyncedPlan({
    required String userId,
    required String organizationId,
    required CachedPlanRecord plan,
    required DateTime refreshedAt,
  });

  Future<void> upsertSyncedSession({
    required String userId,
    required String organizationId,
    required CachedSessionRecord session,
    required DateTime refreshedAt,
  });

  Future<void> deleteSyncedSession({
    required String userId,
    required String organizationId,
    required String sessionId,
    required DateTime refreshedAt,
  });

  Future<void> replaceSyncedSessionOrder({
    required String userId,
    required String organizationId,
    required String planId,
    required List<String> orderedSessionIds,
    List<int>? orderedSessionPositions,
    required int planVersion,
    required DateTime refreshedAt,
  });

  Future<void> upsertSyncedSessionItem({
    required String userId,
    required String organizationId,
    required CachedSessionItemRecord item,
    required int sessionVersion,
    required DateTime refreshedAt,
  });

  Future<void> deleteSyncedSessionItem({
    required String userId,
    required String organizationId,
    required String sessionId,
    required String sessionItemId,
    required int sessionVersion,
    required DateTime refreshedAt,
  });

  Future<void> replaceSyncedSessionItemOrder({
    required String userId,
    required String organizationId,
    required String sessionId,
    required List<String> orderedSessionItemIds,
    List<int>? orderedSessionItemPositions,
    required int sessionVersion,
    required DateTime refreshedAt,
  });
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
    bool Function()? shouldContinue,
  }) async {
    _validateProjection(plans: plans, sessions: sessions, items: items);
    _ensureProjectionCurrent(shouldContinue);

    await _database.transaction(() async {
      _ensureProjectionCurrent(shouldContinue);
      final currentOwner =
          await (_database.select(_database.planningProjectionOwners)..where(
                (table) =>
                    table.userId.equals(userId) &
                    table.organizationId.equals(organizationId),
              ))
              .getSingleOrNull();
      final nextSnapshotVersion = (currentOwner?.snapshotVersion ?? 0) + 1;

      await deletePlanningProjection(
        userId: userId,
        organizationId: organizationId,
      );
      _ensureProjectionCurrent(shouldContinue);

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
      _ensureProjectionCurrent(shouldContinue);

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
                  slug: plan.slug,
                  name: plan.name,
                  description: Value(plan.description),
                  scheduledFor: Value(plan.scheduledFor?.toUtc()),
                  updatedAt: plan.updatedAt.toUtc(),
                  version: plan.version,
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
                  slug: session.slug,
                  position: session.position,
                  name: session.name,
                  version: session.version,
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
      _ensureProjectionCurrent(shouldContinue);
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
        await (_database.select(_database.cachedPlanningPlans)
              ..where(
                (table) =>
                    table.userId.equals(userId) &
                    table.organizationId.equals(organizationId) &
                    table.snapshotVersion.equals(owner.snapshotVersion),
              )
              ..orderBy([
                (table) => OrderingTerm.asc(
                  table.scheduledFor,
                  nulls: NullsOrder.last,
                ),
                (table) => OrderingTerm.desc(table.updatedAt),
                (table) => OrderingTerm.asc(table.planId),
              ]))
            .get();

    return rows.map(_toPlanSummary).toList(growable: false);
  }

  @override
  Future<PlanSummary?> readPlanSummaryBySlug({
    required String userId,
    required String organizationId,
    required String planSlug,
  }) async {
    final owner = await _readOwner(
      userId: userId,
      organizationId: organizationId,
    );
    if (owner == null) {
      return null;
    }

    final row =
        await (_database.select(_database.cachedPlanningPlans)..where(
              (table) =>
                  table.userId.equals(userId) &
                  table.organizationId.equals(organizationId) &
                  table.snapshotVersion.equals(owner.snapshotVersion) &
                  table.slug.equals(planSlug),
            ))
            .getSingleOrNull();
    return row == null ? null : _toPlanSummary(row);
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
        await (_database.select(_database.cachedPlanningSessions)
              ..where(
                (table) =>
                    table.userId.equals(userId) &
                    table.organizationId.equals(organizationId) &
                    table.snapshotVersion.equals(owner.snapshotVersion) &
                    table.planId.equals(planId),
              )
              ..orderBy([
                (table) => OrderingTerm.asc(table.position),
                (table) => OrderingTerm.asc(table.sessionId),
              ]))
            .get();

    final itemRows =
        await (_database.select(_database.cachedPlanningSessionItems)
              ..where(
                (table) =>
                    table.userId.equals(userId) &
                    table.organizationId.equals(organizationId) &
                    table.snapshotVersion.equals(owner.snapshotVersion) &
                    table.planId.equals(planId),
              )
              ..orderBy([
                (table) => OrderingTerm.asc(table.sessionId),
                (table) => OrderingTerm.asc(table.position),
                (table) => OrderingTerm.asc(table.sessionItemId),
              ]))
            .get();

    final itemsBySessionId = <String, List<CachedPlanningSessionItem>>{};
    for (final row in itemRows) {
      itemsBySessionId.putIfAbsent(row.sessionId, () => []).add(row);
    }
    return PlanDetail(
      plan: _toPlanSummary(planRow),
      sessions: sessionRows
          .map(
            (session) => SessionSummary(
              id: session.sessionId,
              slug: session.slug,
              name: session.name,
              position: session.position,
              version: session.version,
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
  Future<PlanDetail?> readPlanDetailBySlug({
    required String userId,
    required String organizationId,
    required String planSlug,
  }) async {
    final summary = await readPlanSummaryBySlug(
      userId: userId,
      organizationId: organizationId,
      planSlug: planSlug,
    );
    if (summary == null) {
      return null;
    }

    return readPlanDetail(
      userId: userId,
      organizationId: organizationId,
      planId: summary.id,
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
  Future<int> countSongReferences({
    required String userId,
    required String organizationId,
    required String songId,
  }) async {
    final owner = await _readOwner(
      userId: userId,
      organizationId: organizationId,
    );
    if (owner == null) {
      return 0;
    }

    final countExpression = _database.cachedPlanningSessionItems.sessionItemId
        .count();
    final query = _database.selectOnly(_database.cachedPlanningSessionItems)
      ..addColumns([countExpression])
      ..where(
        _database.cachedPlanningSessionItems.userId.equals(userId) &
            _database.cachedPlanningSessionItems.organizationId.equals(
              organizationId,
            ) &
            _database.cachedPlanningSessionItems.snapshotVersion.equals(
              owner.snapshotVersion,
            ) &
            _database.cachedPlanningSessionItems.songId.equals(songId),
      );
    final row = await query.getSingle();
    return row.read(countExpression) ?? 0;
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
    bool Function()? shouldContinue,
  }) async {
    await _database.transaction(() async {
      _ensureProjectionCurrent(shouldContinue);
      await (_database.delete(_database.cachedPlanningMutations)..where(
            (table) =>
                table.userId.equals(userId) &
                table.organizationId.equals(organizationId),
          ))
          .go();
      _ensureProjectionCurrent(shouldContinue);
      await (_database.delete(_database.cachedPlanningSessionItems)..where(
            (table) =>
                table.userId.equals(userId) &
                table.organizationId.equals(organizationId),
          ))
          .go();
      _ensureProjectionCurrent(shouldContinue);
      await (_database.delete(_database.cachedPlanningSessions)..where(
            (table) =>
                table.userId.equals(userId) &
                table.organizationId.equals(organizationId),
          ))
          .go();
      _ensureProjectionCurrent(shouldContinue);
      await (_database.delete(_database.cachedPlanningPlans)..where(
            (table) =>
                table.userId.equals(userId) &
                table.organizationId.equals(organizationId),
          ))
          .go();
      _ensureProjectionCurrent(shouldContinue);
      await (_database.delete(_database.planningProjectionOwners)..where(
            (table) =>
                table.userId.equals(userId) &
                table.organizationId.equals(organizationId),
          ))
          .go();
    });
  }

  @override
  Future<void> deletePlanningDataForUser({
    required String userId,
    bool Function()? shouldContinue,
  }) async {
    await _database.transaction(() async {
      _ensureProjectionCurrent(shouldContinue);
      await (_database.delete(
        _database.cachedPlanningMutations,
      )..where((table) => table.userId.equals(userId))).go();
      _ensureProjectionCurrent(shouldContinue);
      await (_database.delete(
        _database.cachedPlanningSessionItems,
      )..where((table) => table.userId.equals(userId))).go();
      _ensureProjectionCurrent(shouldContinue);
      await (_database.delete(
        _database.cachedPlanningSessions,
      )..where((table) => table.userId.equals(userId))).go();
      _ensureProjectionCurrent(shouldContinue);
      await (_database.delete(
        _database.cachedPlanningPlans,
      )..where((table) => table.userId.equals(userId))).go();
      _ensureProjectionCurrent(shouldContinue);
      await (_database.delete(
        _database.planningProjectionOwners,
      )..where((table) => table.userId.equals(userId))).go();
    });
  }

  @override
  Future<void> upsertSyncedPlan({
    required String userId,
    required String organizationId,
    required CachedPlanRecord plan,
    required DateTime refreshedAt,
  }) async {
    await _database.transaction(() async {
      final owner = await _ensureOwner(
        userId: userId,
        organizationId: organizationId,
        refreshedAt: refreshedAt,
      );
      await _database
          .into(_database.cachedPlanningPlans)
          .insertOnConflictUpdate(
            CachedPlanningPlansCompanion.insert(
              userId: userId,
              organizationId: organizationId,
              snapshotVersion: owner.snapshotVersion,
              planId: plan.id,
              slug: plan.slug,
              name: plan.name,
              description: Value(plan.description),
              scheduledFor: Value(plan.scheduledFor?.toUtc()),
              updatedAt: plan.updatedAt.toUtc(),
              version: plan.version,
            ),
          );
    });
  }

  @override
  Future<void> upsertSyncedSession({
    required String userId,
    required String organizationId,
    required CachedSessionRecord session,
    required DateTime refreshedAt,
  }) async {
    await _database.transaction(() async {
      final owner = await _ensureOwner(
        userId: userId,
        organizationId: organizationId,
        refreshedAt: refreshedAt,
      );
      await _database
          .into(_database.cachedPlanningSessions)
          .insertOnConflictUpdate(
            CachedPlanningSessionsCompanion.insert(
              userId: userId,
              organizationId: organizationId,
              snapshotVersion: owner.snapshotVersion,
              sessionId: session.id,
              planId: session.planId,
              slug: session.slug,
              position: session.position,
              name: session.name,
              version: session.version,
            ),
          );
    });
  }

  @override
  Future<void> deleteSyncedSession({
    required String userId,
    required String organizationId,
    required String sessionId,
    required DateTime refreshedAt,
  }) async {
    await _database.transaction(() async {
      final owner = await _ensureOwner(
        userId: userId,
        organizationId: organizationId,
        refreshedAt: refreshedAt,
      );
      await (_database.delete(_database.cachedPlanningSessionItems)..where(
            (table) =>
                table.userId.equals(userId) &
                table.organizationId.equals(organizationId) &
                table.snapshotVersion.equals(owner.snapshotVersion) &
                table.sessionId.equals(sessionId),
          ))
          .go();
      await (_database.delete(_database.cachedPlanningSessions)..where(
            (table) =>
                table.userId.equals(userId) &
                table.organizationId.equals(organizationId) &
                table.snapshotVersion.equals(owner.snapshotVersion) &
                table.sessionId.equals(sessionId),
          ))
          .go();
    });
  }

  @override
  Future<void> replaceSyncedSessionOrder({
    required String userId,
    required String organizationId,
    required String planId,
    required List<String> orderedSessionIds,
    List<int>? orderedSessionPositions,
    required int planVersion,
    required DateTime refreshedAt,
  }) async {
    await _database.transaction(() async {
      final owner = await _ensureOwner(
        userId: userId,
        organizationId: organizationId,
        refreshedAt: refreshedAt,
      );
      for (var index = 0; index < orderedSessionIds.length; index += 1) {
        final position =
            orderedSessionPositions != null &&
                index < orderedSessionPositions.length
            ? orderedSessionPositions[index]
            : index + 1;
        await (_database.update(_database.cachedPlanningSessions)..where(
              (table) =>
                  table.userId.equals(userId) &
                  table.organizationId.equals(organizationId) &
                  table.snapshotVersion.equals(owner.snapshotVersion) &
                  table.planId.equals(planId) &
                  table.sessionId.equals(orderedSessionIds[index]),
            ))
            .write(CachedPlanningSessionsCompanion(position: Value(position)));
      }
      await (_database.update(_database.cachedPlanningPlans)..where(
            (table) =>
                table.userId.equals(userId) &
                table.organizationId.equals(organizationId) &
                table.snapshotVersion.equals(owner.snapshotVersion) &
                table.planId.equals(planId),
          ))
          .write(CachedPlanningPlansCompanion(version: Value(planVersion)));
    });
  }

  @override
  Future<void> upsertSyncedSessionItem({
    required String userId,
    required String organizationId,
    required CachedSessionItemRecord item,
    required int sessionVersion,
    required DateTime refreshedAt,
  }) async {
    await _database.transaction(() async {
      final owner = await _ensureOwner(
        userId: userId,
        organizationId: organizationId,
        refreshedAt: refreshedAt,
      );
      await _database
          .into(_database.cachedPlanningSessionItems)
          .insertOnConflictUpdate(
            CachedPlanningSessionItemsCompanion.insert(
              userId: userId,
              organizationId: organizationId,
              snapshotVersion: owner.snapshotVersion,
              sessionItemId: item.id,
              planId: item.planId,
              sessionId: item.sessionId,
              position: item.position,
              songId: item.songId,
              songTitle: item.songTitle,
            ),
          );
      await (_database.update(_database.cachedPlanningSessions)..where(
            (table) =>
                table.userId.equals(userId) &
                table.organizationId.equals(organizationId) &
                table.snapshotVersion.equals(owner.snapshotVersion) &
                table.sessionId.equals(item.sessionId),
          ))
          .write(
            CachedPlanningSessionsCompanion(version: Value(sessionVersion)),
          );
    });
  }

  @override
  Future<void> deleteSyncedSessionItem({
    required String userId,
    required String organizationId,
    required String sessionId,
    required String sessionItemId,
    required int sessionVersion,
    required DateTime refreshedAt,
  }) async {
    await _database.transaction(() async {
      final owner = await _ensureOwner(
        userId: userId,
        organizationId: organizationId,
        refreshedAt: refreshedAt,
      );
      await (_database.delete(_database.cachedPlanningSessionItems)..where(
            (table) =>
                table.userId.equals(userId) &
                table.organizationId.equals(organizationId) &
                table.snapshotVersion.equals(owner.snapshotVersion) &
                table.sessionItemId.equals(sessionItemId),
          ))
          .go();
      await (_database.update(_database.cachedPlanningSessions)..where(
            (table) =>
                table.userId.equals(userId) &
                table.organizationId.equals(organizationId) &
                table.snapshotVersion.equals(owner.snapshotVersion) &
                table.sessionId.equals(sessionId),
          ))
          .write(
            CachedPlanningSessionsCompanion(version: Value(sessionVersion)),
          );
    });
  }

  @override
  Future<void> replaceSyncedSessionItemOrder({
    required String userId,
    required String organizationId,
    required String sessionId,
    required List<String> orderedSessionItemIds,
    List<int>? orderedSessionItemPositions,
    required int sessionVersion,
    required DateTime refreshedAt,
  }) async {
    await _database.transaction(() async {
      final owner = await _ensureOwner(
        userId: userId,
        organizationId: organizationId,
        refreshedAt: refreshedAt,
      );
      for (var index = 0; index < orderedSessionItemIds.length; index += 1) {
        final position =
            orderedSessionItemPositions != null &&
                index < orderedSessionItemPositions.length
            ? orderedSessionItemPositions[index]
            : index + 1;
        await (_database.update(_database.cachedPlanningSessionItems)..where(
              (table) =>
                  table.userId.equals(userId) &
                  table.organizationId.equals(organizationId) &
                  table.snapshotVersion.equals(owner.snapshotVersion) &
                  table.sessionId.equals(sessionId) &
                  table.sessionItemId.equals(orderedSessionItemIds[index]),
            ))
            .write(
              CachedPlanningSessionItemsCompanion(position: Value(position)),
            );
      }
      await (_database.update(_database.cachedPlanningSessions)..where(
            (table) =>
                table.userId.equals(userId) &
                table.organizationId.equals(organizationId) &
                table.snapshotVersion.equals(owner.snapshotVersion) &
                table.sessionId.equals(sessionId),
          ))
          .write(
            CachedPlanningSessionsCompanion(version: Value(sessionVersion)),
          );
    });
  }

  Future<PlanningProjectionOwner> _ensureOwner({
    required String userId,
    required String organizationId,
    required DateTime refreshedAt,
  }) async {
    final existingOwner = await _readOwner(
      userId: userId,
      organizationId: organizationId,
    );
    if (existingOwner != null) {
      await (_database.update(_database.planningProjectionOwners)..where(
            (table) =>
                table.userId.equals(userId) &
                table.organizationId.equals(organizationId),
          ))
          .write(
            PlanningProjectionOwnersCompanion(
              refreshedAt: Value(refreshedAt.toUtc()),
            ),
          );
      return existingOwner;
    }

    await _database
        .into(_database.planningProjectionOwners)
        .insert(
          PlanningProjectionOwnersCompanion.insert(
            userId: userId,
            organizationId: organizationId,
            snapshotVersion: 1,
            refreshedAt: refreshedAt.toUtc(),
          ),
        );
    return (await _readOwner(userId: userId, organizationId: organizationId))!;
  }

  Future<void> deletePlanningProjection({
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
      slug: row.slug,
      name: row.name,
      description: row.description,
      scheduledFor: row.scheduledFor?.toUtc(),
      updatedAt: row.updatedAt.toUtc(),
      version: row.version,
    );
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

  void _ensureProjectionCurrent(bool Function()? shouldContinue) {
    if (shouldContinue != null && !shouldContinue()) {
      throw const PlanningProjectionAbortedException();
    }
  }
}
