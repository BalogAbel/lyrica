import 'package:lyron_app/src/domain/planning/plan_summary.dart';
import 'package:lyron_app/src/domain/planning/session_summary.dart';

class PlanDetail {
  const PlanDetail({required this.plan, required this.sessions});

  final PlanSummary plan;
  final List<SessionSummary> sessions;

  @override
  bool operator ==(Object other) {
    return other is PlanDetail &&
        other.plan == plan &&
        _listEquals(other.sessions, sessions);
  }

  @override
  int get hashCode => Object.hash(plan, Object.hashAll(sessions));
}

bool _listEquals<T>(List<T> left, List<T> right) {
  if (left.length != right.length) {
    return false;
  }

  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }

  return true;
}
