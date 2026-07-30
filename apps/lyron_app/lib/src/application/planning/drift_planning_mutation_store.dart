import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:drift/drift.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';

class DriftPlanningMutationStore implements PlanningMutationStore {
  const DriftPlanningMutationStore({
    required PlanningLocalDatabase database,
    required PlanningLocalStore localStore,
  }) : _database = database,
       _localStore = localStore;

  final PlanningLocalDatabase _database;
  final PlanningLocalStore _localStore;

  @override
  Future<void> recordPlanCreate({
    required PlanningMutationContext context,
    required PlanningPlanCreateMutationDraft draft,
  }) async {
    await _database.transaction(() async {
      if (await _hasReservedPlanSlug(
        userId: context.userId,
        organizationId: context.organizationId,
        slug: draft.slug,
        excludingAggregateId: draft.planId,
      )) {
        throw const LocalPlanningSlugConflictException();
      }

      await _upsertRecord(
        context: context,
        aggregateType: 'plan',
        record: PlanningMutationRecord(
          aggregateId: draft.planId,
          organizationId: context.organizationId,
          kind: PlanningMutationKind.planCreate,
          syncStatus: PlanningMutationSyncStatus.pending,
          orderKey: await _nextOrderKey(
            userId: context.userId,
            organizationId: context.organizationId,
          ),
          updatedAt: DateTime.now().toUtc(),
          slug: draft.slug,
          name: draft.name,
          description: draft.description,
          scheduledFor: draft.scheduledFor?.toUtc(),
        ),
      );
    });
  }

  @override
  Future<void> recordPlanEdit({
    required PlanningMutationContext context,
    required PlanningPlanEditMutationDraft draft,
  }) async {
    await _database.transaction(() async {
      final existing = await readMutation(
        userId: context.userId,
        organizationId: context.organizationId,
        aggregateType: PlanningMutationKind.planEdit.aggregateType,
        aggregateId: draft.planId,
      );
      if (existing?.kind == PlanningMutationKind.planCreate) {
        // A planEdit draft always carries the complete form state (see
        // PlanEditDraft's single construction site in
        // plan_editor_dialog.dart), so a null description/scheduledFor here
        // means the user explicitly cleared the field, not "leave it
        // unchanged". Folding the edit into a still-pending create must
        // therefore pass the clear flags, or copyWith's `?? this.x` shape
        // would silently keep the pre-edit value.
        await _upsertRecord(
          context: context,
          aggregateType: 'plan',
          record: existing!.copyWith(
            name: draft.name,
            description: draft.description,
            clearDescription: draft.description == null,
            scheduledFor: draft.scheduledFor?.toUtc(),
            clearScheduledFor: draft.scheduledFor == null,
            updatedAt: DateTime.now().toUtc(),
          ),
        );
        return;
      }

      await _upsertRecord(
        context: context,
        aggregateType: 'plan',
        record: PlanningMutationRecord(
          aggregateId: draft.planId,
          organizationId: context.organizationId,
          kind: PlanningMutationKind.planEdit,
          syncStatus: PlanningMutationSyncStatus.pending,
          orderKey:
              existing?.orderKey ??
              await _nextOrderKey(
                userId: context.userId,
                organizationId: context.organizationId,
              ),
          updatedAt: DateTime.now().toUtc(),
          name: draft.name,
          description: draft.description,
          scheduledFor: draft.scheduledFor?.toUtc(),
          // OCC: keep the base version captured by the FIRST local edit.
          // draft.baseVersion comes from the locally merged read, which
          // shows the user their own pending overlay rather than a
          // refreshed remote state -- so a later local edit did not
          // actually observe a newer remote version. Rebasing to it here
          // would assert a base the user never saw and silently suppress a
          // real conflict. Explicit, user-initiated rebasing happens in
          // retryMutation via _currentBaseVersionFor.
          baseVersion: existing?.baseVersion ?? draft.baseVersion,
          originSnapshot: existing?.originSnapshot ?? draft.originSnapshot,
        ),
      );
    });
  }

