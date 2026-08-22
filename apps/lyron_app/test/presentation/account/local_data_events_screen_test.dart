import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth_providers.dart';
import 'package:lyron_app/src/offline/local_data_events/drift_local_data_events_store.dart';
import 'package:lyron_app/src/presentation/account/local_data_events_screen.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

void main() {
  final sampleRecords = [
    LocalDataEventRecord(
      id: 2,
      occurredAt: DateTime.utc(2026, 8, 20, 10, 30),
      kind: 'purge',
      target: 'songCatalog',
      reason: 'userSignOut',
      userId: 'u1',
      rowsAffected: null,
    ),
    LocalDataEventRecord(
      id: 1,
      occurredAt: DateTime.utc(2026, 8, 19, 9, 0),
      kind: 'eviction',
      target: 'cachedCatalogSources',
      reason: null,
      userId: null,
      rowsAffected: null,
    ),
  ];

  testWidgets('renders a list of provided records', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localDataEventsRecordsProvider.overrideWith(
            (ref) async => sampleRecords,
          ),
        ],
        child: const MaterialApp(home: LocalDataEventsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('songCatalog'), findsOneWidget);
    expect(find.text('cachedCatalogSources'), findsOneWidget);
  });

  testWidgets('shows empty state when there are no records', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localDataEventsRecordsProvider.overrideWith((ref) async => []),
        ],
        child: const MaterialApp(home: LocalDataEventsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.localDataEventsEmptyMessage), findsOneWidget);
  });

  testWidgets('shows a retryable error state on load failure', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localDataEventsRecordsProvider.overrideWith(
            (ref) async => throw StateError('simulated read failure'),
          ),
        ],
        child: const MaterialApp(home: LocalDataEventsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(AppStrings.localDataEventsLoadErrorMessage),
      findsOneWidget,
    );
    expect(find.text(AppStrings.retryAction), findsOneWidget);
  });

  testWidgets('does not offer any destructive or edit action', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localDataEventsRecordsProvider.overrideWith(
            (ref) async => sampleRecords,
          ),
        ],
        child: const MaterialApp(home: LocalDataEventsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.delete), findsNothing);
    expect(find.byIcon(Icons.edit), findsNothing);
    expect(find.byType(Dismissible), findsNothing);
  });
}
