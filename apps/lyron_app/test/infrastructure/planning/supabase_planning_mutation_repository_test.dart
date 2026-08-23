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
        throw PostgrestException(
          message: 'plan_version_conflict',
          code: 'P0001',
        );
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

  test(
    'sends explicit null for a cleared planEdit description and scheduledFor',
    () async {
      late Map<String, dynamic> rpcParams;
      final repository = SupabasePlanningMutationRepository.testing(
        rpc: (name, {params}) async {
          rpcParams = params ?? const {};
          return {'id': 'plan-1', 'organization_id': 'org-1', 'version': 2};
        },
      );

      await repository.syncMutation(
        organizationId: 'org-1',
        record: PlanningMutationRecord(
          aggregateId: 'plan-1',
          organizationId: 'org-1',
          name: 'Weekend Service',
          description: null,
          scheduledFor: null,
          baseVersion: 1,
          kind: PlanningMutationKind.planEdit,
          syncStatus: PlanningMutationSyncStatus.pending,
          orderKey: 1,
          updatedAt: DateTime.utc(2026),
        ),
      );

      // A cleared field must reach the RPC as an explicit null key, not an
      // omitted one -- an omitted key would read as "leave unchanged" on
      // the server side and the clear would silently no-op there too.
      expect(rpcParams.containsKey('p_description'), isTrue);
      expect(rpcParams['p_description'], isNull);
      expect(rpcParams.containsKey('p_scheduled_for'), isTrue);
      expect(rpcParams['p_scheduled_for'], isNull);
    },
  );

  test('maps session reorder to the plan session reorder rpc', () async {
    late String rpcName;
    late Map<String, dynamic> rpcParams;
    final repository = SupabasePlanningMutationRepository.testing(
      rpc: (name, {params}) async {
        rpcName = name;
        rpcParams = params ?? const {};
        return {
          'plan_id': 'plan-1',
          'organization_id': 'org-1',
          'version': 4,
          'ordered_session_ids': ['session-3', 'session-1', 'session-2'],
          'ordered_session_positions': [10, 20, 30],
        };
      },
    );

    final result = await repository.syncMutation(
      organizationId: 'org-1',
      record: PlanningMutationRecord(
        aggregateId: 'plan-1',
        organizationId: 'org-1',
        planId: 'plan-1',
        orderedSiblingIds: const ['session-3', 'session-1', 'session-2'],
        baseVersion: 3,
        kind: PlanningMutationKind.sessionReorder,
        syncStatus: PlanningMutationSyncStatus.pending,
        orderKey: 1,
        updatedAt: DateTime.utc(2026),
      ),
    );

    expect(rpcName, 'reorder_plan_sessions');
    expect(rpcParams['p_plan_id'], 'plan-1');
    expect(rpcParams['p_base_version'], 3);
    expect(
      rpcParams['p_session_ids'],
      orderedEquals(const ['session-3', 'session-1', 'session-2']),
    );
    expect(result.baseVersion, 4);
    expect(
      result.orderedSiblingIds,
      orderedEquals(const ['session-3', 'session-1', 'session-2']),
    );
    expect(result.orderedSiblingPositions, orderedEquals(const [10, 20, 30]));
  });

  test('maps a table-style list rpc response using the first row', () async {
    final repository = SupabasePlanningMutationRepository.testing(
      rpc: (name, {params}) async => [
        {
          'plan_id': 'plan-1',
          'organization_id': 'org-1',
          'version': 4,
          'ordered_session_ids': ['session-3', 'session-1', 'session-2'],
          'ordered_session_positions': [10, 20, 30],
        },
      ],
    );

    final result = await repository.syncMutation(
      organizationId: 'org-1',
      record: PlanningMutationRecord(
        aggregateId: 'plan-1',
        organizationId: 'org-1',
        planId: 'plan-1',
        orderedSiblingIds: const ['session-3', 'session-1', 'session-2'],
        baseVersion: 3,
        kind: PlanningMutationKind.sessionReorder,
        syncStatus: PlanningMutationSyncStatus.pending,
        orderKey: 1,
        updatedAt: DateTime.utc(2026),
      ),
    );

    expect(result.baseVersion, 4);
    expect(
      result.orderedSiblingIds,
      orderedEquals(const ['session-3', 'session-1', 'session-2']),
    );
    expect(result.orderedSiblingPositions, orderedEquals(const [10, 20, 30]));
  });

  test(
    'maps session item create to the song-backed session item rpc',
    () async {
      late String rpcName;
      late Map<String, dynamic> rpcParams;
      final repository = SupabasePlanningMutationRepository.testing(
        rpc: (name, {params}) async {
          rpcName = name;
          rpcParams = params ?? const {};
          return {
            'id': 'item-9',
            'plan_id': 'plan-1',
            'session_id': 'session-1',
            'organization_id': 'org-1',
            'song_id': 'song-2',
            'song_title': 'Beta',
            'position': 30,
            'version': 5,
            'ordered_session_item_ids': ['item-1', 'item-9'],
            'ordered_session_item_positions': [10, 30],
          };
        },
      );

      final result = await repository.syncMutation(
        organizationId: 'org-1',
        record: PlanningMutationRecord(
          aggregateId: 'item-local-1',
          organizationId: 'org-1',
          planId: 'plan-1',
          sessionId: 'session-1',
          songId: 'song-2',
          songTitle: 'Beta',
          position: 30,
          baseVersion: 4,
          kind: PlanningMutationKind.sessionItemCreateSong,
          syncStatus: PlanningMutationSyncStatus.pending,
          orderKey: 1,
          updatedAt: DateTime.utc(2026),
        ),
      );

      expect(rpcName, 'create_song_session_item');
      expect(rpcParams.containsKey('p_plan_id'), isFalse);
      expect(rpcParams['p_session_id'], 'session-1');
      expect(rpcParams['p_song_id'], 'song-2');
      expect(rpcParams['p_position'], 30);
      expect(result.aggregateId, 'item-9');
      expect(result.sessionId, 'session-1');
      expect(result.songId, 'song-2');
      expect(result.songTitle, 'Beta');
      expect(
        result.orderedSiblingIds,
        orderedEquals(const ['item-1', 'item-9']),
      );
      expect(result.orderedSiblingPositions, orderedEquals(const [10, 30]));
    },
  );

  test('maps duplicate-song dependency errors to failed dependency', () async {
    final repository = SupabasePlanningMutationRepository.testing(
      rpc: (name, {params}) async {
        throw PostgrestException(
          message: 'duplicate_song_in_session_blocked',
          code: 'P0001',
        );
      },
    );

    await expectLater(
      () => repository.syncMutation(
        organizationId: 'org-1',
        record: PlanningMutationRecord(
          aggregateId: 'item-local-1',
          organizationId: 'org-1',
          planId: 'plan-1',
          sessionId: 'session-1',
          songId: 'song-2',
          kind: PlanningMutationKind.sessionItemCreateSong,
          syncStatus: PlanningMutationSyncStatus.pending,
          orderKey: 1,
          updatedAt: DateTime.utc(2026),
        ),
      ),
      throwsA(
        isA<PlanningMutationSyncException>().having(
          (error) => error.code,
          'code',
          PlanningMutationSyncErrorCode.dependencyBlocked,
        ),
      ),
    );
  });

  test('maps song visibility dependency errors to failed dependency', () async {
    final repository = SupabasePlanningMutationRepository.testing(
      rpc: (name, {params}) async {
        throw PostgrestException(
          message: 'song_not_visible_blocked',
          code: 'P0001',
        );
      },
    );

    await expectLater(
      () => repository.syncMutation(
        organizationId: 'org-1',
        record: PlanningMutationRecord(
          aggregateId: 'item-local-1',
          organizationId: 'org-1',
          planId: 'plan-1',
          sessionId: 'session-1',
          songId: 'song-2',
          kind: PlanningMutationKind.sessionItemCreateSong,
          syncStatus: PlanningMutationSyncStatus.pending,
          orderKey: 1,
          updatedAt: DateTime.utc(2026),
        ),
      ),
      throwsA(
        isA<PlanningMutationSyncException>().having(
          (error) => error.code,
          'code',
          PlanningMutationSyncErrorCode.dependencyBlocked,
        ),
      ),
    );
  });

  test(
    'treats an empty table RPC response as an explicit sync failure',
    () async {
      final repository = SupabasePlanningMutationRepository.testing(
        rpc: (name, {params}) async => <Map<String, dynamic>>[],
      );

      await expectLater(
        () => repository.syncMutation(
          organizationId: 'org-1',
          record: PlanningMutationRecord(
            aggregateId: 'plan-1',
            organizationId: 'org-1',
            planId: 'plan-1',
            orderedSiblingIds: const ['session-1'],
            baseVersion: 3,
            kind: PlanningMutationKind.sessionReorder,
            syncStatus: PlanningMutationSyncStatus.pending,
            orderKey: 1,
            updatedAt: DateTime.utc(2026),
          ),
        ),
        throwsA(
          isA<PlanningMutationSyncException>()
              .having(
                (error) => error.code,
                'code',
                PlanningMutationSyncErrorCode.unknown,
              )
              .having(
                (error) => error.message,
                'message',
                'Planning mutation RPC returned an empty result set.',
              ),
        ),
      );
    },
  );

  // spec D5.6 / ADR-035: `403` and a bare `permission denied` message must
  // classify identically to the existing `42501` branch -- PostgREST does
  // not always return a structured PostgreSQL error code.
  test('maps a bare 403 code to authorizationDenied', () async {
    final repository = SupabasePlanningMutationRepository.testing(
      rpc: (name, {params}) async {
        throw const PostgrestException(message: 'Forbidden', code: '403');
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
          PlanningMutationSyncErrorCode.authorizationDenied,
        ),
      ),
    );
  });


  // The `permission denied` match is narrowed to the full PostgreSQL phrase
  // so an unrelated error that merely quotes those two words is not
  // misclassified as permanently unauthorized.
  test(
    'does NOT map an unrelated message merely quoting "permission denied" to '
    'authorizationDenied -- it stays retryable',
    () async {
      final repository = SupabasePlanningMutationRepository.testing(
        rpc: (name, {params}) async {
          throw const PostgrestException(
            message:
                'planning_import_failed: the source said "permission denied" '
                'in its header',
            code: 'P0001',
          );
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
            isNot(PlanningMutationSyncErrorCode.authorizationDenied),
          ),
        ),
      );
    },
  );

  test(
    'maps a "permission denied" message with no structured code to '
    'authorizationDenied',
    () async {
      final repository = SupabasePlanningMutationRepository.testing(
        rpc: (name, {params}) async {
          throw const PostgrestException(
            message: 'permission denied for table plans',
          );
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
            PlanningMutationSyncErrorCode.authorizationDenied,
          ),
        ),
      );
    },
  );

  // Regression guard for spec D5.6 / ADR-035: `401` means the token is
  // missing, malformed, or expired -- re-authentication can make the very
  // same mutation succeed, so it must stay `unknown` (retryable), never
  // `authorizationDenied` (terminal). This protects ordinary token expiry
  // from having its queued work discarded.
  test('does NOT classify a bare 401 as authorizationDenied', () async {
    final repository = SupabasePlanningMutationRepository.testing(
      rpc: (name, {params}) async {
        throw const PostgrestException(message: 'Unauthorized', code: '401');
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
          PlanningMutationSyncErrorCode.unknown,
        ),
      ),
    );
  });
}
