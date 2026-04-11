import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/domain/planning/plan_detail.dart';
import 'package:lyron_app/src/domain/planning/plan_summary.dart';
import 'package:lyron_app/src/domain/planning/planning_repository.dart';
import 'package:lyron_app/src/domain/planning/session_summary.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';

class ActivePlanningReadContext {
  const ActivePlanningReadContext({
    required this.userId,
    required this.organizationId,
  });

  final String userId;
  final String organizationId;

  @override
  bool operator ==(Object other) {
    return other is ActivePlanningReadContext &&
        other.userId == userId &&
        other.organizationId == organizationId;
  }

  @override
  int get hashCode => Object.hash(userId, organizationId);
}

typedef ActivePlanningReadContextReader =
    Future<ActivePlanningReadContext?> Function();

class PlanningLocalReadRepository implements PlanningRepository {
  const PlanningLocalReadRepository({
    required PlanningLocalStore store,
    PlanningMutationStore? mutationStore,
    required ActivePlanningReadContextReader contextReader,
  }) : _store = store,
       _mutationStore = mutationStore,
       _contextReader = contextReader;

  final PlanningLocalStore _store;
  final PlanningMutationStore? _mutationStore;
  final ActivePlanningReadContextReader _contextReader;

  @override
  Future<List<PlanSummary>> listPlans() async {
    final context = await _requireContext();
    final basePlans = await _store.readPlanSummaries(
      userId: context.userId,
      organizationId: context.organizationId,
    );
    final pendingMutations = await _readPendingMutations(context);
    return _mergePlanSummaries(basePlans, pendingMutations);
  }

  @override
  Future<PlanDetail> getPlanDetail(String planId) async {
    final context = await _requireContext();
    final detail = await _store.readPlanDetail(
      userId: context.userId,
      organizationId: context.organizationId,
      planId: planId,
    );
    final pendingMutations = await _readPendingMutations(context);
    final merged = _mergePlanDetail(detail, planId, pendingMutations);
    if (merged == null) {
      throw StateError('Plan not found in local planning projection: $planId');
    }

    return merged;
  }

  @override
  Future<PlanSummary?> getPlanSummaryBySlug(String planSlug) async {
    final plans = await listPlans();
    for (final plan in plans) {
      if (plan.slug == planSlug) {
        return plan;
      }
    }
    return null;
  }

  @override
  Future<PlanDetail?> getPlanDetailBySlug(String planSlug) async {
    final summary = await getPlanSummaryBySlug(planSlug);
    if (summary == null) {
      return null;
    }
    return getPlanDetail(summary.id);
  }

  Future<ActivePlanningReadContext> _requireContext() async {
    final context = await _contextReader();
    if (context == null) {
      throw StateError('Active planning context is unavailable.');
    }

    return context;
  }

  Future<List<PlanningMutationRecord>> _readPendingMutations(
    ActivePlanningReadContext context,
  ) async {
    final mutationStore = _mutationStore;
    if (mutationStore == null) {
      return const [];
    }

    return mutationStore.readPendingMutations(
      userId: context.userId,
      organizationId: context.organizationId,
    );
  }

  List<PlanSummary> _mergePlanSummaries(
    List<PlanSummary> basePlans,
    List<PlanningMutationRecord> mutations,
  ) {
    final plansById = {
      for (final plan in basePlans) plan.id: plan,
    };

    for (final mutation in mutations) {
      switch (mutation.kind) {
        case PlanningMutationKind.planCreate:
          plansById[mutation.aggregateId] = PlanSummary(
            id: mutation.aggregateId,
            slug: mutation.slug,
            name: mutation.name ?? '',
            description: mutation.description,
            scheduledFor: mutation.scheduledFor,
            updatedAt: mutation.updatedAt,
            version: 1,
          );
        case PlanningMutationKind.planEdit:
          final existing = plansById[mutation.aggregateId];
          if (existing == null) {
            continue;
          }
          plansById[mutation.aggregateId] = PlanSummary(
            id: existing.id,
            slug: existing.slug,
            name: mutation.name ?? existing.name,
            description: mutation.description,
            scheduledFor: mutation.scheduledFor,
            updatedAt: mutation.updatedAt,
            version: existing.version,
          );
        case PlanningMutationKind.sessionCreate:
        case PlanningMutationKind.sessionRename:
        case PlanningMutationKind.sessionDelete:
          break;
      }
    }

    final merged = plansById.values.toList(growable: false);
    merged.sort((left, right) {
      final scheduledComparison = _compareScheduledFor(
        left.scheduledFor,
        right.scheduledFor,
      );
      if (scheduledComparison != 0) {
        return scheduledComparison;
      }
      final updatedComparison = right.updatedAt.compareTo(left.updatedAt);
      if (updatedComparison != 0) {
        return updatedComparison;
      }
      return left.id.compareTo(right.id);
    });
    return merged;
  }

  PlanDetail? _mergePlanDetail(
    PlanDetail? baseDetail,
    String planId,
    List<PlanningMutationRecord> mutations,
  ) {
    PlanSummary? plan = baseDetail?.plan;
    final sessionsById = {
      for (final session in baseDetail?.sessions ?? const <SessionSummary>[])
        session.id: session,
    };

    for (final mutation in mutations) {
      if (mutation.aggregateId == planId &&
          mutation.kind == PlanningMutationKind.planCreate) {
        plan = PlanSummary(
          id: mutation.aggregateId,
          slug: mutation.slug,
          name: mutation.name ?? '',
          description: mutation.description,
          scheduledFor: mutation.scheduledFor,
          updatedAt: mutation.updatedAt,
          version: 1,
        );
      } else if (mutation.aggregateId == planId &&
          mutation.kind == PlanningMutationKind.planEdit &&
          plan != null) {
        plan = PlanSummary(
          id: plan.id,
          slug: plan.slug,
          name: mutation.name ?? plan.name,
          description: mutation.description,
          scheduledFor: mutation.scheduledFor,
          updatedAt: mutation.updatedAt,
          version: plan.version,
        );
      } else if (mutation.planId == planId) {
        switch (mutation.kind) {
          case PlanningMutationKind.sessionCreate:
            sessionsById[mutation.aggregateId] = SessionSummary(
              id: mutation.aggregateId,
              slug: mutation.slug,
              name: mutation.name ?? '',
              position: mutation.position ?? 0,
              version: 1,
              items: const [],
            );
          case PlanningMutationKind.sessionRename:
            final existing = sessionsById[mutation.aggregateId];
            if (existing == null) {
              continue;
            }
            sessionsById[mutation.aggregateId] = SessionSummary(
              id: existing.id,
              slug: existing.slug,
              name: mutation.name ?? existing.name,
              position: existing.position,
              version: existing.version,
              items: existing.items,
            );
          case PlanningMutationKind.sessionDelete:
            sessionsById.remove(mutation.aggregateId);
          case PlanningMutationKind.planCreate:
          case PlanningMutationKind.planEdit:
            break;
        }
      }
    }

    if (plan == null) {
      return null;
    }

    final sessions = sessionsById.values.toList(growable: false)
      ..sort((left, right) {
        final positionComparison = left.position.compareTo(right.position);
        if (positionComparison != 0) {
          return positionComparison;
        }
        return left.id.compareTo(right.id);
      });

    return PlanDetail(plan: plan, sessions: sessions);
  }

  int _compareScheduledFor(DateTime? left, DateTime? right) {
    if (left == null && right == null) {
      return 0;
    }
    if (left == null) {
      return 1;
    }
    if (right == null) {
      return -1;
    }
    return left.compareTo(right);
  }
}
