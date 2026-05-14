import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_types.dart';
import 'package:lyron_app/src/application/sync/unified_sync_overview.dart';
import 'package:lyron_app/src/presentation/sync/unified_sync_providers.dart';
import 'package:lyron_app/src/presentation/sync/unified_sync_status_popup.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

UnifiedSyncOverview _overview({
  List<UnifiedSyncSongRow> songs = const [],
  List<UnifiedSyncPlanRow> plans = const [],
  UnifiedSyncHeaderStatus status = UnifiedSyncHeaderStatus.synced,
}) {
  return UnifiedSyncOverview(
    headerStatus: status,
    activity: UnifiedSyncActivity.idle,
    connectivity: UnifiedSyncConnectivity.online,
    freshness: UnifiedSyncFreshness.fresh,
    songRows: songs,
    planRows: plans,
    hasUnsyncedWork: songs.isNotEmpty || plans.isNotEmpty,
  );
}

Future<void> _pumpPopup(
  WidgetTester tester,
  UnifiedSyncOverview overview,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [unifiedSyncOverviewProvider.overrideWithValue(overview)],
      child: const MaterialApp(home: Scaffold(body: UnifiedSyncStatusPopup())),
    ),
  );
}

void main() {
  testWidgets('shows empty copy when nothing to sync', (tester) async {
    await _pumpPopup(tester, _overview());
    expect(find.text(AppStrings.unifiedSyncEmptyMessage), findsOneWidget);
  });

  testWidgets('song row + plan conflict row render with Sync now button', (
    tester,
  ) async {
    final overview = _overview(
      status: UnifiedSyncHeaderStatus.conflict,
      songs: const [
        UnifiedSyncSongRow(
          songId: 's1',
          title: 'Hymn',
          entityState: SongSyncStatus.pendingCreate,
          severity: UnifiedSyncRowSeverity.pending,
          reasonCode: UnifiedSyncReasonCode.pendingLocal,
        ),
      ],
      plans: const [
        UnifiedSyncPlanRow(
          planId: 'p1',
          title: 'Service',
          severity: UnifiedSyncRowSeverity.conflict,
          reasonCode: UnifiedSyncReasonCode.conflict,
          nestedSummaries: ['plan edited'],
        ),
      ],
    );
    await _pumpPopup(tester, overview);
    expect(find.text('Hymn'), findsOneWidget);
    expect(find.text('Service'), findsOneWidget);
    expect(find.text(AppStrings.unifiedSyncNowAction), findsOneWidget);
    expect(find.text(AppStrings.unifiedSyncReasonConflict), findsOneWidget);
  });

  testWidgets('authorization_denied row renders specific reason chip', (
    tester,
  ) async {
    final overview = _overview(
      status: UnifiedSyncHeaderStatus.conflict,
      plans: const [
        UnifiedSyncPlanRow(
          planId: 'p1',
          title: 'Closed Plan',
          severity: UnifiedSyncRowSeverity.conflict,
          reasonCode: UnifiedSyncReasonCode.authorizationDenied,
          nestedSummaries: ['plan edited'],
        ),
      ],
    );
    await _pumpPopup(tester, overview);
    expect(
      find.text(AppStrings.unifiedSyncReasonAuthorizationDenied),
      findsOneWidget,
    );
  });

  testWidgets('dependency_blocked row renders specific reason chip', (
    tester,
  ) async {
    final overview = _overview(
      status: UnifiedSyncHeaderStatus.conflict,
      plans: const [
        UnifiedSyncPlanRow(
          planId: 'p1',
          title: 'Blocked',
          severity: UnifiedSyncRowSeverity.conflict,
          reasonCode: UnifiedSyncReasonCode.dependencyBlocked,
          nestedSummaries: ['session removed'],
        ),
      ],
    );
    await _pumpPopup(tester, overview);
    expect(
      find.text(AppStrings.unifiedSyncReasonDependencyBlocked),
      findsOneWidget,
    );
  });

  testWidgets('remote_missing row renders specific reason chip', (
    tester,
  ) async {
    final overview = _overview(
      status: UnifiedSyncHeaderStatus.conflict,
      plans: const [
        UnifiedSyncPlanRow(
          planId: 'p1',
          title: 'Gone',
          severity: UnifiedSyncRowSeverity.conflict,
          reasonCode: UnifiedSyncReasonCode.remoteMissing,
          nestedSummaries: ['plan edited'],
        ),
      ],
    );
    await _pumpPopup(tester, overview);
    expect(
      find.text(AppStrings.unifiedSyncReasonRemoteMissing),
      findsOneWidget,
    );
  });

  testWidgets('sync_failed song row renders retryable reason chip', (
    tester,
  ) async {
    final overview = _overview(
      status: UnifiedSyncHeaderStatus.unsynced,
      songs: const [
        UnifiedSyncSongRow(
          songId: 's1',
          title: 'Retry',
          entityState: SongSyncStatus.pendingUpdate,
          severity: UnifiedSyncRowSeverity.retryableFailure,
          reasonCode: UnifiedSyncReasonCode.syncFailed,
        ),
      ],
    );
    await _pumpPopup(tester, overview);
    expect(find.text(AppStrings.unifiedSyncReasonSyncFailed), findsOneWidget);
  });
}
