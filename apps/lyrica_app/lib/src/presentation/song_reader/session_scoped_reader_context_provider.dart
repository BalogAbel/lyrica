import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyrica_app/src/presentation/planning/planning_providers.dart';
import 'package:lyrica_app/src/presentation/song_reader/session_scoped_reader_context.dart';
import 'package:lyrica_app/src/presentation/song_reader/session_scoped_reader_context_resolver.dart';

final sessionScopedReaderContextProvider = FutureProvider.autoDispose
    .family<
      SessionScopedReaderContextResult,
      SessionScopedReaderContextRequest
    >((ref, request) async {
      final warmPlanDetail = request.warmPlanDetail;
      if (warmPlanDetail != null) {
        return resolveSessionScopedReaderContext(
          planDetail: warmPlanDetail,
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
        return resolveSessionScopedReaderContext(
          planDetail: planDetail,
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
