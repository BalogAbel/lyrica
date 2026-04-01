import 'package:lyrica_app/src/domain/planning/plan_detail.dart';

enum SessionScopedReaderContextFailure {
  invalidRouteContext,
  unavailablePlanDetail,
}

class SessionScopedReaderNeighbor {
  const SessionScopedReaderNeighbor({
    required this.sessionItemId,
    required this.songId,
    required this.title,
  });

  final String sessionItemId;
  final String songId;
  final String title;

  @override
  bool operator ==(Object other) {
    return other is SessionScopedReaderNeighbor &&
        other.sessionItemId == sessionItemId &&
        other.songId == songId &&
        other.title == title;
  }

  @override
  int get hashCode => Object.hash(sessionItemId, songId, title);
}

class SessionScopedReaderContext {
  const SessionScopedReaderContext({
    required this.planId,
    required this.sessionId,
    required this.sessionItemId,
    required this.songId,
    required this.selectedItem,
    required this.previousItem,
    required this.nextItem,
  });

  final String planId;
  final String sessionId;
  final String sessionItemId;
  final String songId;
  final SessionScopedReaderNeighbor selectedItem;
  final SessionScopedReaderNeighbor? previousItem;
  final SessionScopedReaderNeighbor? nextItem;

  @override
  bool operator ==(Object other) {
    return other is SessionScopedReaderContext &&
        other.planId == planId &&
        other.sessionId == sessionId &&
        other.sessionItemId == sessionItemId &&
        other.songId == songId &&
        other.selectedItem == selectedItem &&
        other.previousItem == previousItem &&
        other.nextItem == nextItem;
  }

  @override
  int get hashCode => Object.hash(
    planId,
    sessionId,
    sessionItemId,
    songId,
    selectedItem,
    previousItem,
    nextItem,
  );
}

sealed class SessionScopedReaderContextResult {
  const SessionScopedReaderContextResult();
}

class ResolvedSessionScopedReaderContextResult
    extends SessionScopedReaderContextResult {
  const ResolvedSessionScopedReaderContextResult(this.context);

  final SessionScopedReaderContext context;

  @override
  bool operator ==(Object other) {
    return other is ResolvedSessionScopedReaderContextResult &&
        other.context == context;
  }

  @override
  int get hashCode => context.hashCode;
}

class SessionScopedReaderContextFailureResult
    extends SessionScopedReaderContextResult {
  const SessionScopedReaderContextFailureResult(this.failure);

  final SessionScopedReaderContextFailure failure;

  @override
  bool operator ==(Object other) {
    return other is SessionScopedReaderContextFailureResult &&
        other.failure == failure;
  }

  @override
  int get hashCode => failure.hashCode;
}

class SessionScopedReaderContextRequest {
  const SessionScopedReaderContextRequest({
    required this.planId,
    required this.sessionId,
    required this.sessionItemId,
    required this.songId,
    this.warmPlanDetail,
  });

  final String planId;
  final String sessionId;
  final String sessionItemId;
  final String songId;
  final PlanDetail? warmPlanDetail;

  @override
  bool operator ==(Object other) {
    return other is SessionScopedReaderContextRequest &&
        other.planId == planId &&
        other.sessionId == sessionId &&
        other.sessionItemId == sessionItemId &&
        other.songId == songId &&
        other.warmPlanDetail == warmPlanDetail;
  }

  @override
  int get hashCode =>
      Object.hash(planId, sessionId, sessionItemId, songId, warmPlanDetail);
}
