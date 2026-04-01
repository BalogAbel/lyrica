import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lyron_app/src/domain/planning/plan_summary.dart';
import 'package:lyron_app/src/presentation/planning/plan_list_screen.dart';
import 'package:lyron_app/src/presentation/planning/planning_providers.dart';
import 'package:lyron_app/src/router/app_routes.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildApp({Object? listPlansValue = const <PlanSummary>[]}) {
    final router = GoRouter(
      initialLocation: AppRoutes.planList.path,
      routes: [
        GoRoute(
          path: AppRoutes.planList.path,
          builder: (context, state) => const PlanListScreen(),
        ),
        GoRoute(
          path: AppRoutes.planDetail.path,
          builder: (context, state) {
            final planId = state.pathParameters['planId']!;
            return Material(child: Text('plan-detail:$planId'));
          },
        ),
      ],
    );

    return ProviderScope(
      overrides: [
        planningPlanListProvider.overrideWith((ref) {
          if (listPlansValue is Future<List<PlanSummary>>) {
            return listPlansValue;
          }

          if (listPlansValue is Object &&
              listPlansValue is! List<PlanSummary>) {
            return Future<List<PlanSummary>>.error(listPlansValue);
          }

          return Future.value(listPlansValue as List<PlanSummary>);
        }),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  testWidgets('renders visible plans in the order provided by the list', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildApp(
        listPlansValue: [
          PlanSummary(
            id: 'plan-2',
            name: 'Zulu Rehearsal',
            description: 'Multi-session rehearsal fixture',
            scheduledFor: null,
            updatedAt: DateTime(2026, 3, 31, 12),
          ),
          PlanSummary(
            id: 'plan-1',
            name: 'Alpha Morning',
            description: 'Single-session Sunday fixture',
            scheduledFor: DateTime(2026, 4, 5, 8, 30),
            updatedAt: DateTime(2026, 3, 31, 8),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Alpha Morning'), findsOneWidget);
    expect(find.text('Zulu Rehearsal'), findsOneWidget);
    expect(find.byType(ListTile), findsNWidgets(2));
    expect(
      tester.getTopLeft(find.text('Zulu Rehearsal')).dy,
      lessThan(tester.getTopLeft(find.text('Alpha Morning')).dy),
    );
  });

  testWidgets('navigates to the plan detail route when a plan is tapped', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildApp(
        listPlansValue: [
          PlanSummary(
            id: 'plan-1',
            name: 'Sunday Morning',
            description: 'Single-session Sunday fixture',
            scheduledFor: DateTime(2026, 4, 5, 8, 30),
            updatedAt: DateTime(2026, 3, 31, 8),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sunday Morning'));
    await tester.pumpAndSettle();

    expect(find.text('plan-detail:plan-1'), findsOneWidget);
  });

  testWidgets('shows a loading state while plans are loading', (tester) async {
    final completer = Completer<List<PlanSummary>>();

    await tester.pumpWidget(buildApp(listPlansValue: completer.future));
    await tester.pump();

    expect(find.text(AppStrings.planListLoadingMessage), findsOneWidget);
  });

  testWidgets('shows an explicit failure surface when plans cannot load', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp(listPlansValue: StateError('boom')));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.planListLoadFailureMessage), findsOneWidget);
    expect(find.text(AppStrings.retryAction), findsOneWidget);
  });
}
