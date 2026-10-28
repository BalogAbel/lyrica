import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';

/// Thrown when a backend-accepted mutation record is missing a field that
/// is required to reconcile it into the local projection (LF-8). This
/// signals a corrupt mutation: writing a coerced empty-string/zero value in
/// its place would silently hide the corruption inside the local cache.
class ReconcileFieldError extends StateError {
  ReconcileFieldError(String field, PlanningMutationKind kind)
    : super('Missing required field "$field" reconciling ${kind.value}');
}

/// Returns [value] if non-null, otherwise throws [ReconcileFieldError].
///
/// Use this only for fields that are genuinely required for [kind] to be a
/// valid mutation (e.g. the songId on a session-item create). Do NOT use it
/// for fields that are legitimately optional (e.g. description).
T _required<T>(T? value, String field, PlanningMutationKind kind) =>
    value ?? (throw ReconcileFieldError(field, kind));

class PlanningMutationReconciler {
  const PlanningMutationReconciler({
    required this._localStore,
    this._now = _wallClockNow,
  });

  final PlanningLocalStore Function() _localStore;

  // LF-T6: the clock used to stamp reconciled records. Defaults to the
  // device wall clock (unchanged behaviour); injectable so tests can
  // characterize clock-skew behaviour. This does NOT add a server-clock
  // anchor -- the reconciled timestamp is still whatever clock is passed
  // in, device or otherwise. A real server-clock anchor is deferred.
  final DateTime Function() _now;

  static DateTime _wallClockNow() => DateTime.now().toUtc();

  /// Reconciles one backend-accepted [record] into the projection of
  /// [context].
  ///
  /// Spec F1: every required field is validated before any store call (a
  /// corrupt record fails whatever the projection holds, LF-8), then the
  /// per-kind writes and D7 rule 1a run as one
  /// [PlanningLocalStore.applyAcceptedWrite] transaction, skipped when the
  /// projection already holds the write. `R` (the gate's
  /// `acceptedContentVersion`) only exists on a record mapped from a backend
  /// response (`acceptedPlanContentVersion` is in memory only), and the PS15
  /// gate nulls it for a key edit that is not provably the caller's own; such
  /// records, and a crash-resumed `accepted` marker, are gated by their
  /// versioned row only and never advance the content version.
  Future<void> reconcile(
    ActivePlanningReadContext context,
    PlanningMutationRecord record,
  ) async {
    final localStore = _localStore();
    final write = _acceptedWriteFor(
      localStore: localStore,
      context: context,
      record: record,
      reconciledAt: _now(),
    );
    await localStore.applyAcceptedWrite(
      userId: context.userId,
      organizationId: context.organizationId,
      gate: write.gate,
      apply: write.apply,
    );
  }

