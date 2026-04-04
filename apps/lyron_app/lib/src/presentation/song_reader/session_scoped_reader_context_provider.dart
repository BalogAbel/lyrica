import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/domain/planning/plan_detail.dart';
import 'package:lyron_app/src/domain/planning/session_item_summary.dart';
import 'package:lyron_app/src/domain/planning/session_summary.dart';
import 'package:lyron_app/src/presentation/planning/planning_providers.dart';
import 'package:lyron_app/src/presentation/song_library/song_library_providers.dart';
import 'package:lyron_app/src/presentation/song_reader/session_scoped_reader_context.dart';
import 'package:lyron_app/src/presentation/song_reader/session_scoped_reader_context_resolver.dart';

final sessionScopedReaderContextProvider = FutureProvider.autoDispose
    .family<
      SessionScopedReaderContextResult,
      SessionScopedReaderContextRequest
    >((ref, request) async {
      final warmPlanDetail = request.warmPlanDetail;
      if (warmPlanDetail != null) {
        final canonicalWarmPlanDetail = await _canonicalizePlanDetailSongs(
          ref,
          warmPlanDetail,
        );
        return resolveSessionScopedReaderContext(
          planDetail: canonicalWarmPlanDetail,
          planId: request.planId,
          sessionId: request.sessionId,
          sessionItemId: request.sessionItemId,
          songId: request.songId,
        );
      }

      try {
        final planDetail = await ref.watch(
          planningPlanDetailProvider(request.planId).future,
        );
        final canonicalPlanDetail = await _canonicalizePlanDetailSongs(
          ref,
          planDetail,
        );
        return resolveSessionScopedReaderContext(
          planDetail: canonicalPlanDetail,
          planId: request.planId,
          sessionId: request.sessionId,
          sessionItemId: request.sessionItemId,
          songId: request.songId,
        );
      } on Exception {
        return const SessionScopedReaderContextFailureResult(
          SessionScopedReaderContextFailure.unavailablePlanDetail,
        );
      }
    });

Future<PlanDetail> _canonicalizePlanDetailSongs(
  Ref ref,
  PlanDetail planDetail,
) async {
  try {
    final songs = await ref.watch(songLibraryListProvider.future);
    final songsById = {for (final song in songs) song.id: song};

    return PlanDetail(
      plan: planDetail.plan,
      sessions: [
        for (final session in planDetail.sessions)
          SessionSummary(
            id: session.id,
            slug: session.slug,
            name: session.name,
            position: session.position,
            items: [
              for (final item in session.items)
                SessionItemSummary(
                  id: item.id,
                  slug: item.slug,
                  position: item.position,
                  song: songsById[item.song.id] ?? item.song,
                ),
            ],
          ),
      ],
    );
  } catch (_) {
    return planDetail;
  }
}
