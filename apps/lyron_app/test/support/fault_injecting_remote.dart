import 'dart:async';

import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';

/// A planning remote repo that records call order and can be made to accept a
/// mutation but fail the subsequent refresh, simulating a partial RPC success
/// (LF-2) and a crash window before the local clear (LF-1).
class FaultInjectingPlanningRemote implements PlanningMutationRemoteRepository {
  final List<String> syncedAggregateIds = [];
  int concurrentPeak = 0;
  int _inFlight = 0;

  @override
  Future<PlanningMutationRecord> syncMutation({
    required String organizationId,
    required PlanningMutationRecord record,
  }) async {
    _inFlight += 1;
    concurrentPeak = _inFlight > concurrentPeak ? _inFlight : concurrentPeak;
    await Future<void>.delayed(Duration.zero);
    syncedAggregateIds.add(record.aggregateId);
    _inFlight -= 1;
    return record;
  }
}
