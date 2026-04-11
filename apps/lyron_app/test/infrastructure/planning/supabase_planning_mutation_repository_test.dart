import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/infrastructure/planning/supabase_planning_mutation_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('maps a plan create mutation to create_plan rpc params', () async {
    late String rpcName;
    late Map<String, dynamic> rpcParams;
    final repository = SupabasePlanningMutationRepository.testing(
      rpc: (name, {params}) async {
        rpcName = name;
        rpcParams = params ?? const {};
        return {
          'id': 'plan-1',
          'organization_id': 'org-1',
          'slug': 'weekend-service-2',
          'version': 1,
        };
      },
    );

    final result = await repository.syncMutation(
      organizationId: 'org-1',
      record: PlanningMutationRecord(
        aggregateId: 'plan-1',
        organizationId: 'org-1',
        slug: 'weekend-service',
        name: 'Weekend Service',
        description: 'Draft',
        kind: PlanningMutationKind.planCreate,
        syncStatus: PlanningMutationSyncStatus.pending,
        orderKey: 1,
        updatedAt: DateTime.utc(2026),
      ),
    );

    expect(rpcName, 'create_plan');
    expect(rpcParams['p_plan_id'], 'plan-1');
    expect(rpcParams['p_slug'], 'weekend-service');
    expect(result.slug, 'weekend-service-2');
    expect(result.baseVersion, 1);
  });

  test('maps version conflicts to sync exceptions', () async {
    final repository = SupabasePlanningMutationRepository.testing(
      rpc: (name, {params}) async {
        throw PostgrestException(message: 'plan_version_conflict', code: 'P0001');
      },
    );

    await expectLater(
      () => repository.syncMutation(
        organizationId: 'org-1',
        record: PlanningMutationRecord(
          aggregateId: 'plan-1',
          organizationId: 'org-1',
          name: 'Weekend Service',
          baseVersion: 1,
          kind: PlanningMutationKind.planEdit,
          syncStatus: PlanningMutationSyncStatus.pending,
          orderKey: 1,
          updatedAt: DateTime.utc(2026),
        ),
      ),
      throwsA(
        isA<PlanningMutationSyncException>().having(
          (error) => error.code,
          'code',
          PlanningMutationSyncErrorCode.conflict,
        ),
      ),
    );
  });
}
