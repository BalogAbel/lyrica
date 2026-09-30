import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';

void main() {
  group('PlanningMutationSyncStatus', () {
    test('accepted status maps to and from "accepted"', () {
      expect(PlanningMutationSyncStatus.accepted.value, 'accepted');
      expect(
        planningMutationSyncStatusFromValue('accepted'),
        PlanningMutationSyncStatus.accepted,
      );
    });
  });

  test('planDelete persists as plan_delete on the plan aggregate and does '
      'not count as plan content (spec D4, D7)', () {
    expect(PlanningMutationKind.planDelete.value, 'plan_delete');
    expect(
      planningMutationKindFromValue('plan_delete'),
      PlanningMutationKind.planDelete,
    );
    expect(PlanningMutationKind.planDelete.aggregateType, 'plan');
    expect(
      {
        for (final kind in PlanningMutationKind.values)
          if (kind.bumpsPlanContent) kind,
      },
      {
        PlanningMutationKind.sessionCreate,
        PlanningMutationKind.sessionRename,
        PlanningMutationKind.sessionDelete,
        PlanningMutationKind.sessionReorder,
        PlanningMutationKind.sessionItemCreateSong,
        PlanningMutationKind.sessionItemDelete,
        PlanningMutationKind.sessionItemReorder,
      },
    );
  });
}
