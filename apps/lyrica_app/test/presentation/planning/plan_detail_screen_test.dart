import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lyrica_app/src/domain/planning/plan_detail.dart';
import 'package:lyrica_app/src/domain/planning/plan_summary.dart';
import 'package:lyrica_app/src/domain/planning/session_item_summary.dart';
import 'package:lyrica_app/src/domain/planning/session_summary.dart';
import 'package:lyrica_app/src/domain/song/song_summary.dart';
import 'package:lyrica_app/src/presentation/planning/plan_detail_screen.dart';
import 'package:lyrica_app/src/presentation/planning/planning_providers.dart';
import 'package:lyrica_app/src/router/app_routes.dart';
import 'package:lyrica_app/src/shared/app_strings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildApp({Object? planDetailValue}) {
    final router = GoRouter(
      initialLocation: AppRoutes.planDetail.path.replaceFirst(
        ':planId',
        'plan-1',
      ),
      routes: [
        GoRoute(
          path: AppRoutes.planDetail.path,
          builder: (context, state) {
            final planId = state.pathParameters['planId']!;
            return PlanDetailScreen(planId: planId);
          },
        ),
      ],
    );

    return ProviderScope(
      overrides: [
        planningPlanDetailProvider('plan-1').overrideWith((ref) {
          if (planDetailValue is Future<PlanDetail>) {
            return planDetailValue;
          }

          if (planDetailValue is Object && planDetailValue is! PlanDetail) {
            return Future<PlanDetail>.error(planDetailValue);
          }

          return Future.value(planDetailValue as PlanDetail);
        }),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  testWidgets('renders sessions and song-backed items in order', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildApp(
        planDetailValue: PlanDetail(
          plan: PlanSummary(
            id: 'plan-1',
            name: 'Team Rehearsal',
            description: 'Multi-session rehearsal fixture',
            scheduledFor: null,
            updatedAt: DateTime(2026, 3, 31, 9),
          ),
          sessions: const [
            SessionSummary(
              id: 'session-1',
              name: 'Warm-Up',
              position: 10,
              items: [
                SessionItemSummary(
                  id: 'item-1',
                  position: 10,
                  song: SongSummary(id: 'song-1', title: 'Zulu Song'),
                ),
                SessionItemSummary(
                  id: 'item-2',
                  position: 20,
                  song: SongSummary(id: 'song-2', title: 'Alpha Song'),
                ),
              ],
            ),
            SessionSummary(
              id: 'session-2',
              name: 'Run-Through',
              position: 20,
              items: [
                SessionItemSummary(
                  id: 'item-3',
                  position: 10,
                  song: SongSummary(id: 'song-3', title: 'Egy út'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Team Rehearsal'), findsOneWidget);
    expect(find.text('Warm-Up'), findsOneWidget);
    expect(find.text('Run-Through'), findsOneWidget);
    expect(find.textContaining('Zulu Song'), findsOneWidget);
    expect(find.textContaining('Alpha Song'), findsOneWidget);
    expect(find.textContaining('Egy út'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Warm-Up')).dy,
      lessThan(tester.getTopLeft(find.text('Run-Through')).dy),
    );
    expect(
      tester.getTopLeft(find.textContaining('Zulu Song')).dy,
      lessThan(tester.getTopLeft(find.textContaining('Alpha Song')).dy),
    );
  });

  testWidgets('shows an explicit loading state while the plan loads', (
    tester,
  ) async {
    final completer = Completer<PlanDetail>();

    await tester.pumpWidget(buildApp(planDetailValue: completer.future));
    await tester.pump();

    expect(find.text(AppStrings.planDetailLoadingMessage), findsOneWidget);
  });

  testWidgets('shows an explicit failure surface when the plan cannot load', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp(planDetailValue: StateError('boom')));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.planDetailLoadFailureMessage), findsOneWidget);
    expect(find.text(AppStrings.retryAction), findsOneWidget);
  });
}
