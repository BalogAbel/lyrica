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
    required PlanningLocalStore Function() localStore,
  }) : _localStore = localStore;

  final PlanningLocalStore Function() _localStore;

  Future<void> reconcile(
    ActivePlanningReadContext context,
    PlanningMutationRecord record,
  ) async {
    final localStore = _localStore();
    final reconciledAt = DateTime.now().toUtc();

    switch (record.kind) {
      case PlanningMutationKind.planCreate:
      case PlanningMutationKind.planEdit:
        await localStore.upsertSyncedPlan(
          userId: context.userId,
          organizationId: context.organizationId,
          refreshedAt: reconciledAt,
          plan: CachedPlanRecord(
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
          ),
        );
        return;
      case PlanningMutationKind.sessionCreate:
      case PlanningMutationKind.sessionRename:
        await localStore.upsertSyncedSession(
          userId: context.userId,
          organizationId: context.organizationId,
          refreshedAt: reconciledAt,
          session: CachedSessionRecord(
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
            // version default for a freshly reconciled aggregate.
            version: record.baseVersion ?? 1,
          ),
        );
        return;
      case PlanningMutationKind.sessionDelete:
        await localStore.deleteSyncedSession(
          userId: context.userId,
          organizationId: context.organizationId,
          sessionId: record.aggregateId,
          refreshedAt: reconciledAt,
        );
        return;
      case PlanningMutationKind.sessionReorder:
        await localStore.replaceSyncedSessionOrder(
          userId: context.userId,
          organizationId: context.organizationId,
          planId: record.planId ?? record.aggregateId,
          orderedSessionIds: record.orderedSiblingIds ?? const [],
          orderedSessionPositions: record.orderedSiblingPositions,
          // version default for a freshly reconciled aggregate.
          planVersion: record.baseVersion ?? 1,
          refreshedAt: reconciledAt,
        );
        return;
      case PlanningMutationKind.sessionItemCreateSong:
        await localStore.upsertSyncedSessionItem(
          userId: context.userId,
          organizationId: context.organizationId,
          refreshedAt: reconciledAt,
          // version default for a freshly reconciled aggregate.
          sessionVersion: record.baseVersion ?? 1,
          item: CachedSessionItemRecord(
            id: record.aggregateId,
            // planId, sessionId, songId, songTitle and position are all
            // required on PlanningSessionItemCreateSongMutationDraft: a
            // null here means a corrupt mutation, not an absent optional
            // value. Coercing to '' / 0 would silently persist a fabricated
            // row instead of surfacing the corruption (LF-8).
            planId: _required(record.planId, 'planId', record.kind),
            sessionId: _required(record.sessionId, 'sessionId', record.kind),
            position: _required(record.position, 'position', record.kind),
            songId: _required(record.songId, 'songId', record.kind),
            songTitle: _required(record.songTitle, 'songTitle', record.kind),
          ),
        );
        if (record.orderedSiblingIds != null) {
          await localStore.replaceSyncedSessionItemOrder(
            userId: context.userId,
            organizationId: context.organizationId,
            sessionId: _required(record.sessionId, 'sessionId', record.kind),
            orderedSessionItemIds: record.orderedSiblingIds!,
            orderedSessionItemPositions: record.orderedSiblingPositions,
            // version default for a freshly reconciled aggregate.
            sessionVersion: record.baseVersion ?? 1,
            refreshedAt: reconciledAt,
          );
        }
        return;
      case PlanningMutationKind.sessionItemDelete:
        // sessionId/sessionItemId here identify an EXISTING row to delete,
        // not a field on a create draft, so this is out of scope for the
        // create-path corruption fix (LF-8); left as-is.
        await localStore.deleteSyncedSessionItem(
          userId: context.userId,
          organizationId: context.organizationId,
          sessionId: record.sessionId ?? '',
          sessionItemId: record.aggregateId,
          // version default for a freshly reconciled aggregate.
          sessionVersion: record.baseVersion ?? 1,
          refreshedAt: reconciledAt,
        );
        if (record.orderedSiblingIds != null) {
          await localStore.replaceSyncedSessionItemOrder(
            userId: context.userId,
            organizationId: context.organizationId,
            sessionId: record.sessionId ?? '',
            orderedSessionItemIds: record.orderedSiblingIds!,
            orderedSessionItemPositions: record.orderedSiblingPositions,
            // version default for a freshly reconciled aggregate.
            sessionVersion: record.baseVersion ?? 1,
            refreshedAt: reconciledAt,
          );
        }
        return;
      case PlanningMutationKind.sessionItemReorder:
        await localStore.replaceSyncedSessionItemOrder(
          userId: context.userId,
          organizationId: context.organizationId,
          sessionId: record.sessionId ?? '',
          orderedSessionItemIds: record.orderedSiblingIds ?? const [],
          orderedSessionItemPositions: record.orderedSiblingPositions,
          // version default for a freshly reconciled aggregate.
          sessionVersion: record.baseVersion ?? 1,
          refreshedAt: reconciledAt,
        );
        return;
    }
  }
}
