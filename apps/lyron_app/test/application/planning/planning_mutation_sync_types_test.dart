import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';

void main() {
  group('PlanningMutationSyncStatus', () {
    test('accepted status maps to and from "accepted"', () {
      expect(PlanningMutationSyncStatus.accepted.value, 'accepted');
      expect(planningMutationSyncStatusFromValue('accepted'), PlanningMutationSyncStatus.accepted);
    });
  });
}
