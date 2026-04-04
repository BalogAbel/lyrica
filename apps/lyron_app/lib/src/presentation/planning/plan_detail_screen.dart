import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lyron_app/src/domain/planning/plan_detail.dart';
import 'package:lyron_app/src/domain/planning/session_item_summary.dart';
import 'package:lyron_app/src/domain/planning/session_summary.dart';
import 'package:lyron_app/src/presentation/planning/planning_providers.dart';
import 'package:lyron_app/src/presentation/planning/planning_routes.dart';
import 'package:lyron_app/src/presentation/song_library/song_library_providers.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

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
                  _SessionCard(planDetail: detail, session: session),
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
  const _SessionCard({required this.planDetail, required this.session});

  final PlanDetail planDetail;
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
              _SongItemButton(
                planDetail: planDetail,
                session: session,
                item: item,
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _SongItemButton extends ConsumerWidget {
  const _SongItemButton({
    required this.planDetail,
    required this.session,
    required this.item,
  });

  final PlanDetail planDetail;
  final SessionSummary session;
  final SessionItemSummary item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolvedSongSlug = ref
        .watch(songLibrarySongByIdProvider(item.song.id))
        .valueOrNull
        ?.slug;
    return InkWell(
      key: ValueKey('plan-session-item-${item.id}'),
      onTap: resolvedSongSlug == null
          ? null
          : () {
              context.push(
                PlanningRoutes.planSessionSongReaderLocation(
                  planSlug: planDetail.plan.slug,
                  sessionSlug: session.slug,
                  songSlug: resolvedSongSlug,
                ),
                extra: planDetail,
              );
            },
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(child: Text('${item.position}. ${item.song.title}')),
            const Icon(Icons.chevron_right),
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
