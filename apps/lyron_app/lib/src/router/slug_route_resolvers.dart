import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/song_library/catalog_refresh_status.dart';
import 'package:lyron_app/src/domain/planning/session_item_summary.dart';
import 'package:lyron_app/src/domain/planning/session_summary.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/presentation/planning/plan_detail_screen.dart';
import 'package:lyron_app/src/presentation/planning/planning_providers.dart';
import 'package:lyron_app/src/presentation/song_editor/song_editor_providers.dart';
import 'package:lyron_app/src/presentation/song_editor/song_editor_screen.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_screen.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

/// Resolves the session item whose song matches [songSlug].
///
/// Plan detail data does not always carry the canonical song slug: the offline
/// store has no slug column, so cached session items fall back to the song id
/// as their slug. The session-scoped reader canonicalizes neighbor songs
/// against the song library before building navigation URLs, so neighbor links
/// use the library slug (e.g. `a-forrasnal`) even when the cached plan detail
/// only knows the song id. This matcher mirrors that canonicalization so the
/// route resolves regardless of which slug form the URL carries.
///
/// Returns the first matching item, or `null` when nothing matches. When a
/// session contains the same song more than once (e.g. a reprise), the URL
/// cannot distinguish the occurrences, so the first one is resolved instead of
/// failing the route.
@visibleForTesting
SessionItemSummary? resolveSessionItemBySongSlug({
  required SessionSummary session,
  required String songSlug,
  required Map<String, SongSummary> songsById,
}) {
  return session.items.firstWhereOrNull((item) {
    if (item.song.slug == songSlug || item.song.id == songSlug) {
      return true;
    }
    return songsById[item.song.id]?.slug == songSlug;
  });
}

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

class SongEditorSlugRouteResolver extends ConsumerWidget {
  const SongEditorSlugRouteResolver({super.key, required this.songSlug});

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

    final songAsync = ref.watch(songEditorRouteDataProvider(songSlug));
    return songAsync.when(
      loading: () => const _RouteStateScaffold(
        message: AppStrings.songReaderLoadingMessage,
      ),
      error: (error, stackTrace) => const _RouteStateScaffold(
        message: AppStrings.songReaderLoadFailureMessage,
      ),
      data: (song) {
        if (song == null) {
          return const _RouteStateScaffold(
            message: AppStrings.routeNotFoundMessage,
          );
        }

        return SongEditorScreen.edit(
          songId: song.songId,
          songSlug: song.songSlug,
          initialSource: song.source,
        );
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
      skipLoadingOnReload: true,
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
    if (plansAsync.isLoading && !plansAsync.hasValue) {
      return const _RouteStateScaffold(
        message: AppStrings.songReaderLoadingMessage,
      );
    }

    if (plansAsync.hasError) {
      return const _RouteStateScaffold(
        message: AppStrings.planDetailLoadFailureMessage,
      );
    }
    if (catalogState.context != null && songsAsync.isLoading) {
      return const _RouteStateScaffold(
        message: AppStrings.songReaderLoadingMessage,
      );
    }
    if (catalogState.context != null && songsAsync.hasError) {
      return const _RouteStateScaffold(
        message: AppStrings.songReaderLoadFailureMessage,
      );
    }

    final plan = plansAsync.value?.firstWhereOrNull(
      (candidate) => candidate.slug == planSlug,
    );
    if (plan == null) {
      return const _RouteStateScaffold(
        message: AppStrings.routeNotFoundMessage,
      );
    }

    final detailAsync = ref.watch(planningPlanDetailProvider(plan.id));
    return detailAsync.when(
      skipLoadingOnReload: true,
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

        final songsById = {
          for (final song in songsAsync.value ?? const <SongSummary>[])
            song.id: song,
        };
        final selectedItem = resolveSessionItemBySongSlug(
          session: session,
          songSlug: songSlug,
          songsById: songsById,
        );
        if (selectedItem == null) {
          return const _RouteStateScaffold(
            message: AppStrings.routeNotFoundMessage,
          );
        }

        return SongReaderScreen(
          songId: selectedItem.song.id,
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