  @override
  Future<void> recordSessionCreate({
    required PlanningMutationContext context,
    required PlanningSessionCreateMutationDraft draft,
  }) async {
    await _database.transaction(() async {
      if (await _hasReservedSessionSlug(
        userId: context.userId,
        organizationId: context.organizationId,
        planId: draft.planId,
        slug: draft.slug,
        excludingAggregateId: draft.sessionId,
      )) {
        throw const LocalPlanningSlugConflictException();
      }

      await _upsertRecord(
        context: context,
        aggregateType: 'session',
        record: PlanningMutationRecord(
          aggregateId: draft.sessionId,
          organizationId: context.organizationId,
          planId: draft.planId,
          slug: draft.slug,
          name: draft.name,
          position: draft.position,
          kind: PlanningMutationKind.sessionCreate,
          syncStatus: PlanningMutationSyncStatus.pending,
          orderKey: await _nextOrderKey(
            userId: context.userId,
            organizationId: context.organizationId,
          ),
          updatedAt: DateTime.now().toUtc(),
        ),
      );
    });
  }

  @override
  Future<void> recordSessionRename({
    required PlanningMutationContext context,
    required PlanningSessionRenameMutationDraft draft,
  }) async {
    await _database.transaction(() async {
      final existing = await readMutation(
        userId: context.userId,
        organizationId: context.organizationId,
        aggregateType: PlanningMutationKind.sessionRename.aggregateType,
        aggregateId: draft.sessionId,
      );
      if (existing?.kind == PlanningMutationKind.sessionCreate) {
        await _upsertRecord(
          context: context,
          aggregateType: 'session',
          record: existing!.copyWith(
            name: draft.name,
            updatedAt: DateTime.now().toUtc(),
          ),
        );
        return;
      }

      await _upsertRecord(
        context: context,
        aggregateType: 'session',
        record: PlanningMutationRecord(
          aggregateId: draft.sessionId,
          organizationId: context.organizationId,
          planId: draft.planId,
          name: draft.name,
          baseVersion: existing?.baseVersion ?? draft.baseVersion,
          kind: PlanningMutationKind.sessionRename,
          syncStatus: PlanningMutationSyncStatus.pending,
          orderKey:
              existing?.orderKey ??
              await _nextOrderKey(
                userId: context.userId,
                organizationId: context.organizationId,
              ),
          updatedAt: DateTime.now().toUtc(),
          originSnapshot: existing?.originSnapshot ?? draft.originSnapshot,
        ),
      );
    });
  }

  @override
  Future<void> recordSessionDelete({
    required PlanningMutationContext context,
    required PlanningSessionDeleteMutationDraft draft,
  }) async {
    await _database.transaction(() async {
      final existing = await readMutation(
        userId: context.userId,
        organizationId: context.organizationId,
        aggregateType: PlanningMutationKind.sessionDelete.aggregateType,
        aggregateId: draft.sessionId,
      );
      if (existing?.kind == PlanningMutationKind.sessionCreate) {
        await (_database.delete(_database.cachedPlanningMutations)..where(
              (table) =>
                  table.userId.equals(context.userId) &
                  table.organizationId.equals(context.organizationId) &
                  table.aggregateType.equals('session') &
                  table.aggregateId.equals(draft.sessionId),
            ))
            .go();
        await _removeSessionFromPendingReorder(
          context: context,
          planId: draft.planId,
          sessionId: draft.sessionId,
        );
        return;
      }

      await _upsertRecord(
        context: context,
        aggregateType: 'session',
        record: PlanningMutationRecord(
          aggregateId: draft.sessionId,
          organizationId: context.organizationId,
          planId: draft.planId,
          baseVersion: existing?.baseVersion ?? draft.baseVersion,
          kind: PlanningMutationKind.sessionDelete,
          syncStatus: PlanningMutationSyncStatus.pending,
          orderKey:
              existing?.orderKey ??
              await _nextOrderKey(
                userId: context.userId,
                organizationId: context.organizationId,
              ),
          updatedAt: DateTime.now().toUtc(),
          originSnapshot: existing?.originSnapshot ?? draft.originSnapshot,
        ),
      );
      await _removeSessionFromPendingReorder(
        context: context,
        planId: draft.planId,
        sessionId: draft.sessionId,
      );
    });
  }

