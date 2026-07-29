import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lyron_app/src/domain/planning/plan_detail.dart';
import 'package:lyron_app/src/presentation/planning/planning_routes.dart';
import 'package:lyron_app/src/presentation/song_reader/session_scoped_reader_context.dart';
import 'package:lyron_app/src/presentation/song_reader/session_scoped_reader_runtime_controller.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_immersive_mode.dart';
import 'package:lyron_app/src/router/app_routes.dart';

/// Scoped (plan-session) reader navigation: back handling, starting the
/// scoped runtime session, and previous/next neighbor navigation.
///
/// Plain class (not a widget) — same shape as `SongReaderSongActions`. Values
/// tied to the screen's `widget` become constructor parameters;
/// `BuildContext`/`WidgetRef` are method parameters. `mounted` cannot be read
/// directly (only the screen's `State` object has it), so callers pass an
/// `isMounted` callback in exactly where the original code guarded on it.
class SongReaderScopedNavigation {
  const SongReaderScopedNavigation({
    required this.planId,
    required this.sessionId,
    required this.sessionItemId,
    required this.warmPlanDetail,
    required this.songId,
  });

  final String? planId;
  final String? sessionId;
  final String? sessionItemId;
  final PlanDetail? warmPlanDetail;
  final String songId;

  bool get isScopedMode =>
      planId != null && sessionId != null && sessionItemId != null;

  String get _sessionKey => '$planId:$sessionId';

  void handleBack(
    BuildContext context, {
    required SongReaderImmersiveMode immersiveMode,
  }) {
    immersiveMode.apply(false);
    if (context.canPop()) {
      context.pop();
      return;
    }

    if (isScopedMode) {
      final planSlug = warmPlanDetail?.plan.slug ?? planId!;
      context.replace(PlanningRoutes.planDetailLocation(planSlug));
      return;
    }

    context.replace(AppRoutes.home.path);
  }

  void syncScopedRuntimeState({
    required WidgetRef ref,
    required bool Function() isMounted,
  }) {
    if (!isScopedMode) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isMounted()) {
        return;
      }

      ref
          .read(sessionScopedReaderRuntimeControllerProvider(_sessionKey))
          .startSession(planId: planId!, sessionId: sessionId!, songId: songId);
    });
  }

  void _navigateToScopedSong(
    BuildContext context, {
    required SessionScopedReaderContext scopedContext,
    required String songSlug,
  }) {
    context.replace(
      PlanningRoutes.planSessionSongReaderLocation(
        planSlug: scopedContext.planSlug,
        sessionSlug: scopedContext.sessionSlug,
        songSlug: songSlug,
      ),
      extra: warmPlanDetail,
    );
  }

  VoidCallback? buildScopedNeighborNavigationTap(
    BuildContext context, {
    required SessionScopedReaderContext? scopedContext,
    required SessionScopedReaderNeighbor? neighbor,
  }) {
    if (scopedContext == null || neighbor == null) {
      return null;
    }

    return () => _navigateToScopedSong(
      context,
      scopedContext: scopedContext,
      songSlug: neighbor.songSlug,
    );
  }
}
