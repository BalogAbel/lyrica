import 'package:lyron_app/src/domain/planning/plan_detail.dart';
import 'package:lyron_app/src/domain/planning/plan_summary.dart';
import 'package:lyron_app/src/domain/planning/planning_repository.dart';
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
    required ActivePlanningReadContextReader contextReader,
  }) : _store = store,
       _contextReader = contextReader;

  final PlanningLocalStore _store;
  final ActivePlanningReadContextReader _contextReader;

  @override
  Future<List<PlanSummary>> listPlans() async {
    final context = await _requireContext();
    return _store.readPlanSummaries(
      userId: context.userId,
      organizationId: context.organizationId,
    );
  }

  @override
  Future<PlanDetail> getPlanDetail(String planId) async {
    final context = await _requireContext();
    final detail = await _store.readPlanDetail(
      userId: context.userId,
      organizationId: context.organizationId,
      planId: planId,
    );
    if (detail == null) {
      throw StateError('Plan not found in local planning projection: $planId');
    }

    return detail;
  }

  Future<ActivePlanningReadContext> _requireContext() async {
    final context = await _contextReader();
    if (context == null) {
      throw StateError('Active planning context is unavailable.');
    }

    return context;
  }
}