  /// Validates [record] and returns its gate and the writes that reconcile
  /// it. Every `_required` runs here, eagerly, before [reconcile] makes a
  /// store call.
  ({PlanningAcceptedWriteGate gate, Future<void> Function() apply})
  _acceptedWriteFor({
    required PlanningLocalStore localStore,
    required ActivePlanningReadContext context,
    required PlanningMutationRecord record,
    required DateTime reconciledAt,
  }) {
    // The rule-1a plan (moved from the sync controller's MG4 block).
    final planId = record.kind.aggregateType == 'plan'
        ? record.aggregateId
        : record.planId;
    final acceptedContentVersion = record.kind.bumpsPlanContent
        ? record.acceptedPlanContentVersion
        : null;

    switch (record.kind) {
      case PlanningMutationKind.planCreate:
      case PlanningMutationKind.planEdit:
        final plan = CachedPlanRecord(
          id: record.aggregateId,
          // slug falls back to aggregateId: both planCreate and planEdit
          // are keyed by aggregateId, so this is a legitimate default,
          // not a coercion of a required field.
          slug: record.slug ?? record.aggregateId,
          // name is required on both PlanningPlanCreateMutationDraft and
          // PlanningPlanEditMutationDraft: a null here means a corrupt
          // mutation, not an absent optional value.
          name: _required(record.name, 'name', record.kind),
          // description is genuinely optional on both create and edit.
          description: record.description,
          scheduledFor: record.scheduledFor,
          updatedAt: reconciledAt,
          // version default for a freshly reconciled aggregate.
          version: record.baseVersion ?? 1,
          // Spec D4: a new plan starts at the response's content version;
          // an edit never changes it (upsertSyncedPlan keeps an existing
          // row's value anyway).
          contentVersion: record.kind == PlanningMutationKind.planCreate
              ? (record.acceptedPlanContentVersion ?? 1)
              : null,
        );
        return (
          gate: PlanningAcceptedWriteGate(
            planId: planId,
            versionedRow: PlanningVersionedRow(
              kind: PlanningProjectionRowKind.plan,
              id: record.aggregateId,
              writtenVersion: plan.version,
            ),
          ),
          apply: () => localStore.upsertSyncedPlan(
            userId: context.userId,
            organizationId: context.organizationId,
            refreshedAt: reconciledAt,
            plan: plan,
          ),
        );
      case PlanningMutationKind.planDelete:
        return (
          gate: PlanningAcceptedWriteGate(planId: planId),
          apply: () => localStore.deleteSyncedPlan(
            userId: context.userId,
            organizationId: context.organizationId,
            planId: record.aggregateId,
            refreshedAt: reconciledAt,
          ),
        );
      case PlanningMutationKind.sessionCreate:
      case PlanningMutationKind.sessionRename:
        final session = CachedSessionRecord(
          id: record.aggregateId,
          // planId is required on both PlanningSessionCreateMutationDraft
          // and PlanningSessionRenameMutationDraft: a null here means a
          // corrupt mutation, not an absent optional value.
          planId: _required(record.planId, 'planId', record.kind),
          // slug falls back to aggregateId: sessionRename does not carry
          // a slug at all, so this is a legitimate default for that case.
          slug: record.slug ?? record.aggregateId,
          // position is not part of PlanningSessionRenameMutationDraft;
          // 0 is a legitimate default when rename omits it.
          position: record.position ?? 0,
          // name is required on both create and rename drafts: a null
          // here means a corrupt mutation, not an absent optional value.
          name: _required(record.name, 'name', record.kind),
          // A create is written at version 1: create_session always inserts
          // the session at version 1 and takes no base. A create's
          // baseVersion is never the session's version (MG8 can rebase a
          // retried create onto the PLAN version), so it must not become
          // the written version nor the gate's written version (F1, final
          // review I-1). A rename keeps its base (version default for a
          // freshly reconciled aggregate).
          version: record.kind == PlanningMutationKind.sessionCreate
              ? 1
              : record.baseVersion ?? 1,
        );
        return (
          gate: PlanningAcceptedWriteGate(
            planId: planId,
            acceptedContentVersion: acceptedContentVersion,
            versionedRow: PlanningVersionedRow(
              kind: PlanningProjectionRowKind.session,
              id: record.aggregateId,
              writtenVersion: session.version,
            ),
          ),
          apply: () => localStore.upsertSyncedSession(
            userId: context.userId,
            organizationId: context.organizationId,
            refreshedAt: reconciledAt,
            session: session,
          ),
        );
      case PlanningMutationKind.sessionDelete:
        return (
          gate: PlanningAcceptedWriteGate(
            planId: planId,
            acceptedContentVersion: acceptedContentVersion,
          ),
          apply: () => localStore.deleteSyncedSession(
            userId: context.userId,
            organizationId: context.organizationId,
            sessionId: record.aggregateId,
            refreshedAt: reconciledAt,
          ),
        );
      case PlanningMutationKind.sessionReorder:
        final reorderedPlanId = record.planId ?? record.aggregateId;
        // version default for a freshly reconciled aggregate.
        final planVersion = record.baseVersion ?? 1;
        return (
          gate: PlanningAcceptedWriteGate(
            planId: planId,
            acceptedContentVersion: acceptedContentVersion,
            versionedRow: PlanningVersionedRow(
              kind: PlanningProjectionRowKind.plan,
              id: reorderedPlanId,
              writtenVersion: planVersion,
            ),
          ),
          apply: () => localStore.replaceSyncedSessionOrder(
            userId: context.userId,
            organizationId: context.organizationId,
            planId: reorderedPlanId,
            orderedSessionIds: record.orderedSiblingIds ?? const [],
            orderedSessionPositions: record.orderedSiblingPositions,
            planVersion: planVersion,
            refreshedAt: reconciledAt,
          ),
        );
      case PlanningMutationKind.sessionItemCreateSong:
        // planId, sessionId, songId, songTitle and position are all
        // required on PlanningSessionItemCreateSongMutationDraft: a null
        // here means a corrupt mutation, not an absent optional value.
        // Coercing to '' / 0 would silently persist a fabricated row
        // instead of surfacing the corruption (LF-8).
        final item = CachedSessionItemRecord(
          id: record.aggregateId,
          planId: _required(record.planId, 'planId', record.kind),
          sessionId: _required(record.sessionId, 'sessionId', record.kind),
          position: _required(record.position, 'position', record.kind),
          songId: _required(record.songId, 'songId', record.kind),
          songTitle: _required(record.songTitle, 'songTitle', record.kind),
        );
        // version default for a freshly reconciled aggregate.
        final sessionVersion = record.baseVersion ?? 1;
        return (
          gate: PlanningAcceptedWriteGate(
            planId: planId,
            acceptedContentVersion: acceptedContentVersion,
            versionedRow: PlanningVersionedRow(
              kind: PlanningProjectionRowKind.session,
              id: item.sessionId,
              writtenVersion: sessionVersion,
            ),
          ),
          apply: () async {
            await localStore.upsertSyncedSessionItem(
              userId: context.userId,
              organizationId: context.organizationId,
              refreshedAt: reconciledAt,
              sessionVersion: sessionVersion,
              item: item,
            );
            final siblingIds = record.orderedSiblingIds;
            if (siblingIds != null) {
              await localStore.replaceSyncedSessionItemOrder(
                userId: context.userId,
                organizationId: context.organizationId,
                sessionId: item.sessionId,
                orderedSessionItemIds: siblingIds,
                orderedSessionItemPositions: record.orderedSiblingPositions,
                sessionVersion: sessionVersion,
                refreshedAt: reconciledAt,
              );
            }
          },
        );
      case PlanningMutationKind.sessionItemDelete:
        // sessionId is required by the delete/reorder drafts (it identifies the
        // existing row's session), so a null here is a corrupt record -- reject
        // it via _required rather than coercing to '' and silently deleting /
        // reordering against the wrong (empty) session key (LF-8).
        final sessionId = _required(record.sessionId, 'sessionId', record.kind);
        // version default for a freshly reconciled aggregate.
        final sessionVersion = record.baseVersion ?? 1;
        return (
          gate: PlanningAcceptedWriteGate(
            planId: planId,
            acceptedContentVersion: acceptedContentVersion,
            versionedRow: PlanningVersionedRow(
              kind: PlanningProjectionRowKind.session,
              id: sessionId,
              writtenVersion: sessionVersion,
            ),
          ),
          apply: () async {
            await localStore.deleteSyncedSessionItem(
              userId: context.userId,
              organizationId: context.organizationId,
              sessionId: sessionId,
              sessionItemId: record.aggregateId,
              sessionVersion: sessionVersion,
              refreshedAt: reconciledAt,
            );
            final siblingIds = record.orderedSiblingIds;
            if (siblingIds != null) {
              await localStore.replaceSyncedSessionItemOrder(
                userId: context.userId,
                organizationId: context.organizationId,
                sessionId: sessionId,
                orderedSessionItemIds: siblingIds,
                orderedSessionItemPositions: record.orderedSiblingPositions,
                sessionVersion: sessionVersion,
                refreshedAt: reconciledAt,
              );
            }
          },
        );
      case PlanningMutationKind.sessionItemReorder:
        final sessionId = _required(record.sessionId, 'sessionId', record.kind);
        // version default for a freshly reconciled aggregate.
        final sessionVersion = record.baseVersion ?? 1;
        return (
          gate: PlanningAcceptedWriteGate(
            planId: planId,
            acceptedContentVersion: acceptedContentVersion,
            versionedRow: PlanningVersionedRow(
              kind: PlanningProjectionRowKind.session,
              id: sessionId,
              writtenVersion: sessionVersion,
            ),
          ),
          apply: () => localStore.replaceSyncedSessionItemOrder(
            userId: context.userId,
            organizationId: context.organizationId,
            sessionId: sessionId,
            orderedSessionItemIds: record.orderedSiblingIds ?? const [],
            orderedSessionItemPositions: record.orderedSiblingPositions,
            sessionVersion: sessionVersion,
            refreshedAt: reconciledAt,
          ),
        );
      case PlanningMutationKind.sessionItemKeyEdit:
        // Two shapes reach here (PS15). A response-shaped synced record
        // carries the RETURNED item version in baseVersion and the server key
        // in keyEdit (all set/clear), which ignores the base values. A
        // crash-resumed `accepted` marker is the unsent shape: baseVersion is
        // the OLD item version and keyEdit may hold `keep`, so the edit is
        // applied over the base values -- what an accepted OCC write at that
        // base produced. A stale version then shows at most one visible
        // conflict, as for the other kinds. A record without its edit or
        // version is a corrupt mutation (LF-8), not a value to default.
        final key = _required(
          record.keyEdit,
          'keyEdit',
          record.kind,
        ).applyTo(transpose: record.keyBaseTranspose, capo: record.keyBaseCapo);
        final version = _required(
          record.baseVersion,
          'baseVersion',
          record.kind,
        );
        return (
          gate: PlanningAcceptedWriteGate(
            planId: planId,
            acceptedContentVersion: acceptedContentVersion,
            versionedRow: PlanningVersionedRow(
              kind: PlanningProjectionRowKind.sessionItem,
              id: record.aggregateId,
              writtenVersion: version,
            ),
          ),
          apply: () => localStore.applySyncedSessionItemKey(
            userId: context.userId,
            organizationId: context.organizationId,
            sessionItemId: record.aggregateId,
            version: version,
            transpose: key.transpose,
            capo: key.capo,
            refreshedAt: reconciledAt,
          ),
        );
    }
  }
}
