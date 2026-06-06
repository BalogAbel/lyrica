import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/sync/unified_sync_overview.dart';
import 'package:lyron_app/src/presentation/sync/unified_sync_header_control.dart';
import 'package:lyron_app/src/presentation/sync/unified_sync_providers.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

UnifiedSyncOverview _overview(
  UnifiedSyncHeaderStatus status, {
  bool hasUnsyncedWork = false,
  UnifiedSyncFreshness freshness = UnifiedSyncFreshness.fresh,
  UnifiedSyncActivity activity = UnifiedSyncActivity.idle,
}) {
  return UnifiedSyncOverview(
    headerStatus: status,
    activity: activity,
    connectivity: UnifiedSyncConnectivity.online,
    freshness: freshness,
    songRows: const [],
    planRows: const [],
    hasUnsyncedWork: hasUnsyncedWork,
  );
}

Future<void> _pump(WidgetTester tester, UnifiedSyncOverview overview) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [unifiedSyncOverviewProvider.overrideWithValue(overview)],
      child: const MaterialApp(
        home: Scaffold(
          appBar: null,
          body: SafeArea(child: UnifiedSyncHeaderControl()),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('exposes Synced label via tooltip for green status', (
    tester,
  ) async {
    await _pump(tester, _overview(UnifiedSyncHeaderStatus.synced));
    expect(find.byTooltip(AppStrings.unifiedSyncSyncedLabel), findsOneWidget);
  });

  testWidgets('exposes Unsynced label via tooltip for yellow status', (
    tester,
  ) async {
    await _pump(
      tester,
      _overview(UnifiedSyncHeaderStatus.unsynced, hasUnsyncedWork: true),
    );
    expect(find.byTooltip(AppStrings.unifiedSyncUnsyncedLabel), findsOneWidget);
  });

  testWidgets('exposes Conflict label via tooltip for red status', (
    tester,
  ) async {
    await _pump(
      tester,
      _overview(UnifiedSyncHeaderStatus.conflict, hasUnsyncedWork: true),
    );
    expect(find.byTooltip(AppStrings.unifiedSyncConflictLabel), findsOneWidget);
  });

  testWidgets('appends secondary freshness detail to the tooltip', (
    tester,
  ) async {
    await _pump(
      tester,
      _overview(
        UnifiedSyncHeaderStatus.synced,
        freshness: UnifiedSyncFreshness.stale,
      ),
    );
    expect(
      find.byTooltip(
        '${AppStrings.unifiedSyncSyncedLabel} · '
        '${AppStrings.unifiedSyncFreshnessStale}',
      ),
      findsOneWidget,
    );
  });

  testWidgets('joins multiple secondary parts in the tooltip', (tester) async {
    await _pump(
      tester,
      _overview(
        UnifiedSyncHeaderStatus.unsynced,
        hasUnsyncedWork: true,
        freshness: UnifiedSyncFreshness.stale,
        activity: UnifiedSyncActivity.syncing,
      ),
    );
    expect(
      find.byTooltip(
        '${AppStrings.unifiedSyncUnsyncedLabel} · '
        '${AppStrings.unifiedSyncFreshnessStale} · '
        '${AppStrings.unifiedSyncActivitySyncing}',
      ),
      findsOneWidget,
    );
  });
}
