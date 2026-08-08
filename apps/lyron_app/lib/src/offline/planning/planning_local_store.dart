import 'package:drift/drift.dart';
import 'package:lyron_app/src/application/storage/local_storage_domain_rejection.dart';
import 'package:lyron_app/src/application/storage/local_storage_footprint_revision.dart';
import 'package:lyron_app/src/application/storage/local_storage_write_recovery.dart';
import 'package:lyron_app/src/domain/planning/plan_detail.dart';
import 'package:lyron_app/src/domain/planning/plan_summary.dart';
import 'package:lyron_app/src/domain/planning/session_item_summary.dart';
import 'package:lyron_app/src/domain/planning/session_summary.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';

/// Thrown by [PlanningLocalStore.replaceActiveProjection] when the caller's
/// `shouldContinue` reports that a newer refresh has superseded this one.
///
/// This is a cooperative-cancellation signal, not storage pressure: it must
/// pass through [LocalStorageWriteRecovery.guard] untouched, the same as any
/// other domain rejection, so it implements [LocalStorageDomainRejection].
/// Treating it as storage pressure would evict droppable catalog sources for
/// no reason and retry into the same abort.
class PlanningProjectionAbortedException
    implements LocalStorageDomainRejection {
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
  const DriftPlanningLocalStore(
    this._database, {
    this._onStorageFootprintChanged,
    this._writeRecovery,
  });

  final PlanningLocalDatabase _database;
  final LocalStorageFootprintChanged? _onStorageFootprintChanged;

  /// Guards every local write that can increase stored bytes: a projection
  /// replacement or synced upsert that fails at the storage layer gets one
  /// eviction-and-retry before surfacing a typed [LocalStorageWriteFailure]
  /// (LF-T4, D1). `null` in tests that construct this store directly --
  /// production wiring always supplies it, mirroring how
  /// [_onStorageFootprintChanged] is injected.
  final LocalStorageWriteRecovery? _writeRecovery;

  Future<T> _guarded<T>(Future<T> Function() write) {
    final recovery = _writeRecovery;
    return recovery == null ? write() : recovery.guard(write);
  }

  @override
  Future<void> replaceActiveProjection({
    required String userId,
    required String organizationId,
    required List<CachedPlanRecord> plans,
    required List<CachedSessionRecord> sessions,
    required List<CachedSessionItemRecord> items,
    required DateTime refreshedAt,
    bool Function()? shouldContinue,
  }) => _guarded(
    () => _replaceActiveProjection(
      userId: userId,
      organizationId: organizationId,
      plans: plans,
      sessions: sessions,
      items: items,
      refreshedAt: refreshedAt,
      shouldContinue: shouldContinue,
    ),
  );

  Future<void> _replaceActiveProjection({
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

      await _deletePlanningProjectionRows(
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
    _onStorageFootprintChanged?.call();
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
    final deletedRows = await _database.transaction(() async {
      var deletedRows = 0;
      _ensureProjectionCurrent(shouldContinue);
      deletedRows +=
          await (_database.delete(_database.cachedPlanningMutations)..where(
                (table) =>
                    table.userId.equals(userId) &
                    table.organizationId.equals(organizationId),
              ))
              .go();
      _ensureProjectionCurrent(shouldContinue);
      deletedRows +=
          await (_database.delete(_database.cachedPlanningSessionItems)..where(
                (table) =>
                    table.userId.equals(userId) &
                    table.organizationId.equals(organizationId),
              ))
              .go();
      _ensureProjectionCurrent(shouldContinue);
      deletedRows +=
          await (_database.delete(_database.cachedPlanningSessions)..where(
                (table) =>
                    table.userId.equals(userId) &
                    table.organizationId.equals(organizationId),
              ))
              .go();
      _ensureProjectionCurrent(shouldContinue);
      deletedRows +=
          await (_database.delete(_database.cachedPlanningPlans)..where(
                (table) =>
                    table.userId.equals(userId) &
                    table.organizationId.equals(organizationId),
              ))
              .go();
      _ensureProjectionCurrent(shouldContinue);
      deletedRows +=
          await (_database.delete(_database.planningProjectionOwners)..where(
                (table) =>
                    table.userId.equals(userId) &
                    table.organizationId.equals(organizationId),
              ))
              .go();
      return deletedRows;
    });
    if (deletedRows > 0) {
      _onStorageFootprintChanged?.call();
    }
  }

  @override
  Future<void> deletePlanningDataForUser({
    required String userId,
    bool Function()? shouldContinue,
  }) async {
    final deletedRows = await _database.transaction(() async {
      var deletedRows = 0;
      _ensureProjectionCurrent(shouldContinue);
      deletedRows += await (_database.delete(
        _database.cachedPlanningMutations,
      )..where((table) => table.userId.equals(userId))).go();
      _ensureProjectionCurrent(shouldContinue);
      deletedRows += await (_database.delete(
        _database.cachedPlanningSessionItems,
      )..where((table) => table.userId.equals(userId))).go();
      _ensureProjectionCurrent(shouldContinue);
      deletedRows += await (_database.delete(
        _database.cachedPlanningSessions,
      )..where((table) => table.userId.equals(userId))).go();
      _ensureProjectionCurrent(shouldContinue);
      deletedRows += await (_database.delete(
        _database.cachedPlanningPlans,
      )..where((table) => table.userId.equals(userId))).go();
      _ensureProjectionCurrent(shouldContinue);
      deletedRows += await (_database.delete(
        _database.planningProjectionOwners,
      )..where((table) => table.userId.equals(userId))).go();
      return deletedRows;
    });
    if (deletedRows > 0) {
      _onStorageFootprintChanged?.call();
    }
  }

  @override
  Future<void> upsertSyncedPlan({
    required String userId,
    required String organizationId,
    required CachedPlanRecord plan,
    required DateTime refreshedAt,
  }) => _guarded(
    () => _upsertSyncedPlan(
      userId: userId,
      organizationId: organizationId,
      plan: plan,
      refreshedAt: refreshedAt,
    ),
  );

  Future<void> _upsertSyncedPlan({
    required String userId,
    required String organizationId,
    required CachedPlanRecord plan,
    required DateTime refreshedAt,
  }) async {
    final changed = await _database.transaction(() async {
      final ensuredOwner = await _ensureOwner(
        userId: userId,
        organizationId: organizationId,
        refreshedAt: refreshedAt,
      );
      final rowChanged = await _upsertPlanRow(
        userId: userId,
        organizationId: organizationId,
        snapshotVersion: ensuredOwner.owner.snapshotVersion,
        plan: plan,
      );
      return ensuredOwner.changed || rowChanged;
    });
    if (changed) {
      _onStorageFootprintChanged?.call();
    }
  }

  @override
  Future<void> upsertSyncedSession({
    required String userId,
    required String organizationId,
    required CachedSessionRecord session,
    required DateTime refreshedAt,
  }) => _guarded(
    () => _upsertSyncedSession(
      userId: userId,
      organizationId: organizationId,
      session: session,
      refreshedAt: refreshedAt,
    ),
  );

  Future<void> _upsertSyncedSession({
    required String userId,
    required String organizationId,
    required CachedSessionRecord session,
    required DateTime refreshedAt,
  }) async {
    final changed = await _database.transaction(() async {
      final ensuredOwner = await _ensureOwner(
        userId: userId,
        organizationId: organizationId,
        refreshedAt: refreshedAt,
      );
      final rowChanged = await _upsertSessionRow(
        userId: userId,
        organizationId: organizationId,
        snapshotVersion: ensuredOwner.owner.snapshotVersion,
        session: session,
      );
      return ensuredOwner.changed || rowChanged;
    });
    if (changed) {
      _onStorageFootprintChanged?.call();
    }
  }

  @override
  Future<void> deleteSyncedSession({
    required String userId,
    required String organizationId,
    required String sessionId,
    required DateTime refreshedAt,
  }) async {
    final changed = await _database.transaction(() async {
      final ensuredOwner = await _ensureOwner(
        userId: userId,
        organizationId: organizationId,
        refreshedAt: refreshedAt,
      );
      var changed = ensuredOwner.changed;
      final owner = ensuredOwner.owner;
      changed =
          await (_database.delete(_database.cachedPlanningSessionItems)..where(
                    (table) =>
                        table.userId.equals(userId) &
                        table.organizationId.equals(organizationId) &
                        table.snapshotVersion.equals(owner.snapshotVersion) &
                        table.sessionId.equals(sessionId),
                  ))
                  .go() >
              0 ||
          changed;
      changed =
          await (_database.delete(_database.cachedPlanningSessions)..where(
                    (table) =>
                        table.userId.equals(userId) &
                        table.organizationId.equals(organizationId) &
                        table.snapshotVersion.equals(owner.snapshotVersion) &
                        table.sessionId.equals(sessionId),
                  ))
                  .go() >
              0 ||
          changed;
      return changed;
    });
    if (changed) {
      _onStorageFootprintChanged?.call();
    }
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
    final changed = await _database.transaction(() async {
      final ensuredOwner = await _ensureOwner(
        userId: userId,
        organizationId: organizationId,
        refreshedAt: refreshedAt,
      );
      final owner = ensuredOwner.owner;
      var changed = ensuredOwner.changed;
      for (var index = 0; index < orderedSessionIds.length; index += 1) {
        final position =
            orderedSessionPositions != null &&
                index < orderedSessionPositions.length
            ? orderedSessionPositions[index]
            : index + 1;
        final updatedRows =
            await (_database.update(_database.cachedPlanningSessions)..where(
                  (table) =>
                      table.userId.equals(userId) &
                      table.organizationId.equals(organizationId) &
                      table.snapshotVersion.equals(owner.snapshotVersion) &
                      table.planId.equals(planId) &
                      table.sessionId.equals(orderedSessionIds[index]) &
                      table.position.equals(position).not(),
                ))
                .write(
                  CachedPlanningSessionsCompanion(position: Value(position)),
                );
        changed = updatedRows > 0 || changed;
      }
      final updatedPlanRows =
          await (_database.update(_database.cachedPlanningPlans)..where(
                (table) =>
                    table.userId.equals(userId) &
                    table.organizationId.equals(organizationId) &
                    table.snapshotVersion.equals(owner.snapshotVersion) &
                    table.planId.equals(planId) &
                    table.version.equals(planVersion).not(),
              ))
              .write(CachedPlanningPlansCompanion(version: Value(planVersion)));
      return updatedPlanRows > 0 || changed;
    });
    if (changed) {
      _onStorageFootprintChanged?.call();
    }
  }

  @override
  Future<void> upsertSyncedSessionItem({
    required String userId,
    required String organizationId,
    required CachedSessionItemRecord item,
    required int sessionVersion,
    required DateTime refreshedAt,
  }) => _guarded(
    () => _upsertSyncedSessionItem(
      userId: userId,
      organizationId: organizationId,
      item: item,
      sessionVersion: sessionVersion,
      refreshedAt: refreshedAt,
    ),
  );

  Future<void> _upsertSyncedSessionItem({
    required String userId,
    required String organizationId,
    required CachedSessionItemRecord item,
    required int sessionVersion,
    required DateTime refreshedAt,
  }) async {
    final changed = await _database.transaction(() async {
      final ensuredOwner = await _ensureOwner(
        userId: userId,
        organizationId: organizationId,
        refreshedAt: refreshedAt,
      );
      final owner = ensuredOwner.owner;
      var changed = ensuredOwner.changed;
      changed =
          await _upsertSessionItemRow(
            userId: userId,
            organizationId: organizationId,
            snapshotVersion: owner.snapshotVersion,
            item: item,
          ) ||
          changed;
      final updatedSessionRows =
          await (_database.update(_database.cachedPlanningSessions)..where(
                (table) =>
                    table.userId.equals(userId) &
                    table.organizationId.equals(organizationId) &
                    table.snapshotVersion.equals(owner.snapshotVersion) &
                    table.sessionId.equals(item.sessionId) &
                    table.version.equals(sessionVersion).not(),
              ))
              .write(
                CachedPlanningSessionsCompanion(version: Value(sessionVersion)),
              );
      return updatedSessionRows > 0 || changed;
    });
    if (changed) {
      _onStorageFootprintChanged?.call();
    }
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
    final changed = await _database.transaction(() async {
      final ensuredOwner = await _ensureOwner(
        userId: userId,
        organizationId: organizationId,
        refreshedAt: refreshedAt,
      );
      final owner = ensuredOwner.owner;
      var changed = ensuredOwner.changed;
      changed =
          await (_database.delete(_database.cachedPlanningSessionItems)..where(
                    (table) =>
                        table.userId.equals(userId) &
                        table.organizationId.equals(organizationId) &
                        table.snapshotVersion.equals(owner.snapshotVersion) &
                        table.sessionItemId.equals(sessionItemId),
                  ))
                  .go() >
              0 ||
          changed;
      final updatedSessionRows =
          await (_database.update(_database.cachedPlanningSessions)..where(
                (table) =>
                    table.userId.equals(userId) &
                    table.organizationId.equals(organizationId) &
                    table.snapshotVersion.equals(owner.snapshotVersion) &
                    table.sessionId.equals(sessionId) &
                    table.version.equals(sessionVersion).not(),
              ))
              .write(
                CachedPlanningSessionsCompanion(version: Value(sessionVersion)),
              );
      return updatedSessionRows > 0 || changed;
    });
    if (changed) {
      _onStorageFootprintChanged?.call();
    }
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
    final changed = await _database.transaction(() async {
      final ensuredOwner = await _ensureOwner(
        userId: userId,
        organizationId: organizationId,
        refreshedAt: refreshedAt,
      );
      final owner = ensuredOwner.owner;
      var changed = ensuredOwner.changed;
      for (var index = 0; index < orderedSessionItemIds.length; index += 1) {
        final position =
            orderedSessionItemPositions != null &&
                index < orderedSessionItemPositions.length
            ? orderedSessionItemPositions[index]
            : index + 1;
        final updatedRows =
            await (_database.update(
                  _database.cachedPlanningSessionItems,
                )..where(
                  (table) =>
                      table.userId.equals(userId) &
                      table.organizationId.equals(organizationId) &
                      table.snapshotVersion.equals(owner.snapshotVersion) &
                      table.sessionId.equals(sessionId) &
                      table.sessionItemId.equals(orderedSessionItemIds[index]) &
                      table.position.equals(position).not(),
                ))
                .write(
                  CachedPlanningSessionItemsCompanion(
                    position: Value(position),
                  ),
                );
        changed = updatedRows > 0 || changed;
      }
      final updatedSessionRows =
          await (_database.update(_database.cachedPlanningSessions)..where(
                (table) =>
                    table.userId.equals(userId) &
                    table.organizationId.equals(organizationId) &
                    table.snapshotVersion.equals(owner.snapshotVersion) &
                    table.sessionId.equals(sessionId) &
                    table.version.equals(sessionVersion).not(),
              ))
              .write(
                CachedPlanningSessionsCompanion(version: Value(sessionVersion)),
              );
      return updatedSessionRows > 0 || changed;
    });
    if (changed) {
      _onStorageFootprintChanged?.call();
    }
  }

  Future<bool> _upsertPlanRow({
    required String userId,
    required String organizationId,
    required int snapshotVersion,
    required CachedPlanRecord plan,
  }) async {
    final existing =
        await (_database.select(_database.cachedPlanningPlans)..where(
              (table) =>
                  table.userId.equals(userId) &
                  table.organizationId.equals(organizationId) &
                  table.snapshotVersion.equals(snapshotVersion) &
                  table.planId.equals(plan.id),
            ))
            .getSingleOrNull();
    if (existing != null &&
        existing.slug == plan.slug &&
        existing.name == plan.name &&
        existing.description == plan.description &&
        existing.scheduledFor?.toUtc() == plan.scheduledFor?.toUtc() &&
        existing.updatedAt.toUtc() == plan.updatedAt.toUtc() &&
        existing.version == plan.version) {
      return false;
    }
    await _database
        .into(_database.cachedPlanningPlans)
        .insertOnConflictUpdate(
          CachedPlanningPlansCompanion.insert(
            userId: userId,
            organizationId: organizationId,
            snapshotVersion: snapshotVersion,
            planId: plan.id,
            slug: plan.slug,
            name: plan.name,
            description: Value(plan.description),
            scheduledFor: Value(plan.scheduledFor?.toUtc()),
            updatedAt: plan.updatedAt.toUtc(),
            version: plan.version,
          ),
        );
    return true;
  }

  Future<bool> _upsertSessionRow({
    required String userId,
    required String organizationId,
    required int snapshotVersion,
    required CachedSessionRecord session,
  }) async {
    final existing =
        await (_database.select(_database.cachedPlanningSessions)..where(
              (table) =>
                  table.userId.equals(userId) &
                  table.organizationId.equals(organizationId) &
                  table.snapshotVersion.equals(snapshotVersion) &
                  table.sessionId.equals(session.id),
            ))
            .getSingleOrNull();
    if (existing != null &&
        existing.planId == session.planId &&
        existing.slug == session.slug &&
        existing.position == session.position &&
        existing.name == session.name &&
        existing.version == session.version) {
      return false;
    }
    await _database
        .into(_database.cachedPlanningSessions)
        .insertOnConflictUpdate(
          CachedPlanningSessionsCompanion.insert(
            userId: userId,
            organizationId: organizationId,
            snapshotVersion: snapshotVersion,
            sessionId: session.id,
            planId: session.planId,
            slug: session.slug,
            position: session.position,
            name: session.name,
            version: session.version,
          ),
        );
    return true;
  }

  Future<bool> _upsertSessionItemRow({
    required String userId,
    required String organizationId,
    required int snapshotVersion,
    required CachedSessionItemRecord item,
  }) async {
    final existing =
        await (_database.select(_database.cachedPlanningSessionItems)..where(
              (table) =>
                  table.userId.equals(userId) &
                  table.organizationId.equals(organizationId) &
                  table.snapshotVersion.equals(snapshotVersion) &
                  table.sessionItemId.equals(item.id),
            ))
            .getSingleOrNull();
    if (existing != null &&
        existing.planId == item.planId &&
        existing.sessionId == item.sessionId &&
        existing.position == item.position &&
        existing.songId == item.songId &&
        existing.songTitle == item.songTitle) {
      return false;
    }
    await _database
        .into(_database.cachedPlanningSessionItems)
        .insertOnConflictUpdate(
          CachedPlanningSessionItemsCompanion.insert(
            userId: userId,
            organizationId: organizationId,
            snapshotVersion: snapshotVersion,
            sessionItemId: item.id,
            planId: item.planId,
            sessionId: item.sessionId,
            position: item.position,
            songId: item.songId,
            songTitle: item.songTitle,
          ),
        );
    return true;
  }

  Future<_EnsuredProjectionOwner> _ensureOwner({
    required String userId,
    required String organizationId,
    required DateTime refreshedAt,
  }) async {
    final existingOwner = await _readOwner(
      userId: userId,
      organizationId: organizationId,
    );
    if (existingOwner != null) {
      final changed = existingOwner.refreshedAt.toUtc() != refreshedAt.toUtc();
      if (changed) {
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
      }
      return _EnsuredProjectionOwner(owner: existingOwner, changed: changed);
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
    return _EnsuredProjectionOwner(
      owner: (await _readOwner(
        userId: userId,
        organizationId: organizationId,
      ))!,
      changed: true,
    );
  }

  Future<void> deletePlanningProjection({
    required String userId,
    required String organizationId,
  }) async {
    final deletedRows = await _database.transaction(
      () => _deletePlanningProjectionRows(
        userId: userId,
        organizationId: organizationId,
      ),
    );
    if (deletedRows > 0) {
      _onStorageFootprintChanged?.call();
    }
  }

  Future<int> _deletePlanningProjectionRows({
    required String userId,
    required String organizationId,
  }) async {
    var deletedRows = 0;
    deletedRows +=
        await (_database.delete(_database.cachedPlanningSessionItems)..where(
              (table) =>
                  table.userId.equals(userId) &
                  table.organizationId.equals(organizationId),
            ))
            .go();
    deletedRows +=
        await (_database.delete(_database.cachedPlanningSessions)..where(
              (table) =>
                  table.userId.equals(userId) &
                  table.organizationId.equals(organizationId),
            ))
            .go();
    deletedRows +=
        await (_database.delete(_database.cachedPlanningPlans)..where(
              (table) =>
                  table.userId.equals(userId) &
                  table.organizationId.equals(organizationId),
            ))
            .go();
    deletedRows +=
        await (_database.delete(_database.planningProjectionOwners)..where(
              (table) =>
                  table.userId.equals(userId) &
                  table.organizationId.equals(organizationId),
            ))
            .go();
    return deletedRows;
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

class _EnsuredProjectionOwner {
  const _EnsuredProjectionOwner({required this.owner, required this.changed});

  final PlanningProjectionOwner owner;
  final bool changed;
}
