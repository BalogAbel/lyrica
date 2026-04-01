import 'package:lyrica_app/src/domain/planning/plan_detail.dart';
import 'package:lyrica_app/src/domain/planning/session_item_summary.dart';
import 'package:lyrica_app/src/presentation/song_reader/session_scoped_reader_context.dart';

SessionScopedReaderContextResult resolveSessionScopedReaderContext({
  required PlanDetail planDetail,
  required String planId,
  required String sessionId,
  required String sessionItemId,
  required String songId,
}) {
  if (planDetail.plan.id != planId) {
    return const SessionScopedReaderContextFailureResult(
      SessionScopedReaderContextFailure.invalidRouteContext,
    );
  }

  final session = planDetail.sessions
      .where((candidate) => candidate.id == sessionId)
      .firstOrNull;
  if (session == null) {
    return const SessionScopedReaderContextFailureResult(
      SessionScopedReaderContextFailure.invalidRouteContext,
    );
  }

  final orderedItems = [...session.items]
    ..sort((left, right) => left.position.compareTo(right.position));
  final selectedIndex = orderedItems.indexWhere(
    (item) => item.id == sessionItemId,
  );
  if (selectedIndex == -1) {
    return const SessionScopedReaderContextFailureResult(
      SessionScopedReaderContextFailure.invalidRouteContext,
    );
  }

  final selectedItem = orderedItems[selectedIndex];
  if (selectedItem.song.id != songId) {
    return const SessionScopedReaderContextFailureResult(
      SessionScopedReaderContextFailure.invalidRouteContext,
    );
  }

  return ResolvedSessionScopedReaderContextResult(
    SessionScopedReaderContext(
      planId: planId,
      sessionId: sessionId,
      sessionItemId: sessionItemId,
      songId: songId,
      selectedItem: _toNeighbor(selectedItem),
      previousItem: selectedIndex > 0
          ? _toNeighbor(orderedItems[selectedIndex - 1])
          : null,
      nextItem: selectedIndex < orderedItems.length - 1
          ? _toNeighbor(orderedItems[selectedIndex + 1])
          : null,
    ),
  );
}

SessionScopedReaderNeighbor _toNeighbor(SessionItemSummary item) {
  return SessionScopedReaderNeighbor(
    sessionItemId: item.id,
    songId: item.song.id,
    title: item.song.title,
  );
}