  @override
  Future<void> recordSessionReorder({
    required PlanningMutationContext context,
    required PlanningSessionReorderMutationDraft draft,
  }) async {
    await _database.transaction(() async {
      final existing = await _readMutationByKey(
        userId: context.userId,
        organizationId: context.organizationId,
        aggregateType: 'session_order',
        aggregateId: draft.planId,
      );
      await _upsertRecord(
        context: context,
        aggregateType: 'session_order',
        record: PlanningMutationRecord(
          aggregateId: draft.planId,
          organizationId: context.organizationId,
          planId: draft.planId,
          kind: PlanningMutationKind.sessionReorder,
          syncStatus: PlanningMutationSyncStatus.pending,
          orderKey:
              existing?.orderKey ??
              await _nextOrderKey(
                userId: context.userId,
                organizationId: context.organizationId,
              ),
          updatedAt: DateTime.now().toUtc(),
          orderedSiblingIds: draft.orderedSessionIds,
          baseVersion: existing?.baseVersion ?? draft.baseVersion,
          originSnapshot: existing?.originSnapshot ?? draft.originSnapshot,
        ),
      );
    });
  }

  @override
  Future<void> recordSessionItemCreateSong({
    required PlanningMutationContext context,
    required PlanningSessionItemCreateSongMutationDraft draft,
  }) async {
    await _database.transaction(() async {
      await _upsertRecord(
        context: context,
        aggregateType: 'session_item',
        record: PlanningMutationRecord(
          aggregateId: draft.sessionItemId,
          organizationId: context.organizationId,
          planId: draft.planId,
          sessionId: draft.sessionId,
          songId: draft.songId,
          songTitle: draft.songTitle,
          position: draft.position,
          kind: PlanningMutationKind.sessionItemCreateSong,
          syncStatus: PlanningMutationSyncStatus.pending,
          orderKey: await _nextOrderKey(
            userId: context.userId,
            organizationId: context.organizationId,
          ),
          updatedAt: DateTime.now().toUtc(),
          baseVersion: draft.baseVersion,
          originSnapshot: draft.originSnapshot,
        ),
      );
    });
  }

  @override
  Future<void> recordSessionItemDelete({
    required PlanningMutationContext context,
    required PlanningSessionItemDeleteMutationDraft draft,
  }) async {
    await _database.transaction(() async {
      final existing = await _readMutationByKey(
        userId: context.userId,
        organizationId: context.organizationId,
        aggregateType: 'session_item',
        aggregateId: draft.sessionItemId,
      );
      if (existing?.kind == PlanningMutationKind.sessionItemCreateSong) {
        await (_database.delete(_database.cachedPlanningMutations)..where(
              (table) =>
                  table.userId.equals(context.userId) &
                  table.organizationId.equals(context.organizationId) &
                  table.aggregateType.equals('session_item') &
                  table.aggregateId.equals(draft.sessionItemId),
            ))
            .go();
        await _removeSessionItemFromPendingReorder(
          context: context,
          sessionId: draft.sessionId,
          sessionItemId: draft.sessionItemId,
        );
        return;
      }

      await _upsertRecord(
        context: context,
        aggregateType: 'session_item',
        record: PlanningMutationRecord(
          aggregateId: draft.sessionItemId,
          organizationId: context.organizationId,
          planId: draft.planId,
          sessionId: draft.sessionId,
          baseVersion: existing?.baseVersion ?? draft.baseVersion,
          kind: PlanningMutationKind.sessionItemDelete,
          syncStatus: PlanningMutationSyncStatus.pending,
          orderKey:
              existing?.orderKey ??
              await _nextOrderKey(
                userId: context.userId,
                organizationId: context.organizationId,
              ),
          updatedAt: DateTime.now().toUtc(),
          originSnapshot: existing?.originSnapshot ?? draft.originSnapshot,
        ),
      );
      await _removeSessionItemFromPendingReorder(
        context: context,
        sessionId: draft.sessionId,
        sessionItemId: draft.sessionItemId,
      );
    });
  }

