import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/application/planning/planning_sync_state.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/domain/planning/plan_detail.dart';
import 'package:lyron_app/src/domain/planning/plan_summary.dart';

final planningPlanListProvider = FutureProvider.autoDispose<List<PlanSummary>>((
  ref,
) {
  return _readPlanningOrThrow<List<PlanSummary>>(
    ref,
    () => ref.watch(planningRepositoryProvider).listPlans(),
  );
});

final planningPlanBySlugProvider = FutureProvider.autoDispose
    .family<PlanSummary?, String>((ref, planSlug) async {
      return ref
          .watch(planningRepositoryProvider)
          .getPlanSummaryBySlug(planSlug);
    });

final planningPlanDetailBySlugProvider = FutureProvider.autoDispose
    .family<PlanDetail?, String>((ref, planSlug) async {
      return ref
          .watch(planningRepositoryProvider)
          .getPlanDetailBySlug(planSlug);
    });

final planningPlanDetailProvider = FutureProvider.autoDispose
    .family<PlanDetail, String>((ref, planId) {
      return _readPlanningOrThrow<PlanDetail>(
        ref,
        () => ref.watch(planningRepositoryProvider).getPlanDetail(planId),
      );
    });

Future<T> _readPlanningOrThrow<T>(Ref ref, Future<T> Function() read) async {
  final syncState = ref.watch(planningSyncStateProvider);
  if (syncState.accessStatus == PlanningAccessStatus.signedOut) {
    throw StateError(
      'Planning is unavailable without an authenticated session.',
    );
  }

  if (!syncState.hasLocalPlanningData) {
    await ref.read(planningSyncControllerProvider).refreshPlanning();
    final refreshedState = ref.read(planningSyncStateProvider);
    if (!refreshedState.hasLocalPlanningData) {
      throw StateError(
        'Planning local data is unavailable for the active organization.',
      );
    }
  }

  return read();
}
