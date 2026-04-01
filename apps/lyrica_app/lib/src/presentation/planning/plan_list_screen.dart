import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lyrica_app/src/domain/planning/plan_summary.dart';
import 'package:lyrica_app/src/presentation/planning/planning_providers.dart';
import 'package:lyrica_app/src/presentation/planning/planning_routes.dart';
import 'package:lyrica_app/src/shared/app_strings.dart';

class PlanListScreen extends ConsumerWidget {
  const PlanListScreen({super.key});

  static const _contentWidth = 720.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plansAsync = ref.watch(planningPlanListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.planListTitle),
        leading: BackButton(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            }
          },
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _contentWidth),
            child: plansAsync.when(
              loading: () =>
                  const Center(child: Text(AppStrings.planListLoadingMessage)),
              error: (error, stackTrace) => _RetryableErrorState(
                message: AppStrings.planListLoadFailureMessage,
                onRetry: () => ref.invalidate(planningPlanListProvider),
              ),
              data: (plans) {
                if (plans.isEmpty) {
                  return const Center(
                    child: Text(AppStrings.planListEmptyMessage),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(24),
                  itemCount: plans.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final plan = plans[index];

                    return ListTile(
                      title: Text(plan.name),
                      subtitle: _PlanSummarySubtitle(plan: plan),
                      onTap: () => context.push(
                        PlanningRoutes.planDetailLocation(plan.id),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _PlanSummarySubtitle extends StatelessWidget {
  const _PlanSummarySubtitle({required this.plan});

  final PlanSummary plan;

  @override
  Widget build(BuildContext context) {
    final scheduledFor = plan.scheduledFor;
    if (scheduledFor == null) {
      return const Text(AppStrings.planListUnscheduledLabel);
    }

    return Text(scheduledFor.toIso8601String());
  }
}

class _RetryableErrorState extends StatelessWidget {
  const _RetryableErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: onRetry,
            child: const Text(AppStrings.retryAction),
          ),
        ],
      ),
    );
  }
}
