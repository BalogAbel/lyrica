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
}) {
  return UnifiedSyncOverview(
    headerStatus: status,
    activity: UnifiedSyncActivity.idle,
    connectivity: UnifiedSyncConnectivity.online,
    freshness: UnifiedSyncFreshness.fresh,
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
  testWidgets('renders Synced label for green status', (tester) async {
    await _pump(tester, _overview(UnifiedSyncHeaderStatus.synced));
    expect(find.text(AppStrings.unifiedSyncSyncedLabel), findsOneWidget);
  });

  testWidgets('renders Unsynced label for yellow status', (tester) async {
    await _pump(
      tester,
      _overview(UnifiedSyncHeaderStatus.unsynced, hasUnsyncedWork: true),
    );
    expect(find.text(AppStrings.unifiedSyncUnsyncedLabel), findsOneWidget);
  });

  testWidgets('renders Conflict label for red status', (tester) async {
    await _pump(
      tester,
      _overview(UnifiedSyncHeaderStatus.conflict, hasUnsyncedWork: true),
    );
    expect(find.text(AppStrings.unifiedSyncConflictLabel), findsOneWidget);
  });
}
