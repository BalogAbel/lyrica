import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lyrica_app/src/domain/planning/plan_detail.dart';
import 'package:lyrica_app/src/domain/planning/session_summary.dart';
import 'package:lyrica_app/src/presentation/planning/planning_providers.dart';
import 'package:lyrica_app/src/shared/app_strings.dart';

class PlanDetailScreen extends ConsumerWidget {
  const PlanDetailScreen({super.key, required this.planId});

  final String planId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(planningPlanDetailProvider(planId));

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.planDetailTitle),
        leading: BackButton(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            }
          },
        ),
      ),
      body: SafeArea(
        child: detailAsync.when(
          loading: () =>
              const Center(child: Text(AppStrings.planDetailLoadingMessage)),
          error: (error, stackTrace) => _RetryableErrorState(
            message: AppStrings.planDetailLoadFailureMessage,
            onRetry: () => ref.invalidate(planningPlanDetailProvider(planId)),
          ),
          data: (PlanDetail detail) {
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  detail.plan.name,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 20),
                for (final session in detail.sessions) ...[
                  _SessionCard(session: session),
                  const SizedBox(height: 16),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.session});

  final SessionSummary session;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(session.name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('${AppStrings.sessionLabel} ${session.position}'),
            const SizedBox(height: 12),
            for (final item in session.items) ...[
              Text('${item.position}. ${item.song.title}'),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
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