  @override
  Future<void> recordSessionItemReorder({
    required PlanningMutationContext context,
    required PlanningSessionItemReorderMutationDraft draft,
  }) async {
    await _database.transaction(() async {
      final existing = await _readMutationByKey(
        userId: context.userId,
        organizationId: context.organizationId,
        aggregateType: 'session_item_order',
        aggregateId: draft.sessionId,
      );
      await _upsertRecord(
        context: context,
        aggregateType: 'session_item_order',
        record: PlanningMutationRecord(
          aggregateId: draft.sessionId,
          organizationId: context.organizationId,
          planId: draft.planId,
          sessionId: draft.sessionId,
          kind: PlanningMutationKind.sessionItemReorder,
          syncStatus: PlanningMutationSyncStatus.pending,
          orderKey:
              existing?.orderKey ??
              await _nextOrderKey(
                userId: context.userId,
                organizationId: context.organizationId,
              ),
          updatedAt: DateTime.now().toUtc(),
          orderedSiblingIds: draft.orderedSessionItemIds,
          baseVersion: existing?.baseVersion ?? draft.baseVersion,
          originSnapshot: existing?.originSnapshot ?? draft.originSnapshot,
        ),
      );
    });
  }

  @override
  Future<List<PlanningMutationRecord>> readPendingMutations({
    required String userId,
    required String organizationId,
  }) async {
    final rows =
        await (_database.select(_database.cachedPlanningMutations)
              ..where(
                (table) =>
                    table.userId.equals(userId) &
                    table.organizationId.equals(organizationId) &
                    table.syncStatus.equals(
                      PlanningMutationSyncStatus.pending.value,
                    ),
              )
              ..orderBy([
                (table) => OrderingTerm.asc(table.orderKey),
                (table) => OrderingTerm.asc(table.aggregateId),
              ]))
            .get();
    return rows.map(_toRecord).toList(growable: false);
  }

  @override
  Future<List<PlanningMutationRecord>> readActionableMutations({
    required String userId,
    required String organizationId,
  }) async {
    final rows =
        await (_database.select(_database.cachedPlanningMutations)
              ..where(
                (table) =>
                    table.userId.equals(userId) &
                    table.organizationId.equals(organizationId) &
                    table.syncStatus.isIn([
                      PlanningMutationSyncStatus.pending.value,
                      PlanningMutationSyncStatus.accepted.value,
                      PlanningMutationSyncStatus.failedAuthorization.value,
                      PlanningMutationSyncStatus.failedDependency.value,
                      PlanningMutationSyncStatus.failedRemoteDelete.value,
                      PlanningMutationSyncStatus.conflict.value,
                    ]),
              )
              ..orderBy([
                (table) => OrderingTerm.asc(table.orderKey),
                (table) => OrderingTerm.asc(table.aggregateId),
              ]))
            .get();
    return rows.map(_toRecord).toList(growable: false);
  }

  @override
  Future<List<PlanningMutationRecord>> readAllMutations({
    required String userId,
    required String organizationId,
  }) async {
    final rows =
        await (_database.select(_database.cachedPlanningMutations)
              ..where(
                (table) =>
                    table.userId.equals(userId) &
                    table.organizationId.equals(organizationId),
              )
              ..orderBy([
                (table) => OrderingTerm.asc(table.orderKey),
                (table) => OrderingTerm.asc(table.aggregateId),
              ]))
            .get();
    return rows.map(_toRecord).toList(growable: false);
  }

  @override
  Future<PlanningMutationRecord?> readMutation({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
  }) => _readMutationByKey(
    userId: userId,
    organizationId: organizationId,
    aggregateType: aggregateType,
    aggregateId: aggregateId,
  );

  Future<PlanningMutationRecord?> _readMutationByKey({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
  }) async {
    final row =
        await (_database.select(_database.cachedPlanningMutations)..where(
              (table) =>
                  table.userId.equals(userId) &
                  table.organizationId.equals(organizationId) &
                  table.aggregateType.equals(aggregateType) &
                  table.aggregateId.equals(aggregateId),
            ))
            .getSingleOrNull();
    return row == null ? null : _toRecord(row);
  }

