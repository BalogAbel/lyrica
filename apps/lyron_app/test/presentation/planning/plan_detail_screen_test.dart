import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/song_library/catalog_connection_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_refresh_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_session_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_snapshot_state.dart';
import 'package:lyron_app/src/application/song_library/song_reader_result.dart';
import 'package:lyron_app/src/domain/planning/plan_detail.dart';
import 'package:lyron_app/src/domain/planning/plan_summary.dart';
import 'package:lyron_app/src/domain/planning/session_item_summary.dart';
import 'package:lyron_app/src/domain/planning/session_summary.dart';
import 'package:lyron_app/src/domain/song/parsed_song.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/presentation/planning/plan_detail_screen.dart';
import 'package:lyron_app/src/presentation/planning/planning_providers.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_screen.dart';
import 'package:lyron_app/src/router/app_routes.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildApp({Object? planDetailValue}) {
    GoRouter.optionURLReflectsImperativeAPIs = true;

    final router = GoRouter(
      initialLocation: AppRoutes.planDetail.path.replaceFirst(
        ':planSlug',
        'team-rehearsal',
      ),
      routes: [
        GoRoute(
          path: AppRoutes.planDetail.path,
          builder: (context, state) => const PlanDetailScreen(planId: 'plan-1'),
        ),
        GoRoute(
          path: AppRoutes.planSessionSongReader.path,
          builder: (context, state) => SongReaderScreen(
            songId: 'song-1',
            planId: 'plan-1',
            sessionId: 'session-1',
            sessionItemId: 'item-1',
            warmPlanDetail: state.extra is PlanDetail
                ? state.extra! as PlanDetail
                : null,
          ),
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
            slug: 'team-rehearsal',
            name: 'Team Rehearsal',
            description: 'Multi-session rehearsal fixture',
            scheduledFor: null,
            updatedAt: DateTime(2026, 3, 31, 9),
          ),
          sessions: const [
            SessionSummary(
              id: 'session-1',
              slug: 'warm-up',
              name: 'Warm-Up',
              position: 10,
              items: [
                SessionItemSummary(
                  id: 'item-1',
                  position: 10,
                  song: SongSummary(
                    id: 'song-1',
                    slug: 'zulu-song',
                    title: 'Zulu Song',
                  ),
                ),
                SessionItemSummary(
                  id: 'item-2',
                  position: 20,
                  song: SongSummary(
                    id: 'song-2',
                    slug: 'alpha-song',
                    title: 'Alpha Song',
                  ),
                ),
              ],
            ),
            SessionSummary(
              id: 'session-2',
              slug: 'run-through',
              name: 'Run-Through',
              position: 20,
              items: [
                SessionItemSummary(
                  id: 'item-3',
                  position: 10,
                  song: SongSummary(
                    id: 'song-3',
                    slug: 'egy-ut',
                    title: 'Egy út',
                  ),
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

  testWidgets(
    'tapping a session item opens the scoped reader without replacing plan detail',
    (tester) async {
      GoRouter.optionURLReflectsImperativeAPIs = true;

      final router = GoRouter(
        initialLocation: AppRoutes.planDetail.path.replaceFirst(
          ':planSlug',
          'team-rehearsal',
        ),
        routes: [
          GoRoute(
            path: AppRoutes.planDetail.path,
            builder: (context, state) =>
                const PlanDetailScreen(planId: 'plan-1'),
          ),
          GoRoute(
            path: AppRoutes.planSessionSongReader.path,
            builder: (context, state) => SongReaderScreen(
              songId: 'song-1',
              planId: 'plan-1',
              sessionId: 'session-1',
              sessionItemId: 'item-1',
              warmPlanDetail: state.extra is PlanDetail
                  ? state.extra! as PlanDetail
                  : null,
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            planningPlanDetailProvider('plan-1').overrideWith((ref) async {
              return PlanDetail(
                plan: PlanSummary(
                  id: 'plan-1',
                  slug: 'team-rehearsal',
                  name: 'Team Rehearsal',
                  description: 'Multi-session rehearsal fixture',
                  scheduledFor: null,
                  updatedAt: DateTime(2026, 3, 31, 9),
                ),
                sessions: const [
                  SessionSummary(
                    id: 'session-1',
                    slug: 'warm-up',
                    name: 'Warm-Up',
                    position: 10,
                    items: [
                      SessionItemSummary(
                        id: 'item-1',
                        position: 10,
                        song: SongSummary(
                          id: 'song-1',
                          slug: 'a-forrasnal',
                          title: 'A forrasnal',
                        ),
                      ),
                    ],
                  ),
                ],
              );
            }),
            catalogSnapshotStateProvider.overrideWithValue(
              const CatalogSnapshotState(
                context: null,
                connectionStatus: CatalogConnectionStatus.online,
                refreshStatus: CatalogRefreshStatus.idle,
                sessionStatus: CatalogSessionStatus.verified,
                hasCachedCatalog: true,
              ),
            ),
            songLibraryReaderProvider.overrideWithProvider(
              (songId) => FutureProvider.autoDispose(
                (ref) async => SongReaderResult(
                  song: ParsedSong(
                    title: 'A forrasnal',
                    sourceKey: 'C',
                    sections: const [],
                    diagnostics: const [],
                  ),
                ),
              ),
            ),
            songLibrarySongByIdProvider('song-1').overrideWith(
              (ref) async => const SongSummary(
                id: 'song-1',
                slug: 'a-forrasnal',
                title: 'A forrasnal',
              ),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('plan-session-item-item-1')));
      await tester.pumpAndSettle();

      expect(find.text('Song reader'), findsOneWidget);
      expect(find.byTooltip(AppStrings.songReaderBackAction), findsOneWidget);

      await tester.tap(find.byTooltip(AppStrings.songReaderBackAction));
      await tester.pumpAndSettle();

      expect(find.text('Team Rehearsal'), findsOneWidget);
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        '/plans/team-rehearsal',
      );
    },
  );

  testWidgets(
    'session items stay disabled until a canonical song slug is available',
    (tester) async {
      final router = GoRouter(
        initialLocation: AppRoutes.planDetail.path.replaceFirst(
          ':planSlug',
          'team-rehearsal',
        ),
        routes: [
          GoRoute(
            path: AppRoutes.planDetail.path,
            builder: (context, state) =>
                const PlanDetailScreen(planId: 'plan-1'),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            planningPlanDetailProvider('plan-1').overrideWith((ref) async {
              return PlanDetail(
                plan: PlanSummary(
                  id: 'plan-1',
                  slug: 'team-rehearsal',
                  name: 'Team Rehearsal',
                  description: 'Multi-session rehearsal fixture',
                  scheduledFor: null,
                  updatedAt: DateTime(2026, 3, 31, 9),
                ),
                sessions: const [
                  SessionSummary(
                    id: 'session-1',
                    slug: 'warm-up',
                    name: 'Warm-Up',
                    position: 10,
                    items: [
                      SessionItemSummary(
                        id: 'item-1',
                        position: 10,
                        song: SongSummary(id: 'song-1', title: 'A forrasnal'),
                      ),
                    ],
                  ),
                ],
              );
            }),
            catalogSnapshotStateProvider.overrideWithValue(
              const CatalogSnapshotState(
                context: null,
                connectionStatus: CatalogConnectionStatus.online,
                refreshStatus: CatalogRefreshStatus.idle,
                sessionStatus: CatalogSessionStatus.verified,
                hasCachedCatalog: true,
              ),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('plan-session-item-item-1')));
      await tester.pumpAndSettle();

      expect(find.text('Team Rehearsal'), findsOneWidget);
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        '/plans/team-rehearsal',
      );
    },
  );
}
