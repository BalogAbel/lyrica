import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/application/planning/planning_sync_state.dart';
import 'package:lyron_app/src/application/song_library/active_catalog_context.dart';
import 'package:lyron_app/src/application/song_library/catalog_connection_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_refresh_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_session_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_snapshot_state.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_types.dart';
import 'package:lyron_app/src/application/sync/unified_sync_overview.dart';

const _userId = 'user-1';
const _orgId = 'org-1';

CatalogSnapshotState _catalog({
  CatalogConnectionStatus connection = CatalogConnectionStatus.online,
  CatalogRefreshStatus refresh = CatalogRefreshStatus.idle,
  bool hasCached = true,
}) {
  return CatalogSnapshotState(
    context: const ActiveCatalogContext(
      userId: _userId,
      organizationId: _orgId,
    ),
    connectionStatus: connection,
    refreshStatus: refresh,
    sessionStatus: CatalogSessionStatus.verified,
    hasCachedCatalog: hasCached,
  );
}

SongMutationRecord _song({
  required String id,
  required String title,
  SongSyncStatus status = SongSyncStatus.pendingCreate,
  SongMutationSyncErrorCode? errorCode,
}) {
  return SongMutationRecord(
    id: id,
    organizationId: _orgId,
    slug: id,
    title: title,
    chordproSource: '',
    version: 1,
    baseVersion: null,
    syncStatus: status,
    errorCode: errorCode,
  );
}

PlanningMutationRecord _plan({
  required String aggregateId,
  PlanningMutationKind kind = PlanningMutationKind.planCreate,
  PlanningMutationSyncStatus status = PlanningMutationSyncStatus.pending,
  PlanningMutationSyncErrorCode? errorCode,
  String? name,
  String? planId,
}) {
  return PlanningMutationRecord(
    aggregateId: aggregateId,
    organizationId: _orgId,
    kind: kind,
    syncStatus: status,
    orderKey: 0,
    updatedAt: DateTime.utc(2026, 1, 1),
    name: name,
    planId: planId,
    errorCode: errorCode,
  );
}

UnifiedSyncOverview _compute({
  CatalogSnapshotState? catalog,
  List<SongMutationRecord> songs = const [],
  PlanningSyncState? planning,
  List<PlanningMutationRecord> plans = const [],
  Map<String, String> planTitles = const {},
}) {
  return computeUnifiedSyncOverview(
    UnifiedSyncOverviewInputs(
      catalog: catalog ?? _catalog(),
      songEntries: songs,
      planning: planning ?? const PlanningSyncState.initial(),
      planningEntries: plans,
      planTitles: planTitles,
    ),
  );
}

