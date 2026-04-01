import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/domain/planning/plan_detail.dart';
import 'package:lyron_app/src/domain/planning/plan_summary.dart';

final planningPlanListProvider = FutureProvider.autoDispose<List<PlanSummary>>((
  ref,
) {
  return ref.watch(planningRepositoryProvider).listPlans();
});

final planningPlanDetailProvider = FutureProvider.autoDispose
    .family<PlanDetail, String>((ref, planId) {
      return ref.watch(planningRepositoryProvider).getPlanDetail(planId);
    });
