import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:drift/drift.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/application/storage/local_storage_footprint_revision.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';

class DriftPlanningMutationStore implements PlanningMutationStore {
  const DriftPlanningMutationStore({
    required PlanningLocalDatabase database,
    required PlanningLocalStore localStore,
    LocalStorageFootprintChanged? onStorageFootprintChanged,
  }) : _database = database,
       _localStore = localStore,
       _onStorageFootprintChanged = onStorageFootprintChanged;

  final PlanningLocalDatabase _database;
  final PlanningLocalStore _localStore;
  final LocalStorageFootprintChanged? _onStorageFootprintChanged;

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
    _onStorageFootprintChanged?.call();
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
        //
        // ADR-030 known follow-up: `existing` may be `accepted` but not yet
        // cleared (the ADR-019 durable-marker window -- backend confirmed,
        // local clear has not run, e.g. LF-1's crash-between-accept-and-
        // clear). New local intent is unsent by definition, so folding it
        // in must reset syncStatus to `pending` and drop any stale error
        // left by a prior attempt -- otherwise a subsequent sync's
        // accepted-durable-marker branch would skip the remote send and
        // reconcile this newer, never-sent content as if the backend
        // already had it.
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
            syncStatus: PlanningMutationSyncStatus.pending,
            clearErrorCode: true,
            clearErrorMessage: true,
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
    _onStorageFootprintChanged?.call();
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
    _onStorageFootprintChanged?.call();
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
        // ADR-030 known follow-up: same shape as the recordPlanEdit fold
        // above -- `existing` may be `accepted` but not yet cleared, and
        // this rename is new, unsent local intent, so the fold must reset
        // syncStatus to `pending` and drop any stale error rather than
        // carry the row's current status forward untouched.
        await _upsertRecord(
          context: context,
          aggregateType: 'session',
          record: existing!.copyWith(
            name: draft.name,
            updatedAt: DateTime.now().toUtc(),
            syncStatus: PlanningMutationSyncStatus.pending,
            clearErrorCode: true,
            clearErrorMessage: true,
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
    _onStorageFootprintChanged?.call();
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
        // D2 (docs/specs/2026-08-06-in-flight-create-cancellation.md): a
        // `sending` row's create is genuinely in flight to the backend right
        // now (D1's durable marker, written by
        // PlanningMutationSyncController._run just before the remote call).
        // Physically collapsing it here would destroy the only local trace
        // of this delete before the create's outcome is known -- if it then
        // succeeds, the object exists on the server and nothing would ever
        // delete it. Keep the row as a cancellation tombstone instead, at a
        // bumped revision; resolveCancelledCreate below turns it into a real
        // pending delete or discards it once the create's remote call
        // returns.
        if (existing!.syncStatus == PlanningMutationSyncStatus.sending) {
          await _upsertRecord(
            context: context,
            aggregateType: 'session',
            record: existing.copyWith(
              syncStatus: PlanningMutationSyncStatus.cancelling,
              updatedAt: DateTime.now().toUtc(),
              clearErrorCode: true,
              clearErrorMessage: true,
            ),
          );
        } else if (existing.syncStatus == PlanningMutationSyncStatus.accepted) {
          // Gap closed (docs/specs/2026-08-06-in-flight-create-cancellation.md,
          // the variant D1-D3 left open): `accepted` is ADR-019's own
          // durable-marker window -- the backend has ALREADY confirmed this
          // create; only the local clear has not run yet (e.g. a crash
          // between PlanningMutationSyncController._run's accept write and
          // its batch clear -- the exact LF-1 scenario ADR-030's
          // fold-status follow-up documents). Unlike `sending`, there is no
          // live remote call to race here: the create's fate is already
          // known, not in flight. That makes this simpler than the
          // `sending` branch above -- no tombstone, no resolveCancelledCreate
          // step -- the delete can become a real pending delete directly.
          // Falling through to the physical-collapse branch below would
          // still lose the delete intent for an object the backend already
          // has, one state over from the gap D1-D3 closed.
          //
          // baseVersion: `existing.baseVersion` is whatever was captured
          // for the CREATE's own OCC check and was never updated by the
          // accept write (saveSyncAttemptResult only ever touches
          // syncStatus/errorCode/errorMessage/localRevision) -- it is not
          // guaranteed to be the version the backend assigned as a result
          // of accepting this create. `draft.baseVersion`, supplied by the
          // caller from today's local merged read, is the best
          // complementary source but is not guaranteed to carry that
          // post-create version either, for the same reason
          // resolveCancelledCreate's D3 branch is handed
          // `acceptedBaseVersion` explicitly from the RPC response instead
          // of recomputing it locally -- that response is long gone by the
          // time a delete can land here. Rather than invent a number, this
          // uses `existing.baseVersion ?? draft.baseVersion`, the exact
          // same fallback the genuine (non-create) delete path below
          // already uses for every other kind of delete. If it happens to
          // be correct, the delete's OCC check on the backend passes
          // normally. If it is stale, the backend's own
          // `delete_empty_session`/`delete_session_item` version guard
          // rejects the RPC into a visible, recoverable `conflict` (or, if
          // no version is known at all, a deterministic rejection) rather
          // than this code silently guessing -- the fail-safe outcome.
          await _upsertRecord(
            context: context,
            aggregateType: 'session',
            record: PlanningMutationRecord(
              aggregateId: draft.sessionId,
              organizationId: context.organizationId,
              planId: draft.planId,
              baseVersion: existing.baseVersion ?? draft.baseVersion,
              kind: PlanningMutationKind.sessionDelete,
              syncStatus: PlanningMutationSyncStatus.pending,
              orderKey: existing.orderKey,
              updatedAt: DateTime.now().toUtc(),
              originSnapshot: existing.originSnapshot ?? draft.originSnapshot,
            ),
          );
        } else {
          // Not in flight and not accepted: physically collapse, exactly
          // as before (ADR-028 D10) -- the create never left the device
          // (or already concluded with an error), so there is nothing on
          // the backend a delete would need to reach.
          await (_database.delete(_database.cachedPlanningMutations)..where(
                (table) =>
                    table.userId.equals(context.userId) &
                    table.organizationId.equals(context.organizationId) &
                    table.aggregateType.equals('session') &
                    table.aggregateId.equals(draft.sessionId),
              ))
              .go();
        }
        // Whichever of the three branches above ran, the session is being
        // deleted one way or another: a tombstone that will eventually
        // convert to a real delete or be discarded, an immediate physical
        // collapse, or (the branch closed by this change) an immediate real
        // pending delete. Either way a pending item mutation under it has
        // no reachable destination -- sent to a session that doesn't exist
        // yet, or sent to one that is being deleted for real. Drop them
        // with the session, inside the same transaction, same as the
        // pre-existing collapse behaviour.
        await _deletePendingMutationsForSession(
          context: context,
          sessionId: draft.sessionId,
        );
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
    _onStorageFootprintChanged?.call();
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
    _onStorageFootprintChanged?.call();
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
    _onStorageFootprintChanged?.call();
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
        // D2: same reasoning as the sessionCreate branch of
        // recordSessionDelete above -- a `sending` row's create is
        // genuinely in flight, so keep it as a cancellation tombstone
        // instead of physically collapsing it.
        if (existing!.syncStatus == PlanningMutationSyncStatus.sending) {
          await _upsertRecord(
            context: context,
            aggregateType: 'session_item',
            record: existing.copyWith(
              syncStatus: PlanningMutationSyncStatus.cancelling,
              updatedAt: DateTime.now().toUtc(),
              clearErrorCode: true,
              clearErrorMessage: true,
            ),
          );
        } else if (existing.syncStatus == PlanningMutationSyncStatus.accepted) {
          // Gap closed (docs/specs/2026-08-06-in-flight-create-cancellation.md,
          // the variant D1-D3 left open): same reasoning as the accepted
          // branch of recordSessionDelete above -- `accepted` means the
          // backend already confirmed this create and only the local clear
          // has not run yet, so there is no live remote call to race and no
          // need for the tombstone/resolve dance `sending` uses. Convert
          // straight into a real pending delete.
          //
          // baseVersion: `existing.baseVersion` was captured for the
          // create's own OCC check (the session's version BEFORE this item
          // was added) and was never updated by the accept write. The
          // backend's `create_song_session_item` bumps the session's
          // version by one as a side effect of accepting the create, and
          // that new value is only ever returned in the RPC response --
          // never persisted back onto this row -- so it is not available
          // here. `draft.baseVersion` (from today's merged read) carries
          // the same pre-create value for the same reason, not the
          // post-create one. Rather than invent the "+1" this create is
          // known to have caused, this uses `existing.baseVersion ??
          // draft.baseVersion`, the same fallback the genuine delete path
          // below already uses. A stale value fails safe: the backend's
          // `delete_session_item` version guard rejects it into a visible,
          // recoverable `conflict` instead of this code silently guessing.
          await _upsertRecord(
            context: context,
            aggregateType: 'session_item',
            record: PlanningMutationRecord(
              aggregateId: draft.sessionItemId,
              organizationId: context.organizationId,
              planId: draft.planId,
              sessionId: draft.sessionId,
              baseVersion: existing.baseVersion ?? draft.baseVersion,
              kind: PlanningMutationKind.sessionItemDelete,
              syncStatus: PlanningMutationSyncStatus.pending,
              orderKey: existing.orderKey,
              updatedAt: DateTime.now().toUtc(),
              originSnapshot: existing.originSnapshot ?? draft.originSnapshot,
            ),
          );
        } else {
          await (_database.delete(_database.cachedPlanningMutations)..where(
                (table) =>
                    table.userId.equals(context.userId) &
                    table.organizationId.equals(context.organizationId) &
                    table.aggregateType.equals('session_item') &
                    table.aggregateId.equals(draft.sessionItemId),
              ))
              .go();
        }
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
    _onStorageFootprintChanged?.call();
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
    _onStorageFootprintChanged?.call();
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
                      // D1: a `sending` row is functionally still pending
                      // from a reader's point of view -- its content is
                      // unchanged, only its in-flight bookkeeping differs --
                      // so it must keep rendering as the pending
                      // session/item it is. `cancelling` is deliberately
                      // NOT included: that tombstone represents a session/
                      // item the user just deleted, and must disappear from
                      // every merged read immediately, before its eventual
                      // create outcome is even known (D2/D3).
                      PlanningMutationSyncStatus.sending.value,
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
  Future<int?> saveSyncAttemptResult({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
    required PlanningMutationSyncStatus syncStatus,
    PlanningMutationSyncErrorCode? errorCode,
    String? errorMessage,
    int? expectedRevision,
  }) async {
    final existing =
        await (_database.select(_database.cachedPlanningMutations)..where(
              (table) =>
                  table.userId.equals(userId) &
                  table.organizationId.equals(organizationId) &
                  table.aggregateType.equals(aggregateType) &
                  table.aggregateId.equals(aggregateId),
            ))
            .getSingleOrNull();
    if (existing == null) {
      // D4 (docs/specs/2026-08-06-in-flight-create-cancellation.md): the
      // row this sync attempt was concluding is gone -- an ordinary
      // concurrent-world outcome (the user deleted a still-pending create
      // while its remote call was in flight, and the collapse path
      // physically removed the row; ADR-028 D10), not a defect. Reporting
      // it the same way D3 reports a stale revision ("did not apply", not
      // an exception) is what lets PlanningMutationSyncController._run
      // move on to the records queued behind this one instead of dying.
      return null;
    }

    // D2: the gating condition lives in the WHERE clause of this single
    // UPDATE, not as a read-then-decide in Dart. `existing` above is read
    // only to raise the not-found error and to know the pre-write revision
    // for computing the new one -- it is NEVER used to decide whether the
    // write applies. That decision is `expectedRevision`, captured by the
    // CALLER at snapshot time, before the remote round trip; comparing it
    // against the row's revision atomically, inside the same statement, is
    // what closes the race a Dart-side read-then-write would reopen.
    final newRevision = (expectedRevision ?? existing.localRevision) + 1;
    var predicate =
        _database.cachedPlanningMutations.userId.equals(userId) &
        _database.cachedPlanningMutations.organizationId.equals(
          organizationId,
        ) &
        _database.cachedPlanningMutations.aggregateType.equals(aggregateType) &
        _database.cachedPlanningMutations.aggregateId.equals(aggregateId);
    if (expectedRevision != null) {
      predicate =
          predicate &
          _database.cachedPlanningMutations.localRevision.equals(
            expectedRevision,
          );
    }
    final rowsUpdated =
        await (_database.update(
          _database.cachedPlanningMutations,
        )..where((_) => predicate)).write(
          CachedPlanningMutationsCompanion(
            syncStatus: Value(syncStatus.value),
            // Matches the pre-existing copyWith-based semantics this method
            // used to go through: a null errorCode/errorMessage argument
            // leaves the stored value untouched (Value.absent), it does not
            // clear it. Value.absent() also happens to be exactly what
            // "don't touch this column" means for a targeted UPDATE.
            errorCode: errorCode == null
                ? const Value.absent()
                : Value(errorCode.name),
            errorMessage: errorMessage == null
                ? const Value.absent()
                : Value(errorMessage),
            localRevision: Value(newRevision),
          ),
        );

    if (rowsUpdated == 0) {
      // D3: the row's revision moved past what the caller expected -- a
      // local edit landed on this aggregate after the snapshot that was
      // sent. Not an error: leave the row exactly as the edit left it.
      return null;
    }
    _onStorageFootprintChanged?.call();
    return newRevision;
  }

  @override
  Future<bool> retryMutation({
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
      // D4 (docs/specs/2026-08-06-in-flight-create-cancellation.md): same
      // reasoning as saveSyncAttemptResult above -- the row is gone, an
      // ordinary concurrent-world outcome, not a defect. There is nothing
      // left to retry.
      return false;
    }

    final rebasedBaseVersion = await _currentBaseVersionFor(
      existing,
      userId: userId,
      organizationId: organizationId,
    );
    final changed = await _upsertRecord(
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
    if (changed) {
      _onStorageFootprintChanged?.call();
    }
    return true;
  }

  @override
  Future<bool> clearMutation({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
    int? expectedRevision,
  }) async {
    // D2: same shape as saveSyncAttemptResult -- the revision check is part
    // of the DELETE's own WHERE clause, atomically, not a preceding read
    // that could go stale before the delete runs.
    var predicate =
        _database.cachedPlanningMutations.userId.equals(userId) &
        _database.cachedPlanningMutations.organizationId.equals(
          organizationId,
        ) &
        _database.cachedPlanningMutations.aggregateType.equals(aggregateType) &
        _database.cachedPlanningMutations.aggregateId.equals(aggregateId);
    if (expectedRevision != null) {
      predicate =
          predicate &
          _database.cachedPlanningMutations.localRevision.equals(
            expectedRevision,
          );
    }
    final deletedRows = await (_database.delete(
      _database.cachedPlanningMutations,
    )..where((_) => predicate)).go();
    if (deletedRows > 0) {
      _onStorageFootprintChanged?.call();
      return true;
    }
    // D3: either nothing was there, or (when expectedRevision was supplied)
    // a local edit landed after the snapshot that was sent -- not an error.
    return false;
  }

  @override
  Future<bool> resolveCancelledCreate({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
    required bool created,
    int? acceptedBaseVersion,
  }) async {
    return _database.transaction(() async {
      final row =
          await (_database.select(_database.cachedPlanningMutations)..where(
                (table) =>
                    table.userId.equals(userId) &
                    table.organizationId.equals(organizationId) &
                    table.aggregateType.equals(aggregateType) &
                    table.aggregateId.equals(aggregateId),
              ))
              .getSingleOrNull();
      if (row == null) {
        return false;
      }
      final existing = _toRecord(row);
      if (existing.syncStatus != PlanningMutationSyncStatus.cancelling) {
        // Not a tombstone -- either an ordinary local edit landed on this
        // aggregate instead (already handled by the caller's D3
        // stale-revision skip) or a previous call already resolved it.
        // Nothing to do.
        return false;
      }

      if (!created) {
        // D3: the create never reached the backend, so the object never
        // existed remotely -- discard the tombstone outright, with no
        // further backend call. Exactly the physical collapse a plain,
        // not-in-flight delete would have performed (ADR-028 D10).
        await (_database.delete(_database.cachedPlanningMutations)..where(
              (table) =>
                  table.userId.equals(userId) &
                  table.organizationId.equals(organizationId) &
                  table.aggregateType.equals(aggregateType) &
                  table.aggregateId.equals(aggregateId),
            ))
            .go();
        _onStorageFootprintChanged?.call();
        return true;
      }

      // D3: the create succeeded, so the object exists on the server -- the
      // tombstone becomes a real pending delete and the next sync sends it.
      // The already-accepted remote create is never undone; this is a
      // subsequent operation. baseVersion is rebased on the version the
      // backend just assigned the created row, so the delete RPC's OCC
      // check targets content that actually exists.
      final deleteKind = switch (existing.kind) {
        PlanningMutationKind.sessionCreate =>
          PlanningMutationKind.sessionDelete,
        PlanningMutationKind.sessionItemCreateSong =>
          PlanningMutationKind.sessionItemDelete,
        _ => throw StateError(
          'resolveCancelledCreate: unexpected tombstone kind '
          '${existing.kind} for $aggregateType/$aggregateId -- only '
          'sessionCreate/sessionItemCreateSong rows can become cancellation '
          'tombstones (D2).',
        ),
      };
      await _upsertRecord(
        context: PlanningMutationContext(
          userId: userId,
          organizationId: organizationId,
        ),
        aggregateType: aggregateType,
        record: existing.copyWith(
          kind: deleteKind,
          syncStatus: PlanningMutationSyncStatus.pending,
          baseVersion: acceptedBaseVersion ?? existing.baseVersion,
          updatedAt: DateTime.now().toUtc(),
          clearErrorCode: true,
          clearErrorMessage: true,
        ),
      );
      return true;
    });
  }

  Future<bool> _upsertRecord({
    required PlanningMutationContext context,
    required String aggregateType,
    required PlanningMutationRecord record,
  }) async {
    final existing =
        await (_database.select(_database.cachedPlanningMutations)..where(
              (table) =>
                  table.userId.equals(context.userId) &
                  table.organizationId.equals(context.organizationId) &
                  table.aggregateType.equals(aggregateType) &
                  table.aggregateId.equals(record.aggregateId),
            ))
            .getSingleOrNull();
    if (existing != null &&
        _matchesPersistedRecord(
          existing,
          context: context,
          aggregateType: aggregateType,
          record: record,
        )) {
      return false;
    }

    // D1: every local write to this row bumps localRevision, including
    // folds (recordPlanEdit onto a pending planCreate, etc.) -- this is the
    // one write path shared by all nine `record*` mutations plus
    // retryMutation. Reading `existing` here (already done above, for the
    // no-op short-circuit) and computing the increment in Dart is safe: this
    // is not a conditional write racing a network round trip (unlike
    // saveSyncAttemptResult/clearMutation, D2), it is the store's own
    // single, ordinary write for this aggregate.
    await _database
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
            localRevision: Value(
              existing == null ? 1 : existing.localRevision + 1,
            ),
          ),
        );
    return true;
  }

  bool _matchesPersistedRecord(
    CachedPlanningMutation existing, {
    required PlanningMutationContext context,
    required String aggregateType,
    required PlanningMutationRecord record,
  }) {
    return existing.userId == context.userId &&
        existing.organizationId == context.organizationId &&
        existing.aggregateType == aggregateType &&
        existing.aggregateId == record.aggregateId &&
        existing.mutationKind == record.kind.value &&
        existing.syncStatus == record.syncStatus.value &&
        existing.planId == record.planId &&
        existing.sessionId == record.sessionId &&
        existing.slug == record.slug &&
        existing.name == record.name &&
        existing.description == record.description &&
        existing.scheduledFor?.toUtc() == record.scheduledFor?.toUtc() &&
        existing.position == record.position &&
        existing.songId == record.songId &&
        existing.songTitle == record.songTitle &&
        existing.orderedSiblingIds ==
            _encodeJsonValue(record.orderedSiblingIds) &&
        existing.baseVersion == record.baseVersion &&
        existing.originSnapshotJson ==
            _encodeJsonValue(record.originSnapshot) &&
        existing.errorCode == record.errorCode?.name &&
        existing.errorMessage == record.errorMessage &&
        existing.orderKey == record.orderKey &&
        existing.updatedAt.toUtc() == record.updatedAt.toUtc();
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
      localRevision: row.localRevision,
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

  Future<void> _deletePendingMutationsForSession({
    required PlanningMutationContext context,
    required String sessionId,
  }) async {
    await (_database.delete(_database.cachedPlanningMutations)..where(
          (table) =>
              table.userId.equals(context.userId) &
              table.organizationId.equals(context.organizationId) &
              table.aggregateType.equals('session_item') &
              table.sessionId.equals(sessionId),
        ))
        .go();
    await (_database.delete(_database.cachedPlanningMutations)..where(
          (table) =>
              table.userId.equals(context.userId) &
              table.organizationId.equals(context.organizationId) &
              table.aggregateType.equals('session_item_order') &
              table.aggregateId.equals(sessionId),
        ))
        .go();
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
    // ADR-030 known follow-up: dropping the deleted session's id changes
    // this row's content (it is no longer the sibling list the backend may
    // have already accepted), so -- same as the direct edit folds above --
    // it must reset syncStatus to `pending` and drop any stale error rather
    // than carry the row's current status forward via a bare copyWith.
    await _upsertRecord(
      context: context,
      aggregateType: 'session_order',
      record: existing.copyWith(
        orderedSiblingIds: nextIds,
        updatedAt: DateTime.now().toUtc(),
        syncStatus: PlanningMutationSyncStatus.pending,
        clearErrorCode: true,
        clearErrorMessage: true,
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
    // ADR-030 known follow-up: same reasoning as
    // _removeSessionFromPendingReorder above.
    await _upsertRecord(
      context: context,
      aggregateType: 'session_item_order',
      record: existing.copyWith(
        orderedSiblingIds: nextIds,
        updatedAt: DateTime.now().toUtc(),
        syncStatus: PlanningMutationSyncStatus.pending,
        clearErrorCode: true,
        clearErrorMessage: true,
      ),
    );
  }
}
