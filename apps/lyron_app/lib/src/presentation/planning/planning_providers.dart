import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/application/planning/planning_data_revision.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/application/planning/planning_sync_state.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/domain/planning/plan_detail.dart';
import 'package:lyron_app/src/domain/planning/plan_summary.dart';

final planningPlanListProvider = FutureProvider.autoDispose<List<PlanSummary>>((
  ref,
) {
  ref.watch(planningDataRevisionProvider);
  return _readPlanningOrThrow<List<PlanSummary>>(
    ref,
    () => ref.watch(planningRepositoryProvider).listPlans(),
  );
});

final planningPlanBySlugProvider = FutureProvider.autoDispose
    .family<PlanSummary?, String>((ref, planSlug) async {
      ref.watch(planningDataRevisionProvider);
      return ref
          .watch(planningRepositoryProvider)
          .getPlanSummaryBySlug(planSlug);
    });

final planningPlanDetailBySlugProvider = FutureProvider.autoDispose
    .family<PlanDetail?, String>((ref, planSlug) async {
      ref.watch(planningDataRevisionProvider);
      return ref
          .watch(planningRepositoryProvider)
          .getPlanDetailBySlug(planSlug);
    });

final planningPlanDetailProvider = FutureProvider.autoDispose
    .family<PlanDetail, String>((ref, planId) {
      ref.watch(planningDataRevisionProvider);
      return _readPlanningOrThrow<PlanDetail>(
        ref,
        () => ref.watch(planningRepositoryProvider).getPlanDetail(planId),
      );
    });

final planningMutationEntriesProvider =
    FutureProvider.autoDispose<List<PlanningMutationRecord>>((ref) async {
      ref.watch(planningDataRevisionProvider);
      final context = ref.watch(activePlanningContextProvider);
      if (context == null) {
        return const [];
      }

      final entries = await ref.watch(planningMutationStoreProvider).readAllMutations(
        userId: context.userId,
        organizationId: context.organizationId,
      );

      return [...entries]..sort((left, right) {
        final orderCompare = left.orderKey.compareTo(right.orderKey);
        if (orderCompare != 0) {
          return orderCompare;
        }
        return left.aggregateId.compareTo(right.aggregateId);
      });
    });

final hasUnsyncedPlanningMutationsProvider = FutureProvider.autoDispose<bool>((
  ref,
) {
  ref.watch(planningDataRevisionProvider);
  final session = ref.watch(appAuthControllerProvider).state.session;
  final userId = session?.userId;
  if (userId == null) {
    return Future.value(false);
  }

  return ref
      .watch(planningMutationStoreProvider)
      .hasUnsyncedMutations(userId: userId);
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