void main() {
  group('computeUnifiedSyncOverview', () {
    test('no pending work yields green synced', () {
      final overview = _compute();
      expect(overview.headerStatus, UnifiedSyncHeaderStatus.synced);
      expect(overview.hasUnsyncedWork, isFalse);
      expect(overview.songRows, isEmpty);
      expect(overview.planRows, isEmpty);
      expect(overview.freshness, UnifiedSyncFreshness.fresh);
      expect(overview.connectivity, UnifiedSyncConnectivity.online);
    });

    test('one pending song create yields yellow unsynced', () {
      final overview = _compute(
        songs: [_song(id: 's1', title: 'Hymn')],
      );
      expect(overview.headerStatus, UnifiedSyncHeaderStatus.unsynced);
      expect(overview.hasUnsyncedWork, isTrue);
      expect(overview.songRows.single.severity, UnifiedSyncRowSeverity.pending);
      expect(
        overview.songRows.single.reasonCode,
        UnifiedSyncReasonCode.pendingLocal,
      );
    });

    test('planning conflict yields red conflict', () {
      final overview = _compute(
        plans: [
          _plan(
            aggregateId: 'p1',
            status: PlanningMutationSyncStatus.conflict,
            errorCode: PlanningMutationSyncErrorCode.conflict,
            name: 'Sunday Service',
          ),
        ],
      );
      expect(overview.headerStatus, UnifiedSyncHeaderStatus.conflict);
      expect(
        overview.planRows.single.reasonCode,
        UnifiedSyncReasonCode.conflict,
      );
    });

    test('a plan row\'s mutation refs carry the status each entry had when '
        'the overview was computed (review gate 3 F1)', () {
      final overview = _compute(
        plans: [
          _plan(
            aggregateId: 'session-item-1',
            kind: PlanningMutationKind.sessionItemCreateSong,
            status: PlanningMutationSyncStatus.conflict,
            errorCode: PlanningMutationSyncErrorCode.conflict,
            planId: 'p1',
          ),
          _plan(
            aggregateId: 'p1',
            kind: PlanningMutationKind.planDelete,
            status: PlanningMutationSyncStatus.pending,
            name: 'Sunday Service',
          ),
        ],
      );

      final refs = overview.planRows.single.mutationRefs;
      expect(refs.map((r) => (r.aggregateId, r.syncStatus)), [
        ('session-item-1', PlanningMutationSyncStatus.conflict),
        ('p1', PlanningMutationSyncStatus.pending),
      ]);
    });

    test('a conflicted plan removal is titled from its snapshot and explains '
        'the conflict (spec D9)', () {
      final overview = _compute(
        plans: [
          PlanningMutationRecord(
            aggregateId: 'session-9',
            organizationId: 'org-1',
            planId: 'plan-1',
            kind: PlanningMutationKind.sessionRename,
            syncStatus: PlanningMutationSyncStatus.failedDependency,
            orderKey: 1,
            updatedAt: DateTime.utc(2026),
            originSnapshot: const {'name': 'A Session Name'},
          ),
          PlanningMutationRecord(
            aggregateId: 'plan-1',
            organizationId: 'org-1',
            kind: PlanningMutationKind.planDelete,
            syncStatus: PlanningMutationSyncStatus.conflict,
            orderKey: 2,
            updatedAt: DateTime.utc(2026),
            originSnapshot: const {'name': 'Sunday Service'},
          ),
        ],
      );

      final row = overview.planRows.single;
      expect(row.title, 'Sunday Service');
      expect(
        row.nestedSummaries.last,
        'plan removal conflicts: the plan changed after you deleted it — '
        'retry deletes it as it is now, discard keeps it',
      );
    });

    test('a conflicted session removal explains the conflict, a pending one '
        'just says removed (review gate 3 F3)', () {
      String summaryFor(PlanningMutationSyncStatus status) {
        final overview = _compute(
          planTitles: const {'plan-1': 'Sunday Service'},
          plans: [
            PlanningMutationRecord(
              aggregateId: 'session-1',
              organizationId: 'org-1',
              planId: 'plan-1',
              kind: PlanningMutationKind.sessionDelete,
              syncStatus: status,
              orderKey: 1,
              updatedAt: DateTime.utc(2026),
            ),
          ],
        );
        return overview.planRows.single.nestedSummaries.single;
      }

      expect(
        summaryFor(PlanningMutationSyncStatus.conflict),
        'session removal conflicts: the session changed after you deleted '
        'it — retry deletes it as it is now, discard keeps it',
      );
      expect(summaryFor(PlanningMutationSyncStatus.pending), 'session removed');
    });

    test('red wins over yellow when mixed', () {
      final overview = _compute(
        songs: [_song(id: 's1', title: 'Hymn')],
        plans: [
          _plan(
            aggregateId: 'p1',
            status: PlanningMutationSyncStatus.failedAuthorization,
            errorCode: PlanningMutationSyncErrorCode.authorizationDenied,
            name: 'Service',
          ),
        ],
      );
      expect(overview.headerStatus, UnifiedSyncHeaderStatus.conflict);
      expect(overview.hasUnsyncedWork, isTrue);
    });

    test(
      'offline cached with no pending stays green and reports offline freshness',
      () {
        final overview = _compute(
          catalog: _catalog(connection: CatalogConnectionStatus.offlineCached),
        );
        expect(overview.headerStatus, UnifiedSyncHeaderStatus.synced);
        expect(overview.connectivity, UnifiedSyncConnectivity.offline);
        expect(overview.freshness, UnifiedSyncFreshness.offlineCached);
      },
    );

    test('catalog refreshing flags activity', () {
      final overview = _compute(
        catalog: _catalog(refresh: CatalogRefreshStatus.refreshing),
      );
      expect(overview.activity, UnifiedSyncActivity.syncing);
      expect(overview.headerStatus, UnifiedSyncHeaderStatus.synced);
    });

    test('refresh failed while online flags stale freshness without red', () {
      final overview = _compute(
        catalog: _catalog(refresh: CatalogRefreshStatus.failed),
      );
      expect(overview.freshness, UnifiedSyncFreshness.stale);
      expect(overview.headerStatus, UnifiedSyncHeaderStatus.synced);
    });

    test('planning refresh failed while online flags stale freshness', () {
      final overview = _compute(
        planning: const PlanningSyncState.initial().copyWith(
          refreshStatus: PlanningRefreshStatus.failed,
        ),
      );
      expect(overview.freshness, UnifiedSyncFreshness.stale);
      expect(overview.headerStatus, UnifiedSyncHeaderStatus.synced);
    });

    test('authorization_denied planning row yields red conflict severity', () {
      final overview = _compute(
        plans: [
          _plan(
            aggregateId: 'p1',
            kind: PlanningMutationKind.planEdit,
            status: PlanningMutationSyncStatus.failedAuthorization,
            errorCode: PlanningMutationSyncErrorCode.authorizationDenied,
            name: 'X',
          ),
        ],
      );
      expect(
        overview.planRows.single.reasonCode,
        UnifiedSyncReasonCode.authorizationDenied,
      );
      expect(
        overview.planRows.single.severity,
        UnifiedSyncRowSeverity.conflict,
      );
    });

    // spec D5.6 / ADR-035: a permanently unauthorized song row (surfaced by
    // SongMutationSyncController writing `SongSyncStatus.conflict` for an
    // authorizationDenied failure, see song_mutation_sync_controller.dart)
    // must be distinguishable from an ordinary retryable failure, not just
    // shown as a generic conflict -- reasonCode carries that distinction,
    // separately from severity (which both share `conflict`, matching
    // planning's equivalent row above).
    test('authorization_denied song row yields red conflict severity', () {
      final overview = _compute(
        songs: [
          _song(
            id: 's1',
            title: 'Revoked',
            status: SongSyncStatus.conflict,
            errorCode: SongMutationSyncErrorCode.authorizationDenied,
          ),
        ],
      );
      expect(
        overview.songRows.single.reasonCode,
        UnifiedSyncReasonCode.authorizationDenied,
      );
      expect(
        overview.songRows.single.severity,
        UnifiedSyncRowSeverity.conflict,
      );
      // Distinguishable from a merely retryable failure: an ordinary
      // syncFailed/unknown row never reaches conflict severity.
      expect(
        overview.songRows.single.severity,
        isNot(UnifiedSyncRowSeverity.retryableFailure),
      );
    });

    test('synced song entries are filtered from rows', () {
      final overview = _compute(
        songs: [
          _song(id: 's1', title: 'Synced song', status: SongSyncStatus.synced),
        ],
      );
      expect(overview.songRows, isEmpty);
      expect(overview.headerStatus, UnifiedSyncHeaderStatus.synced);
    });

    test(
      'song conflict with dependency_blocked code maps to conflict severity',
      () {
        final overview = _compute(
          songs: [
            _song(
              id: 's1',
              title: 'Blocked',
              status: SongSyncStatus.conflict,
              errorCode: SongMutationSyncErrorCode.dependencyBlocked,
            ),
          ],
        );
        expect(
          overview.songRows.single.reasonCode,
          UnifiedSyncReasonCode.dependencyBlocked,
        );
        expect(overview.headerStatus, UnifiedSyncHeaderStatus.conflict);
      },
    );
  });
}
