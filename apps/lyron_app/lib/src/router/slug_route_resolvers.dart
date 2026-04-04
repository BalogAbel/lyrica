import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/song_library/catalog_refresh_status.dart';
import 'package:lyron_app/src/presentation/planning/plan_detail_screen.dart';
import 'package:lyron_app/src/presentation/planning/planning_providers.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_screen.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

class SongSlugRouteResolver extends ConsumerWidget {
  const SongSlugRouteResolver({super.key, required this.songSlug});

  final String songSlug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogState = ref.watch(catalogSnapshotStateProvider);
    if (catalogState.context == null &&
        catalogState.refreshStatus == CatalogRefreshStatus.refreshing) {
      return const _RouteStateScaffold(
        message: AppStrings.songReaderLoadingMessage,
      );
    }

    final songsAsync = ref.watch(songLibraryListProvider);
    return songsAsync.when(
      loading: () => const _RouteStateScaffold(
        message: AppStrings.songReaderLoadingMessage,
      ),
      error: (error, stackTrace) => const _RouteStateScaffold(
        message: AppStrings.songReaderLoadFailureMessage,
      ),
      data: (songs) {
        final song = songs.firstWhereOrNull(
          (candidate) => candidate.slug == songSlug,
        );
        if (song == null) {
          return const _RouteStateScaffold(
            message: AppStrings.routeNotFoundMessage,
          );
        }

        return SongReaderScreen(songId: song.id);
      },
    );
  }
}

class PlanSlugRouteResolver extends ConsumerWidget {
  const PlanSlugRouteResolver({super.key, required this.planSlug});

  final String planSlug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plansAsync = ref.watch(planningPlanListProvider);
    return plansAsync.when(
      loading: () => const _RouteStateScaffold(
        message: AppStrings.planDetailLoadingMessage,
      ),
      error: (error, stackTrace) => const _RouteStateScaffold(
        message: AppStrings.planDetailLoadFailureMessage,
      ),
      data: (plans) {
        final plan = plans.firstWhereOrNull(
          (candidate) => candidate.slug == planSlug,
        );
        if (plan == null) {
          return const _RouteStateScaffold(
            message: AppStrings.routeNotFoundMessage,
          );
        }

        return PlanDetailScreen(planId: plan.id);
      },
    );
  }
}

class PlanSessionSongSlugRouteResolver extends ConsumerWidget {
  const PlanSessionSongSlugRouteResolver({
    super.key,
    required this.planSlug,
    required this.sessionSlug,
    required this.songSlug,
  });

  final String planSlug;
  final String sessionSlug;
  final String songSlug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogState = ref.watch(catalogSnapshotStateProvider);
    if (catalogState.context == null &&
        catalogState.refreshStatus == CatalogRefreshStatus.refreshing) {
      return const _RouteStateScaffold(
        message: AppStrings.songReaderLoadingMessage,
      );
    }

    final plansAsync = ref.watch(planningPlanListProvider);
    final songsAsync = ref.watch(songLibraryListProvider);

    if (plansAsync.isLoading || songsAsync.isLoading) {
      return const _RouteStateScaffold(
        message: AppStrings.songReaderLoadingMessage,
      );
    }

    if (plansAsync.hasError) {
      return const _RouteStateScaffold(
        message: AppStrings.planDetailLoadFailureMessage,
      );
    }

    if (songsAsync.hasError) {
      return const _RouteStateScaffold(
        message: AppStrings.songReaderLoadFailureMessage,
      );
    }

    final plan = plansAsync.valueOrNull?.firstWhereOrNull(
      (candidate) => candidate.slug == planSlug,
    );
    if (plan == null) {
      return const _RouteStateScaffold(
        message: AppStrings.routeNotFoundMessage,
      );
    }

    final song = songsAsync.valueOrNull?.firstWhereOrNull(
      (candidate) => candidate.slug == songSlug,
    );
    if (song == null) {
      return const _RouteStateScaffold(
        message: AppStrings.routeNotFoundMessage,
      );
    }

    final detailAsync = ref.watch(planningPlanDetailProvider(plan.id));
    return detailAsync.when(
      loading: () => const _RouteStateScaffold(
        message: AppStrings.planDetailLoadingMessage,
      ),
      error: (error, stackTrace) => const _RouteStateScaffold(
        message: AppStrings.planDetailLoadFailureMessage,
      ),
      data: (detail) {
        final session = detail.sessions
            .where((candidate) => candidate.slug == sessionSlug)
            .firstOrNull;
        if (session == null) {
          return const _RouteStateScaffold(
            message: AppStrings.routeNotFoundMessage,
          );
        }

        final matchingItems = session.items
            .where((candidate) => candidate.song.id == song.id)
            .toList(growable: false);
        if (matchingItems.length != 1) {
          return const _RouteStateScaffold(
            message: AppStrings.routeNotFoundMessage,
          );
        }
        final selectedItem = matchingItems.single;

        return SongReaderScreen(
          songId: song.id,
          planId: detail.plan.id,
          sessionId: session.id,
          sessionItemId: selectedItem.id,
          warmPlanDetail: detail,
        );
      },
    );
  }
}

class _RouteStateScaffold extends StatelessWidget {
  const _RouteStateScaffold({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(child: Text(message, textAlign: TextAlign.center)),
      ),
    );
  }
}
