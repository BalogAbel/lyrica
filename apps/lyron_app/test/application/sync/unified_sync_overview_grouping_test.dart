import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/application/planning/planning_sync_state.dart';
import 'package:lyron_app/src/application/song_library/active_catalog_context.dart';
import 'package:lyron_app/src/application/song_library/catalog_connection_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_refresh_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_session_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_snapshot_state.dart';
import 'package:lyron_app/src/application/sync/unified_sync_overview.dart';

const _userId = 'u';
const _orgId = 'o';

CatalogSnapshotState _catalog() {
  return const CatalogSnapshotState(
    context: ActiveCatalogContext(userId: _userId, organizationId: _orgId),
    connectionStatus: CatalogConnectionStatus.online,
    refreshStatus: CatalogRefreshStatus.idle,
    sessionStatus: CatalogSessionStatus.verified,
    hasCachedCatalog: true,
  );
}

PlanningMutationRecord _mut({
  required String aggregateId,
  required PlanningMutationKind kind,
  String? planId,
  String? name,
  String? slug,
  Map<String, Object?>? origin,
  PlanningMutationSyncStatus status = PlanningMutationSyncStatus.pending,
  PlanningMutationSyncErrorCode? errorCode,
}) {
  return PlanningMutationRecord(
    aggregateId: aggregateId,
    organizationId: _orgId,
    kind: kind,
    syncStatus: status,
    orderKey: 0,
    updatedAt: DateTime.utc(2026, 1, 1),
    planId: planId,
    name: name,
    slug: slug,
    originSnapshot: origin,
    errorCode: errorCode,
  );
}

UnifiedSyncOverview _compute(
  List<PlanningMutationRecord> plans, {
  Map<String, String> planTitles = const {},
}) {
  return computeUnifiedSyncOverview(
    UnifiedSyncOverviewInputs(
      catalog: _catalog(),
      songEntries: const [],
      planning: const PlanningSyncState.initial(),
      planningEntries: plans,
      planTitles: planTitles,
    ),
  );
}

void main() {
  group('plan-level grouping', () {
    test('plan create and session create under same plan share one row', () {
      final overview = _compute([
        _mut(
          aggregateId: 'plan-1',
          kind: PlanningMutationKind.planCreate,
          name: 'Sunday',
          slug: 'sunday',
        ),
        _mut(
          aggregateId: 'sess-1',
          kind: PlanningMutationKind.sessionCreate,
          planId: 'plan-1',
          name: 'Morning',
        ),
      ]);

      expect(overview.planRows, hasLength(1));
      final row = overview.planRows.single;
      expect(row.planId, 'plan-1');
      expect(row.title, 'Sunday');
      expect(row.nestedSummaries, containsAll(['plan added', 'session added']));
    });

    test('failed plan create uses name/slug/aggregate fallback chain', () {
      final overview = _compute([
        _mut(
          aggregateId: 'plan-bad',
          kind: PlanningMutationKind.planCreate,
          slug: 'fallback-slug',
          status: PlanningMutationSyncStatus.failedDependency,
          errorCode: PlanningMutationSyncErrorCode.dependencyBlocked,
        ),
      ]);
      expect(overview.planRows.single.title, 'fallback-slug');
      expect(
        overview.planRows.single.reasonCode,
        UnifiedSyncReasonCode.dependencyBlocked,
      );
    });

    test(
      'orphan session item mutation groups under recoverable fallback row',
      () {
        final overview = _compute([
          _mut(
            aggregateId: 'si-1',
            kind: PlanningMutationKind.sessionItemCreateSong,
            planId: 'missing-plan',
          ),
        ]);
        expect(overview.planRows, hasLength(1));
        expect(overview.planRows.single.planId, 'missing-plan');
        expect(overview.planRows.single.nestedSummaries, ['song added']);
      },
    );

    test('planTitles map takes precedence over mutation name', () {
      final overview = _compute(
        [
          _mut(
            aggregateId: 'plan-1',
            kind: PlanningMutationKind.planEdit,
            name: 'Old Name',
          ),
        ],
        planTitles: const {'plan-1': 'Canonical Name'},
      );
      expect(overview.planRows.single.title, 'Canonical Name');
    });

    test('origin snapshot name is used when no mutation name/slug present', () {
      final overview = _compute([
        _mut(
          aggregateId: 'plan-1',
          kind: PlanningMutationKind.planEdit,
          origin: const {'name': 'Origin Name'},
        ),
      ]);
      expect(overview.planRows.single.title, 'Origin Name');
    });

    test('reorder change adds session order changed summary', () {
      final overview = _compute([
        _mut(
          aggregateId: 'plan-1',
          kind: PlanningMutationKind.sessionReorder,
          planId: 'plan-1',
        ),
      ]);
      expect(overview.planRows.single.nestedSummaries, [
        'session order changed',
      ]);
    });

    test('plan rows carry aggregate refs for every grouped mutation', () {
      final overview = _compute([
        _mut(aggregateId: 'plan-1', kind: PlanningMutationKind.planEdit),
        _mut(
          aggregateId: 'session-1',
          kind: PlanningMutationKind.sessionCreate,
          planId: 'plan-1',
        ),
      ]);

      final row = overview.planRows.single;
      expect(
        row.mutationRefs
            .map((r) => '${r.aggregateType}:${r.aggregateId}')
            .toSet(),
        {'plan:plan-1', 'session:session-1'},
      );
    });
  });
}