  @override
  Future<String> allocatePlanSlug({
    required String userId,
    required String organizationId,
    required String name,
  }) async {
    final baseSlug = _slugify(name, fallback: 'plan');
    var candidate = baseSlug;
    var suffix = 2;

    while (await _hasReservedPlanSlug(
      userId: userId,
      organizationId: organizationId,
      slug: candidate,
    )) {
      candidate = '$baseSlug-$suffix';
      suffix += 1;
    }

    return candidate;
  }

  @override
  Future<String> allocateSessionSlug({
    required String userId,
    required String organizationId,
    required String planId,
    required String name,
  }) async {
    final baseSlug = _slugify(name, fallback: 'session');
    var candidate = baseSlug;
    var suffix = 2;

    while (await _hasReservedSessionSlug(
      userId: userId,
      organizationId: organizationId,
      planId: planId,
      slug: candidate,
    )) {
      candidate = '$baseSlug-$suffix';
      suffix += 1;
    }

    return candidate;
  }

  @override
  Future<bool> hasUnsyncedMutations({required String userId}) async {
    final countExpression = _database.cachedPlanningMutations.aggregateId
        .count();
    final query = _database.selectOnly(_database.cachedPlanningMutations)
      ..addColumns([countExpression])
      ..where(_database.cachedPlanningMutations.userId.equals(userId));
    final row = await query.getSingle();
    return (row.read(countExpression) ?? 0) > 0;
  }

  @override
  Future<void> saveSyncAttemptResult({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
    required PlanningMutationSyncStatus syncStatus,
    PlanningMutationSyncErrorCode? errorCode,
    String? errorMessage,
  }) async {
    final existing = await readMutation(
      userId: userId,
      organizationId: organizationId,
      aggregateType: aggregateType,
      aggregateId: aggregateId,
    );
    if (existing == null) {
      throw StateError('Planning mutation record not found: $aggregateId');
    }
    await _upsertRecord(
      context: PlanningMutationContext(
        userId: userId,
        organizationId: organizationId,
      ),
      aggregateType: aggregateType,
      record: existing.copyWith(
        syncStatus: syncStatus,
        errorCode: errorCode,
        errorMessage: errorMessage,
      ),
    );
  }

