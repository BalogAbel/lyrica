import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';

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
            slug: record.slug ?? record.aggregateId,
            name: record.name ?? '',
            description: record.description,
            scheduledFor: record.scheduledFor,
            updatedAt: reconciledAt,
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
            planId: record.planId ?? '',
            slug: record.slug ?? record.aggregateId,
            position: record.position ?? 0,
            name: record.name ?? '',
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
          planVersion: record.baseVersion ?? 1,
          refreshedAt: reconciledAt,
        );
        return;
      case PlanningMutationKind.sessionItemCreateSong:
        await localStore.upsertSyncedSessionItem(
          userId: context.userId,
          organizationId: context.organizationId,
          refreshedAt: reconciledAt,
          sessionVersion: record.baseVersion ?? 1,
          item: CachedSessionItemRecord(
            id: record.aggregateId,
            planId: record.planId ?? '',
            sessionId: record.sessionId ?? '',
            position: record.position ?? 0,
            songId: record.songId ?? '',
            songTitle: record.songTitle ?? '',
          ),
        );
        if (record.orderedSiblingIds != null) {
          await localStore.replaceSyncedSessionItemOrder(
            userId: context.userId,
            organizationId: context.organizationId,
            sessionId: record.sessionId ?? '',
            orderedSessionItemIds: record.orderedSiblingIds!,
            orderedSessionItemPositions: record.orderedSiblingPositions,
            sessionVersion: record.baseVersion ?? 1,
            refreshedAt: reconciledAt,
          );
        }
        return;
      case PlanningMutationKind.sessionItemDelete:
        await localStore.deleteSyncedSessionItem(
          userId: context.userId,
          organizationId: context.organizationId,
          sessionId: record.sessionId ?? '',
          sessionItemId: record.aggregateId,
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
          sessionVersion: record.baseVersion ?? 1,
          refreshedAt: reconciledAt,
        );
        return;
    }
  }
}