  @override
  Future<void> retryMutation({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
  }) async {
    final existing = await readMutation(
      userId: userId,
      organizationId: organizationId,
      aggregateType: aggregateType,
      aggregateId: aggregateId,
    );
    if (existing == null) {
      throw StateError('Planning mutation record not found: $aggregateId');
    }

    final rebasedBaseVersion = await _currentBaseVersionFor(
      existing,
      userId: userId,
      organizationId: organizationId,
    );
    await _upsertRecord(
      context: PlanningMutationContext(
        userId: userId,
        organizationId: organizationId,
      ),
      aggregateType: aggregateType,
      record: existing.copyWith(
        syncStatus: PlanningMutationSyncStatus.pending,
        clearErrorCode: true,
        clearErrorMessage: true,
        baseVersion: rebasedBaseVersion ?? existing.baseVersion,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  @override
  Future<void> clearMutation({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
  }) {
    return (_database.delete(_database.cachedPlanningMutations)..where(
          (table) =>
              table.userId.equals(userId) &
              table.organizationId.equals(organizationId) &
              table.aggregateType.equals(aggregateType) &
              table.aggregateId.equals(aggregateId),
        ))
        .go();
  }

  Future<void> _upsertRecord({
    required PlanningMutationContext context,
    required String aggregateType,
    required PlanningMutationRecord record,
  }) {
    return _database
        .into(_database.cachedPlanningMutations)
        .insertOnConflictUpdate(
          CachedPlanningMutationsCompanion.insert(
            userId: context.userId,
            organizationId: context.organizationId,
            aggregateType: aggregateType,
            aggregateId: record.aggregateId,
            mutationKind: record.kind.value,
            syncStatus: record.syncStatus.value,
            planId: Value(record.planId),
            sessionId: Value(record.sessionId),
            slug: Value(record.slug),
            name: Value(record.name),
            description: Value(record.description),
            scheduledFor: Value(record.scheduledFor?.toUtc()),
            position: Value(record.position),
            songId: Value(record.songId),
            songTitle: Value(record.songTitle),
            orderedSiblingIds: Value(
              _encodeJsonValue(record.orderedSiblingIds),
            ),
            baseVersion: Value(record.baseVersion),
            originSnapshotJson: Value(_encodeJsonValue(record.originSnapshot)),
            errorCode: Value(record.errorCode?.name),
            errorMessage: Value(record.errorMessage),
            orderKey: record.orderKey,
            updatedAt: record.updatedAt.toUtc(),
          ),
        );
  }

  Future<int> _nextOrderKey({
    required String userId,
    required String organizationId,
  }) async {
    final maxExpression = _database.cachedPlanningMutations.orderKey.max();
    final query = _database.selectOnly(_database.cachedPlanningMutations)
      ..addColumns([maxExpression])
      ..where(
        _database.cachedPlanningMutations.userId.equals(userId) &
            _database.cachedPlanningMutations.organizationId.equals(
              organizationId,
            ),
      );
    final row = await query.getSingle();
    return (row.read(maxExpression) ?? 0) + 1;
  }

  Future<int?> _currentBaseVersionFor(
    PlanningMutationRecord record, {
    required String userId,
    required String organizationId,
  }) async {
    final planId = record.planId ?? record.aggregateId;
    if (record.kind == PlanningMutationKind.planCreate) {
      return record.baseVersion;
    }

    final detail = await _localStore.readPlanDetail(
      userId: userId,
      organizationId: organizationId,
      planId: planId,
    );

    final sessionId = record.sessionId;
    return switch (record.kind) {
      PlanningMutationKind.planEdit ||
      PlanningMutationKind.sessionCreate ||
      PlanningMutationKind.sessionReorder => detail?.plan.version,
      PlanningMutationKind.sessionRename ||
      PlanningMutationKind.sessionDelete ||
      PlanningMutationKind.sessionItemCreateSong ||
      PlanningMutationKind.sessionItemDelete ||
      PlanningMutationKind.sessionItemReorder =>
        detail == null || sessionId == null
            ? record.baseVersion
            : detail.sessions
                      .firstWhereOrNull((session) => session.id == sessionId)
                      ?.version ??
                  record.baseVersion,
      _ => record.baseVersion,
    };
  }

  String? _encodeJsonValue(Object? value) {
    return value == null ? null : jsonEncode(value);
  }

  Future<bool> _hasReservedPlanSlug({
    required String userId,
    required String organizationId,
    required String slug,
    String? excludingAggregateId,
  }) async {
    final basePlan = await _localStore.readPlanSummaryBySlug(
      userId: userId,
      organizationId: organizationId,
      planSlug: slug,
    );
    if (basePlan != null && basePlan.id != excludingAggregateId) {
      return true;
    }

    final mutation =
        await (_database.select(_database.cachedPlanningMutations)..where(
              (table) =>
                  table.userId.equals(userId) &
                  table.organizationId.equals(organizationId) &
                  table.aggregateType.equals('plan') &
                  table.slug.equals(slug),
            ))
            .getSingleOrNull();
    return mutation != null && mutation.aggregateId != excludingAggregateId;
  }

  Future<bool> _hasReservedSessionSlug({
    required String userId,
    required String organizationId,
    required String planId,
    required String slug,
    String? excludingAggregateId,
  }) async {
    final detail = await _localStore.readPlanDetail(
      userId: userId,
      organizationId: organizationId,
      planId: planId,
    );
    if (detail != null) {
      for (final session in detail.sessions) {
        if (session.slug == slug && session.id != excludingAggregateId) {
          return true;
        }
      }
    }

    final mutation =
        await (_database.select(_database.cachedPlanningMutations)..where(
              (table) =>
                  table.userId.equals(userId) &
                  table.organizationId.equals(organizationId) &
                  table.aggregateType.equals('session') &
                  table.planId.equals(planId) &
                  table.slug.equals(slug),
            ))
            .getSingleOrNull();
    return mutation != null && mutation.aggregateId != excludingAggregateId;
  }

  PlanningMutationRecord _toRecord(CachedPlanningMutation row) {
    return PlanningMutationRecord(
      aggregateId: row.aggregateId,
      organizationId: row.organizationId,
      planId: row.planId,
      sessionId: row.sessionId,
      slug: row.slug,
      name: row.name,
      description: row.description,
      scheduledFor: row.scheduledFor?.toUtc(),
      position: row.position,
      songId: row.songId,
      songTitle: row.songTitle,
      orderedSiblingIds: _orderedSiblingIdsFromValue(row.orderedSiblingIds),
      baseVersion: row.baseVersion,
      originSnapshot: _originSnapshotFromValue(row.originSnapshotJson),
      errorCode: _errorCodeFromValue(row.errorCode),
      errorMessage: row.errorMessage,
      kind: planningMutationKindFromValue(row.mutationKind),
      syncStatus: planningMutationSyncStatusFromValue(row.syncStatus),
      orderKey: row.orderKey,
      updatedAt: row.updatedAt.toUtc(),
    );
  }

  PlanningMutationSyncErrorCode? _errorCodeFromValue(String? value) {
    if (value == null) {
      return null;
    }

    return PlanningMutationSyncErrorCode.values.byName(value);
  }

  String _slugify(String value, {required String fallback}) {
    final normalized = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '')
        .replaceAll(RegExp(r'-{2,}'), '-');
    return normalized.isEmpty ? fallback : normalized;
  }

  List<String>? _orderedSiblingIdsFromValue(String? value) {
    if (value == null) {
      return null;
    }
    final decoded = jsonDecode(value);
    if (decoded is! List) {
      return null;
    }
    return decoded.map((entry) => entry.toString()).toList(growable: false);
  }

  Map<String, Object?>? _originSnapshotFromValue(String? value) {
    if (value == null) {
      return null;
    }
    final decoded = jsonDecode(value);
    if (decoded is! Map) {
      return null;
    }
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }

  Future<void> _removeSessionFromPendingReorder({
    required PlanningMutationContext context,
    required String planId,
    required String sessionId,
  }) async {
    final existing = await _readMutationByKey(
      userId: context.userId,
      organizationId: context.organizationId,
      aggregateType: 'session_order',
      aggregateId: planId,
    );
    final orderedSiblingIds = existing?.orderedSiblingIds;
    if (existing == null || orderedSiblingIds == null) {
      return;
    }
    final nextIds = orderedSiblingIds
        .where((candidate) => candidate != sessionId)
        .toList(growable: false);
    if (nextIds.length == orderedSiblingIds.length) {
      return;
    }
    if (nextIds.isEmpty) {
      await (_database.delete(_database.cachedPlanningMutations)..where(
            (table) =>
                table.userId.equals(context.userId) &
                table.organizationId.equals(context.organizationId) &
                table.aggregateType.equals('session_order') &
                table.aggregateId.equals(planId),
          ))
          .go();
      return;
    }
    await _upsertRecord(
      context: context,
      aggregateType: 'session_order',
      record: existing.copyWith(
        orderedSiblingIds: nextIds,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  Future<void> _removeSessionItemFromPendingReorder({
    required PlanningMutationContext context,
    required String sessionId,
    required String sessionItemId,
  }) async {
    final existing = await _readMutationByKey(
      userId: context.userId,
      organizationId: context.organizationId,
      aggregateType: 'session_item_order',
      aggregateId: sessionId,
    );
    final orderedSiblingIds = existing?.orderedSiblingIds;
    if (existing == null || orderedSiblingIds == null) {
      return;
    }
    final nextIds = orderedSiblingIds
        .where((candidate) => candidate != sessionItemId)
        .toList(growable: false);
    if (nextIds.length == orderedSiblingIds.length) {
      return;
    }
    if (nextIds.isEmpty) {
      await (_database.delete(_database.cachedPlanningMutations)..where(
            (table) =>
                table.userId.equals(context.userId) &
                table.organizationId.equals(context.organizationId) &
                table.aggregateType.equals('session_item_order') &
                table.aggregateId.equals(sessionId),
          ))
          .go();
      return;
    }
    await _upsertRecord(
      context: context,
      aggregateType: 'session_item_order',
      record: existing.copyWith(
        orderedSiblingIds: nextIds,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }
}
