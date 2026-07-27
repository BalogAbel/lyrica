import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lyron_app/src/application/auth/capability_resolver.dart';
import 'package:lyron_app/src/application/planning/planning_data_revision.dart';
import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/application/planning/planning_write_service.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/song_library/active_catalog_context.dart';
import 'package:lyron_app/src/application/song_library/catalog_connection_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_refresh_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_session_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_snapshot_state.dart';
import 'package:lyron_app/src/application/song_library/song_reader_result.dart';
import 'package:lyron_app/src/application/sync/unified_sync_overview.dart';
import 'package:lyron_app/src/domain/core/capability.dart';
import 'package:lyron_app/src/domain/planning/plan_detail.dart';
import 'package:lyron_app/src/domain/planning/plan_summary.dart';
import 'package:lyron_app/src/domain/planning/planning_repository.dart';
import 'package:lyron_app/src/domain/planning/session_item_summary.dart';
import 'package:lyron_app/src/domain/planning/session_summary.dart';
import 'package:lyron_app/src/domain/song/parsed_song.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/presentation/planning/plan_detail_screen.dart';
import 'package:lyron_app/src/presentation/planning/planning_providers.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_screen.dart';
import 'package:lyron_app/src/presentation/sync/unified_sync_providers.dart';
import 'package:lyron_app/src/router/app_routes.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildApp({
    Object? planDetailValue,
    PlanningWriteService? writeService,
    Future<List<PlanningMutationRecord>> Function()? loadMutationEntries,
    List<SongSummary>? visibleSongs,
    FutureOr<List<SongSummary>> Function(ActiveCatalogContext? context)?
    songsForContext,
    StateProvider<ActivePlanningReadContext?>? mutablePlanningContextProvider,
    CatalogSnapshotState? catalogSnapshotState,
    CapabilityResolver? capabilityResolver,
  }) {
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
          ref.watch(planningDataRevisionProvider);
          if (planDetailValue is Future<PlanDetail>) {
            return planDetailValue;
          }

          if (planDetailValue is Object && planDetailValue is! PlanDetail) {
            return Future<PlanDetail>.error(planDetailValue);
          }

          return Future.value(planDetailValue as PlanDetail);
        }),
        planningWriteServiceProvider.overrideWithValue(
          writeService ?? _FakePlanningWriteService(),
        ),
        planningMutationEntriesProvider.overrideWith((ref) {
          if (loadMutationEntries != null) {
            return loadMutationEntries();
          }
          return Future.value(const <PlanningMutationRecord>[]);
        }),
        planningMutationStoreProvider.overrideWithValue(
          _PlanDetailTestPlanningMutationStore(),
        ),
        songLibraryListProvider.overrideWith((ref) {
          if (songsForContext != null) {
            final songs = songsForContext(
              ref.watch(activeCatalogContextProvider),
            );
            if (songs is Future<List<SongSummary>>) {
              return songs;
            }
            return Future.value(songs);
          }

          return Future.value(visibleSongs ?? const <SongSummary>[]);
        }),
        catalogSnapshotStateProvider.overrideWithValue(
          catalogSnapshotState ??
              const CatalogSnapshotState(
                context: null,
                connectionStatus: CatalogConnectionStatus.online,
                refreshStatus: CatalogRefreshStatus.idle,
                sessionStatus: CatalogSessionStatus.verified,
                hasCachedCatalog: false,
              ),
        ),
        activeCatalogContextProvider.overrideWithValue(
          catalogSnapshotState?.context,
        ),
        if (mutablePlanningContextProvider != null)
          activePlanningContextProvider.overrideWith(
            (ref) => ref.watch(mutablePlanningContextProvider),
          )
        else
          activePlanningContextProvider.overrideWithValue(
            const ActivePlanningReadContext(
              userId: 'user-1',
              organizationId: 'org-1',
            ),
          ),
        unifiedSyncOverviewProvider.overrideWithValue(
          const UnifiedSyncOverview.initial(),
        ),
        capabilityResolverProvider.overrideWith(
          (_) =>
              capabilityResolver ??
              CapabilityResolver(
                gateway: _PlanDetailStaticCapabilityGateway(
                  Capability.values.toSet(),
                ),
              ),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  Future<void> openSessionEditor(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const ValueKey('session-1')));
    await tester.pump();
  }

  Future<void> openSessionNamePopup(WidgetTester tester) async {
    await tester.tap(
      find.byTooltip('${AppStrings.sessionRenameAction}: Warm-Up'),
    );
    await tester.pumpAndSettle();
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
      find.byKey(const ValueKey('session-drag-handle-session-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('session-item-drag-handle-item-1')),
      findsOneWidget,
    );
  });

  testWidgets('shows the plan scheduled date in the header', (tester) async {
    await tester.pumpWidget(
      buildApp(planDetailValue: _editablePlanDetailFixture()),
    );
    await tester.pumpAndSettle();

    final titleContext = tester.element(find.text('Team Rehearsal'));
    final scheduledForLabel = MaterialLocalizations.of(
      titleContext,
    ).formatMediumDate(DateTime(2026, 4, 10, 18));

    expect(find.text('Fixture'), findsOneWidget);
    expect(find.text(scheduledForLabel), findsOneWidget);
  });

  testWidgets('shows an explicit loading state while the plan loads', (
    tester,
  ) async {
    final completer = Completer<PlanDetail>();

    await tester.pumpWidget(buildApp(planDetailValue: completer.future));
    await tester.pump();

    expect(find.text(AppStrings.planDetailLoadingMessage), findsOneWidget);
  });

  testWidgets('keeps current plan detail visible while revision reloads', (
    tester,
  ) async {
    final reloadCompleter = Completer<PlanDetail>();
    var reads = 0;

    await tester.pumpWidget(
      buildApp(
        planDetailValue: Future<PlanDetail>.sync(() {
          reads += 1;
          if (reads == 1) {
            return _editablePlanDetailFixture();
          }
          return reloadCompleter.future;
        }),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Team Rehearsal'), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(PlanDetailScreen)),
    );
    container.read(planningDataRevisionProvider.notifier).state += 1;
    await tester.pump();

    expect(find.text('Team Rehearsal'), findsOneWidget);
    expect(find.text(AppStrings.planDetailLoadingMessage), findsNothing);
  });

  testWidgets('shows an explicit failure surface when the plan cannot load', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp(planDetailValue: StateError('boom')));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.planDetailLoadFailureMessage), findsOneWidget);
    expect(find.text(AppStrings.retryAction), findsOneWidget);
  });

  testWidgets('shows delete action only for empty sessions', (tester) async {
    await tester.pumpWidget(
      buildApp(
        planDetailValue: PlanDetail(
          plan: PlanSummary(
            id: 'plan-1',
            slug: 'team-rehearsal',
            name: 'Team Rehearsal',
            description: 'Fixture',
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
                  song: SongSummary(id: 'song-1', title: 'Zulu Song'),
                ),
              ],
            ),
            SessionSummary(
              id: 'session-2',
              slug: 'closing',
              name: 'Closing',
              position: 20,
              items: [],
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byTooltip('${AppStrings.sessionDeleteAction}: Closing'),
      findsOneWidget,
    );
    expect(
      find.byTooltip('${AppStrings.sessionDeleteAction}: Warm-Up'),
      findsNothing,
    );
  });

  testWidgets('shows an explicit no-session state in plan detail', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildApp(
        planDetailValue: PlanDetail(
          plan: PlanSummary(
            id: 'plan-1',
            slug: 'team-rehearsal',
            name: 'Team Rehearsal',
            description: 'Fixture',
            scheduledFor: null,
            updatedAt: DateTime(2026, 3, 31, 9),
          ),
          sessions: const [],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.sessionListEmptyMessage), findsOneWidget);
  });

  testWidgets('shows inline add-song and rename controls on session cards', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildApp(planDetailValue: _editablePlanDetailFixture()),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.sessionEditAction), findsNothing);
    expect(
      find.byKey(const ValueKey('session-add-song-session-1')),
      findsOneWidget,
    );
    expect(
      find.byTooltip('${AppStrings.sessionRenameAction}: Warm-Up'),
      findsOneWidget,
    );
  });

  testWidgets('opens the session name popup from detail', (tester) async {
    await tester.pumpWidget(
      buildApp(planDetailValue: _planDetailWithItemsFixture()),
    );
    await tester.pumpAndSettle();

    await openSessionNamePopup(tester);

    expect(find.byKey(const ValueKey('session-editor-name')), findsOneWidget);
    expect(
      find.widgetWithText(AlertDialog, AppStrings.sessionEditorTitleRename),
      findsOneWidget,
    );
    expect(find.text(AppStrings.sessionItemAddSongAction), findsWidgets);
  });

  testWidgets('edits a plan locally from the detail screen', (tester) async {
    final writeService = _FakePlanningWriteService();

    await tester.pumpWidget(
      buildApp(
        planDetailValue: _editablePlanDetailFixture(),
        writeService: writeService,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(AppStrings.planEditAction));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('plan-editor-name')),
      'Updated Team Rehearsal',
    );
    await tester.tap(find.text(AppStrings.planSaveAction));
    await tester.pumpAndSettle();

    expect(writeService.editedDraft?.planId, 'plan-1');
    expect(writeService.editedDraft?.name, 'Updated Team Rehearsal');
  });

  testWidgets(
    'async plan edit completion after dispose does not raise invalidation errors',
    (tester) async {
      final completer = Completer<void>();
      final writeService = _DelayedPlanningWriteService(
        onEditPlan: () => completer.future,
      );

      await tester.pumpWidget(
        buildApp(
          planDetailValue: _editablePlanDetailFixture(),
          writeService: writeService,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip(AppStrings.planEditAction));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('plan-editor-name')),
        'Updated Team Rehearsal',
      );
      await tester.tap(find.text(AppStrings.planSaveAction));
      await tester.pump();

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump();

      completer.complete();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(writeService.editedDraft?.name, 'Updated Team Rehearsal');
    },
  );

  testWidgets('creates and renames sessions locally from the detail screen', (
    tester,
  ) async {
    final writeService = _FakePlanningWriteService();

    await tester.pumpWidget(
      buildApp(
        planDetailValue: _editablePlanDetailFixture(),
        writeService: writeService,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(AppStrings.sessionCreateAction));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('session-editor-name')),
      'Closing',
    );
    await tester.tap(find.text(AppStrings.planSaveAction));
    await tester.pumpAndSettle();

    expect(writeService.createdSessionDraft?.planId, 'plan-1');
    expect(writeService.createdSessionDraft?.name, 'Closing');

    await openSessionNamePopup(tester);
    await tester.enterText(
      find.byKey(const ValueKey('session-editor-name')),
      'Warm-Up Updated',
    );
    await tester.tap(find.text(AppStrings.planSaveAction));
    await tester.pumpAndSettle();

    expect(writeService.renamedSessionDraft?.sessionId, 'session-1');
    expect(writeService.renamedSessionDraft?.name, 'Warm-Up Updated');
  });

  testWidgets('session rename rejects an empty name', (tester) async {
    final writeService = _FakePlanningWriteService();

    await tester.pumpWidget(
      buildApp(
        planDetailValue: _editablePlanDetailFixture(),
        writeService: writeService,
      ),
    );
    await tester.pumpAndSettle();

    await openSessionNamePopup(tester);
    await tester.enterText(
      find.byKey(const ValueKey('session-editor-name')),
      '   ',
    );
    await tester.tap(find.text(AppStrings.planSaveAction));
    await tester.pumpAndSettle();

    expect(writeService.renamedSessionDraft, isNull);
  });

  testWidgets('deletes an empty session locally after confirmation', (
    tester,
  ) async {
    final writeService = _FakePlanningWriteService();

    await tester.pumpWidget(
      buildApp(
        planDetailValue: _editablePlanDetailFixture(),
        writeService: writeService,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byTooltip('${AppStrings.sessionDeleteAction}: Closing'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.sessionDeleteConfirmAction));
    await tester.pumpAndSettle();

    expect(writeService.deletedSessionDraft?.sessionId, 'session-2');
  });

  testWidgets('cancelling the session delete dialog does not delete', (
    tester,
  ) async {
    final writeService = _FakePlanningWriteService();

    await tester.pumpWidget(
      buildApp(
        planDetailValue: _editablePlanDetailFixture(),
        writeService: writeService,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byTooltip('${AppStrings.sessionDeleteAction}: Closing'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.songCancelAction));
    await tester.pumpAndSettle();

    expect(writeService.deletedSessionDraft, isNull);
  });

  testWidgets('tap on the session drag handle does not reorder sessions', (
    tester,
  ) async {
    final writeService = _FakePlanningWriteService();

    await tester.pumpWidget(
      buildApp(
        planDetailValue: _editablePlanDetailFixture(),
        writeService: writeService,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('session-drag-handle-session-1')),
    );
    await tester.pumpAndSettle();

    expect(writeService.reorderedSessionDraft, isNull);
    expect(
      tester.getTopLeft(find.text('Warm-Up')).dy,
      lessThan(tester.getTopLeft(find.text('Closing')).dy),
    );
  });

  testWidgets('ignores no-op session reorder requests', (tester) async {
    final writeService = _FakePlanningWriteService();

    await tester.pumpWidget(
      buildApp(
        planDetailValue: _editablePlanDetailFixture(),
        writeService: writeService,
      ),
    );
    await tester.pumpAndSettle();

    final sessionList = tester
        .widgetList<ReorderableListView>(find.byType(ReorderableListView))
        .first;
    sessionList.onReorder(0, 0);
    await tester.pumpAndSettle();

    expect(writeService.reorderedSessionDraft, isNull);
  });

  testWidgets('queues session reorder requests while one is in flight', (
    tester,
  ) async {
    final firstReorderCompleter = Completer<void>();
    var sessionReorderCalls = 0;
    final writeService = _FakePlanningWriteService(
      onReorderSessions: (_) async {
        sessionReorderCalls += 1;
        if (sessionReorderCalls == 1) {
          await firstReorderCompleter.future;
        }
      },
    );

    await tester.pumpWidget(
      buildApp(
        planDetailValue: _editablePlanDetailFixture(),
        writeService: writeService,
      ),
    );
    await tester.pumpAndSettle();

    final sessionList = tester
        .widgetList<ReorderableListView>(find.byType(ReorderableListView))
        .first;
    sessionList.onReorder(0, 2);
    await tester.pump();
    sessionList.onReorder(1, 0);
    await tester.pump();

    expect(writeService.reorderSessionsCallCount, 1);

    firstReorderCompleter.complete();
    await tester.pumpAndSettle();

    expect(writeService.reorderSessionsCallCount, 2);
    expect(writeService.reorderedSessionDrafts, hasLength(2));
  });

  testWidgets('shows reordered sessions before the local write completes', (
    tester,
  ) async {
    final reorderCompleter = Completer<void>();
    final writeService = _FakePlanningWriteService(
      onReorderSessions: (_) => reorderCompleter.future,
    );

    await tester.pumpWidget(
      buildApp(
        planDetailValue: _editablePlanDetailFixture(),
        writeService: writeService,
      ),
    );
    await tester.pumpAndSettle();

    final sessionList = tester
        .widgetList<ReorderableListView>(find.byType(ReorderableListView))
        .first;
    // _editablePlanDetailFixture has two sessions (Warm-Up, Closing), so
    // newIndex 2 is the pre-removal "insert at end" position.
    sessionList.onReorder(0, 2);
    await tester.pump();

    expect(
      tester.getTopLeft(find.text('Warm-Up')).dy,
      greaterThan(tester.getTopLeft(find.text('Closing')).dy),
    );

    reorderCompleter.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('rolls the session order back when the reorder write fails', (
    tester,
  ) async {
    final failCompleter = Completer<void>();
    final writeService = _FakePlanningWriteService(
      onReorderSessions: (_) async {
        await failCompleter.future;
        throw StateError('session reorder failed');
      },
    );

    await tester.pumpWidget(
      buildApp(
        planDetailValue: _editablePlanDetailFixture(),
        writeService: writeService,
      ),
    );
    await tester.pumpAndSettle();

    final sessionList = tester
        .widgetList<ReorderableListView>(find.byType(ReorderableListView))
        .first;
    sessionList.onReorder(0, 2);
    await tester.pump();
    expect(
      tester.getTopLeft(find.text('Warm-Up')).dy,
      greaterThan(tester.getTopLeft(find.text('Closing')).dy),
    );

    failCompleter.complete();
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('Warm-Up')).dy,
      lessThan(tester.getTopLeft(find.text('Closing')).dy),
    );
    expect(tester.takeException(), isA<StateError>());
  });

  testWidgets('stale session reorder result does not clear newer order', (
    tester,
  ) async {
    // Three sessions need a taller viewport than the default test surface
    // to stay on-screen (and buildable) at once.
    await tester.binding.setSurfaceSize(const Size(1024, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final firstReorderCompleter = Completer<void>();
    var reorderCalls = 0;
    final writeService = _FakePlanningWriteService(
      onReorderSessions: (_) async {
        reorderCalls += 1;
        if (reorderCalls == 1) {
          await firstReorderCompleter.future;
          throw StateError('late session reorder failure');
        }
      },
    );

    await tester.pumpWidget(
      buildApp(
        planDetailValue: _editablePlanDetailWithThreeSessionsFixture(),
        writeService: writeService,
      ),
    );
    await tester.pumpAndSettle();

    final sessionList = tester
        .widgetList<ReorderableListView>(find.byType(ReorderableListView))
        .first;
    // First drag (stale, blocked on firstReorderCompleter): Warm-Up, Main
    // Set, Closing -> Main Set, Warm-Up, Closing.
    sessionList.onReorder(0, 2);
    await tester.pump();
    // Second drag (newer, queued behind the first): Main Set, Warm-Up,
    // Closing -> Main Set, Closing, Warm-Up.
    sessionList.onReorder(1, 3);
    await tester.pump();

    expect(
      tester.getTopLeft(find.text('Closing')).dy,
      greaterThan(tester.getTopLeft(find.text('Main Set')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Warm-Up')).dy,
      greaterThan(tester.getTopLeft(find.text('Closing')).dy),
    );

    firstReorderCompleter.complete();
    await tester.pumpAndSettle();

    // If the stale (failing) first result incorrectly cleared the
    // optimistic order, this would fall back to the original order
    // (Warm-Up, Main Set, Closing) instead of holding the second drag's
    // order (Main Set, Closing, Warm-Up).
    expect(
      tester.getTopLeft(find.text('Closing')).dy,
      greaterThan(tester.getTopLeft(find.text('Main Set')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Warm-Up')).dy,
      greaterThan(tester.getTopLeft(find.text('Closing')).dy),
    );
  });

  testWidgets(
    'long-press drag on the session handle reorders sessions',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: _ReorderHandleHarness())),
      );
      await tester.pumpAndSettle();

      final dragHandle = find.byKey(
        const ValueKey('session-drag-handle-warm-up'),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(dragHandle),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump(kLongPressTimeout);
      await gesture.moveBy(const Offset(0, 10));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 40));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(find.text('Closing')).dy,
        lessThan(tester.getTopLeft(find.text('Warm-Up')).dy),
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets('adds a visible song locally from the session picker', (
    tester,
  ) async {
    final writeService = _FakePlanningWriteService();

    await tester.pumpWidget(
      buildApp(
        planDetailValue: _editablePlanDetailFixture(),
        writeService: writeService,
        visibleSongs: const [
          SongSummary(id: 'song-1', slug: 'alpha', title: 'Alpha'),
          SongSummary(id: 'song-2', slug: 'beta', title: 'Beta'),
          SongSummary(id: 'song-3', slug: 'gamma', title: 'Gamma'),
        ],
        catalogSnapshotState: const CatalogSnapshotState(
          context: null,
          connectionStatus: CatalogConnectionStatus.online,
          refreshStatus: CatalogRefreshStatus.idle,
          sessionStatus: CatalogSessionStatus.verified,
          hasCachedCatalog: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await openSessionEditor(tester);
    await tester.tap(find.text(AppStrings.sessionItemAddSongAction).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('session-song-option-song-3')));
    await tester.pumpAndSettle();

    expect(writeService.createdSessionItemDraft?.sessionId, 'session-1');
    expect(writeService.createdSessionItemDraft?.songId, 'song-3');
  });

  testWidgets('ignores duplicate song add failures from the picker flow', (
    tester,
  ) async {
    final writeService = _FakePlanningWriteService(
      addSongException: const DuplicateSessionSongException(
        'session-1',
        'song-1',
      ),
    );

    await tester.pumpWidget(
      buildApp(
        planDetailValue: _editablePlanDetailFixture(),
        writeService: writeService,
        visibleSongs: const [
          SongSummary(id: 'song-1', slug: 'alpha', title: 'Alpha'),
        ],
        catalogSnapshotState: const CatalogSnapshotState(
          context: null,
          connectionStatus: CatalogConnectionStatus.online,
          refreshStatus: CatalogRefreshStatus.idle,
          sessionStatus: CatalogSessionStatus.verified,
          hasCachedCatalog: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await openSessionEditor(tester);
    await tester.tap(find.byKey(const ValueKey('session-add-song-session-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('session-song-option-song-1')));
    await tester.pumpAndSettle();

    expect(writeService.createdSessionItemDraft, isNotNull);
    expect(
      find.byKey(const ValueKey('session-song-picker-body')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('session-add-song-focus-session-1')),
      findsOneWidget,
    );
  });

  testWidgets('opens picker with cached songs after refresh later fails', (
    tester,
  ) async {
    var loadCount = 0;
    final writeService = _FakePlanningWriteService();

    await tester.pumpWidget(
      buildApp(
        planDetailValue: _editablePlanDetailFixture(),
        writeService: writeService,
        songsForContext: (context) {
          loadCount += 1;
          if (loadCount == 1) {
            return const [
              SongSummary(id: 'song-1', slug: 'alpha', title: 'Alpha'),
              SongSummary(id: 'song-2', slug: 'beta', title: 'Beta'),
            ];
          }
          throw StateError('refresh failed');
        },
        catalogSnapshotState: const CatalogSnapshotState(
          context: ActiveCatalogContext(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
          connectionStatus: CatalogConnectionStatus.online,
          refreshStatus: CatalogRefreshStatus.idle,
          sessionStatus: CatalogSessionStatus.verified,
          hasCachedCatalog: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(PlanDetailScreen)),
    );
    container.invalidate(songLibraryListProvider);
    await tester.pumpAndSettle();

    await openSessionEditor(tester);
    await tester.tap(find.byKey(const ValueKey('session-add-song-session-1')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('session-song-picker-body')),
      findsOneWidget,
    );
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(
      find.text(AppStrings.sessionItemSongPickerUnavailableMessage),
      findsNothing,
    );
    expect(writeService.createdSessionItemDraft, isNull);
  });

  testWidgets(
    'aborts add-song when active planning context changes while picker is open',
    (tester) async {
      final planningContextProvider = StateProvider<ActivePlanningReadContext?>(
        (ref) => const ActivePlanningReadContext(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
      );
      final writeService = _FakePlanningWriteService();

      await tester.pumpWidget(
        buildApp(
          planDetailValue: _editablePlanDetailFixture(),
          writeService: writeService,
          mutablePlanningContextProvider: planningContextProvider,
          visibleSongs: const [
            SongSummary(id: 'song-1', slug: 'alpha', title: 'Alpha'),
            SongSummary(id: 'song-2', slug: 'beta', title: 'Beta'),
          ],
          catalogSnapshotState: const CatalogSnapshotState(
            context: ActiveCatalogContext(
              userId: 'user-1',
              organizationId: 'org-1',
            ),
            connectionStatus: CatalogConnectionStatus.online,
            refreshStatus: CatalogRefreshStatus.idle,
            sessionStatus: CatalogSessionStatus.verified,
            hasCachedCatalog: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlanDetailScreen)),
      );

      await openSessionEditor(tester);
      await tester.tap(
        find.byKey(const ValueKey('session-add-song-session-1')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('session-song-picker-body')),
        findsOneWidget,
      );

      container
          .read(planningContextProvider.notifier)
          .state = const ActivePlanningReadContext(
        userId: 'user-1',
        organizationId: 'org-2',
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('session-song-picker-body')),
        findsNothing,
      );

      expect(writeService.createdSessionItemDraft, isNull);
      expect(writeService.createdSongContext, isNull);
    },
  );

  testWidgets(
    'aborts add-song when active catalog changes while picker is open',
    (tester) async {
      final catalogStateProvider = StateProvider<CatalogSnapshotState>(
        (ref) => const CatalogSnapshotState(
          context: ActiveCatalogContext(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
          connectionStatus: CatalogConnectionStatus.online,
          refreshStatus: CatalogRefreshStatus.idle,
          sessionStatus: CatalogSessionStatus.verified,
          hasCachedCatalog: true,
        ),
      );
      final writeService = _FakePlanningWriteService();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            catalogSnapshotStateProvider.overrideWith(
              (ref) => ref.watch(catalogStateProvider),
            ),
            activeCatalogContextProvider.overrideWith(
              (ref) => ref.watch(catalogStateProvider).context,
            ),
            planningPlanDetailProvider(
              'plan-1',
            ).overrideWith((ref) => Future.value(_editablePlanDetailFixture())),
            planningMutationEntriesProvider.overrideWith(
              (ref) async => const <PlanningMutationRecord>[],
            ),
            activePlanningContextProvider.overrideWithValue(
              const ActivePlanningReadContext(
                userId: 'user-1',
                organizationId: 'org-1',
              ),
            ),
            unifiedSyncOverviewProvider.overrideWithValue(
              const UnifiedSyncOverview.initial(),
            ),
            songLibraryListProvider.overrideWith(
              (ref) => Future.value(const [
                SongSummary(id: 'song-1', slug: 'alpha', title: 'Alpha'),
                SongSummary(id: 'song-2', slug: 'beta', title: 'Beta'),
              ]),
            ),
            capabilityResolverProvider.overrideWith(
              (_) => CapabilityResolver(
                gateway: _PlanDetailStaticCapabilityGateway(
                  Capability.values.toSet(),
                ),
              ),
            ),
          ],
          child: MaterialApp.router(
            routerConfig: GoRouter(
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
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlanDetailScreen)),
      );

      await openSessionEditor(tester);
      await tester.tap(
        find.byKey(const ValueKey('session-add-song-session-1')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('session-song-picker-body')),
        findsOneWidget,
      );

      container
          .read(catalogStateProvider.notifier)
          .state = const CatalogSnapshotState(
        context: ActiveCatalogContext(
          userId: 'user-1',
          organizationId: 'org-2',
        ),
        connectionStatus: CatalogConnectionStatus.online,
        refreshStatus: CatalogRefreshStatus.idle,
        sessionStatus: CatalogSessionStatus.verified,
        hasCachedCatalog: true,
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('session-song-picker-body')),
        findsNothing,
      );
      expect(writeService.createdSessionItemDraft, isNull);
    },
  );

  testWidgets(
    'aborts add-song when active planning context changes before picker opens',
    (tester) async {
      final planningContextProvider = StateProvider<ActivePlanningReadContext?>(
        (ref) => const ActivePlanningReadContext(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
      );
      final writeService = _FakePlanningWriteService();

      await tester.pumpWidget(
        buildApp(
          planDetailValue: _editablePlanDetailFixture(),
          writeService: writeService,
          mutablePlanningContextProvider: planningContextProvider,
          songsForContext: (context) {
            return switch (context?.organizationId) {
              'org-1' => const [
                SongSummary(id: 'song-1', slug: 'alpha', title: 'Alpha'),
                SongSummary(id: 'song-2', slug: 'beta', title: 'Beta'),
              ],
              _ => const [
                SongSummary(id: 'song-3', slug: 'gamma', title: 'Gamma'),
              ],
            };
          },
          catalogSnapshotState: const CatalogSnapshotState(
            context: ActiveCatalogContext(
              userId: 'user-1',
              organizationId: 'org-1',
            ),
            connectionStatus: CatalogConnectionStatus.online,
            refreshStatus: CatalogRefreshStatus.idle,
            sessionStatus: CatalogSessionStatus.verified,
            hasCachedCatalog: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlanDetailScreen)),
      );

      await openSessionEditor(tester);
      await tester.tap(
        find.byKey(const ValueKey('session-add-song-session-1')),
      );
      container
          .read(planningContextProvider.notifier)
          .state = const ActivePlanningReadContext(
        userId: 'user-1',
        organizationId: 'org-2',
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('session-song-picker-body')),
        findsNothing,
      );
      expect(writeService.createdSessionItemDraft, isNull);
      expect(writeService.createdSongContext, isNull);
    },
  );

  testWidgets('disables add-song while the local add is in flight', (
    tester,
  ) async {
    final addCompleter = Completer<void>();
    final writeService = _FakePlanningWriteService(
      addSongCompleter: addCompleter,
    );

    await tester.pumpWidget(
      buildApp(
        planDetailValue: _editablePlanDetailFixture(),
        writeService: writeService,
        visibleSongs: const [
          SongSummary(id: 'song-1', slug: 'alpha', title: 'Alpha'),
          SongSummary(id: 'song-2', slug: 'beta', title: 'Beta'),
        ],
        catalogSnapshotState: const CatalogSnapshotState(
          context: null,
          connectionStatus: CatalogConnectionStatus.online,
          refreshStatus: CatalogRefreshStatus.idle,
          sessionStatus: CatalogSessionStatus.verified,
          hasCachedCatalog: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final addButtonFinder = find.byKey(
      const ValueKey('session-add-song-session-1'),
    );

    await openSessionEditor(tester);
    await tester.tap(addButtonFinder);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('session-song-option-song-1')));
    await tester.pump();

    expect(tester.widget<TextButton>(addButtonFinder).onPressed, isNull);
    expect(
      find.text(AppStrings.sessionItemSongPickerAddInProgressMessage),
      findsWidgets,
    );

    addCompleter.complete();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'opens a loading picker while active catalog switches and list reloads',
    (tester) async {
      final catalogStateProvider = StateProvider<CatalogSnapshotState>(
        (ref) => const CatalogSnapshotState(
          context: ActiveCatalogContext(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
          connectionStatus: CatalogConnectionStatus.online,
          refreshStatus: CatalogRefreshStatus.idle,
          sessionStatus: CatalogSessionStatus.verified,
          hasCachedCatalog: true,
        ),
      );
      final org2SongsCompleter = Completer<List<SongSummary>>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            catalogSnapshotStateProvider.overrideWith(
              (ref) => ref.watch(catalogStateProvider),
            ),
            activeCatalogContextProvider.overrideWith(
              (ref) => ref.watch(catalogStateProvider).context,
            ),
            planningPlanDetailProvider(
              'plan-1',
            ).overrideWith((ref) => Future.value(_editablePlanDetailFixture())),
            songLibraryListProvider.overrideWith((ref) {
              final context = ref.watch(activeCatalogContextProvider);
              return switch (context?.organizationId) {
                'org-1' => Future.value(const [
                  SongSummary(id: 'song-1', slug: 'alpha', title: 'Alpha'),
                  SongSummary(id: 'song-2', slug: 'beta', title: 'Beta'),
                ]),
                _ => org2SongsCompleter.future,
              };
            }),
            activePlanningContextProvider.overrideWithValue(
              const ActivePlanningReadContext(
                userId: 'user-1',
                organizationId: 'org-1',
              ),
            ),
            unifiedSyncOverviewProvider.overrideWithValue(
              const UnifiedSyncOverview.initial(),
            ),
            capabilityResolverProvider.overrideWith(
              (_) => CapabilityResolver(
                gateway: _PlanDetailStaticCapabilityGateway(
                  Capability.values.toSet(),
                ),
              ),
            ),
          ],
          child: MaterialApp.router(
            routerConfig: GoRouter(
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
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlanDetailScreen)),
      );
      final addButtonFinder = find.byKey(
        const ValueKey('session-add-song-session-1'),
      );

      await openSessionEditor(tester);
      expect(tester.widget<TextButton>(addButtonFinder).onPressed, isNotNull);

      container
          .read(catalogStateProvider.notifier)
          .state = const CatalogSnapshotState(
        context: ActiveCatalogContext(
          userId: 'user-1',
          organizationId: 'org-2',
        ),
        connectionStatus: CatalogConnectionStatus.online,
        refreshStatus: CatalogRefreshStatus.idle,
        sessionStatus: CatalogSessionStatus.verified,
        hasCachedCatalog: true,
      );
      await tester.pump();

      expect(tester.widget<TextButton>(addButtonFinder).onPressed, isNotNull);
      await tester.tap(addButtonFinder);
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.text(AppStrings.sessionItemSongPickerLoadingMessage),
        findsOneWidget,
      );

      org2SongsCompleter.complete(const []);
      await tester.pumpAndSettle();
    },
  );

  testWidgets('closes the tablet picker after adding a song', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final writeService = _FakePlanningWriteService();

    await tester.pumpWidget(
      buildApp(
        planDetailValue: _editablePlanDetailFixture(),
        writeService: writeService,
        visibleSongs: const [
          SongSummary(id: 'song-1', slug: 'alpha', title: 'Alpha'),
          SongSummary(id: 'song-2', slug: 'beta', title: 'Beta'),
        ],
        catalogSnapshotState: const CatalogSnapshotState(
          context: null,
          connectionStatus: CatalogConnectionStatus.online,
          refreshStatus: CatalogRefreshStatus.idle,
          sessionStatus: CatalogSessionStatus.verified,
          hasCachedCatalog: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await openSessionEditor(tester);
    await tester.tap(find.byKey(const ValueKey('session-add-song-session-1')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('session-song-picker-body')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('session-song-option-song-1')));
    await tester.pumpAndSettle();

    expect(writeService.createdSessionItemDraft?.songId, 'song-1');
    expect(
      find.byKey(const ValueKey('session-song-picker-body')),
      findsNothing,
    );
  });

  testWidgets('closes the tablet picker before the add finishes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1024, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final addCompleter = Completer<void>();
    final writeService = _FakePlanningWriteService(
      addSongCompleter: addCompleter,
    );

    await tester.pumpWidget(
      buildApp(
        planDetailValue: _editablePlanDetailFixture(),
        writeService: writeService,
        visibleSongs: const [
          SongSummary(id: 'song-1', slug: 'alpha', title: 'Alpha'),
          SongSummary(id: 'song-2', slug: 'beta', title: 'Beta'),
        ],
        catalogSnapshotState: const CatalogSnapshotState(
          context: null,
          connectionStatus: CatalogConnectionStatus.online,
          refreshStatus: CatalogRefreshStatus.idle,
          sessionStatus: CatalogSessionStatus.verified,
          hasCachedCatalog: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await openSessionEditor(tester);
    await tester.tap(find.byKey(const ValueKey('session-add-song-session-1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('session-song-option-song-1')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('session-song-picker-body')),
      findsNothing,
    );

    addCompleter.complete();
    await tester.pumpAndSettle();

    expect(writeService.createdSessionItemDraft?.songId, 'song-1');
  });

  testWidgets('opens picker in loading state while songs resolve', (
    tester,
  ) async {
    final songsCompleter = Completer<List<SongSummary>>();

    await tester.pumpWidget(
      buildApp(
        planDetailValue: _editablePlanDetailFixture(),
        songsForContext: (_) => songsCompleter.future,
        catalogSnapshotState: const CatalogSnapshotState(
          context: ActiveCatalogContext(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
          connectionStatus: CatalogConnectionStatus.online,
          refreshStatus: CatalogRefreshStatus.idle,
          sessionStatus: CatalogSessionStatus.verified,
          hasCachedCatalog: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final addButtonFinder = find.byKey(
      const ValueKey('session-add-song-session-1'),
    );

    await openSessionEditor(tester);
    expect(tester.widget<TextButton>(addButtonFinder).onPressed, isNotNull);
    await tester.tap(addButtonFinder);
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.text(AppStrings.sessionItemSongPickerLoadingMessage),
      findsOneWidget,
    );

    songsCompleter.complete(const [
      SongSummary(id: 'song-1', slug: 'alpha', title: 'Alpha'),
      SongSummary(id: 'song-2', slug: 'beta', title: 'Beta'),
    ]);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('session-song-picker-search-field')),
      findsOneWidget,
    );
  });

  testWidgets('returns focus to the add-song control after picker dismissal', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildApp(
        planDetailValue: _editablePlanDetailFixture(),
        visibleSongs: const [
          SongSummary(id: 'song-1', slug: 'alpha', title: 'Alpha'),
          SongSummary(id: 'song-2', slug: 'beta', title: 'Beta'),
        ],
        catalogSnapshotState: const CatalogSnapshotState(
          context: null,
          connectionStatus: CatalogConnectionStatus.online,
          refreshStatus: CatalogRefreshStatus.idle,
          sessionStatus: CatalogSessionStatus.verified,
          hasCachedCatalog: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await openSessionEditor(tester);
    final addFocusFinder = find.byKey(
      const ValueKey('session-add-song-focus-session-1'),
    );
    expect(addFocusFinder, findsOneWidget);
    expect(tester.widget<Focus>(addFocusFinder).focusNode!.hasFocus, isFalse);
    await tester.tap(find.text(AppStrings.sessionItemAddSongAction).first);
    await tester.pumpAndSettle();

    await tester.tap(find.text(AppStrings.songCancelAction));
    await tester.pumpAndSettle();

    expect(tester.widget<Focus>(addFocusFinder).focusNode!.hasFocus, isTrue);
  });

  testWidgets('disables add-song while the picker is open', (tester) async {
    await tester.pumpWidget(
      buildApp(
        planDetailValue: _editablePlanDetailFixture(),
        visibleSongs: const [
          SongSummary(id: 'song-1', slug: 'alpha', title: 'Alpha'),
          SongSummary(id: 'song-2', slug: 'beta', title: 'Beta'),
        ],
        catalogSnapshotState: const CatalogSnapshotState(
          context: null,
          connectionStatus: CatalogConnectionStatus.online,
          refreshStatus: CatalogRefreshStatus.idle,
          sessionStatus: CatalogSessionStatus.verified,
          hasCachedCatalog: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final addButtonFinder = find.byKey(
      const ValueKey('session-add-song-session-1'),
    );

    await openSessionEditor(tester);
    await tester.tap(addButtonFinder);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('session-song-picker-body')),
      findsOneWidget,
    );
    expect(tester.widget<TextButton>(addButtonFinder).onPressed, isNull);
  });

  testWidgets('disables add-song when no cached catalog is available', (
    tester,
  ) async {
    // Set a large viewport for CI stability
    await tester.binding.setSurfaceSize(const Size(1440, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      buildApp(planDetailValue: _editablePlanDetailFixture()),
    );
    await tester.pumpAndSettle();

    await openSessionEditor(tester);
    // Use a direct ValueKey for maximum robustness
    final addButtonFinder = find.byKey(
      const ValueKey('session-add-song-session-1'),
    );

    expect(addButtonFinder, findsOneWidget);

    final addButton = tester.widget<TextButton>(addButtonFinder);
    expect(addButton.onPressed, isNull);
    expect(
      find.text(AppStrings.sessionItemSongUnavailableMessage),
      findsWidgets,
    );
  });

  testWidgets(
    'deletes and reorders session items locally from the detail screen',
    (tester) async {
      final writeService = _FakePlanningWriteService();

      await tester.pumpWidget(
        buildApp(
          planDetailValue: _planDetailWithItemsFixture(),
          writeService: writeService,
          visibleSongs: const [
            SongSummary(id: 'song-1', slug: 'alpha', title: 'Alpha'),
            SongSummary(id: 'song-2', slug: 'beta', title: 'Beta'),
          ],
          catalogSnapshotState: const CatalogSnapshotState(
            context: null,
            connectionStatus: CatalogConnectionStatus.online,
            refreshStatus: CatalogRefreshStatus.idle,
            sessionStatus: CatalogSessionStatus.verified,
            hasCachedCatalog: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byTooltip('${AppStrings.sessionItemDeleteAction}: Alpha'),
      );
      await tester.tap(
        find.byTooltip('${AppStrings.sessionItemDeleteAction}: Alpha'),
      );
      await tester.pumpAndSettle();

      expect(writeService.deletedSessionItemDraft?.sessionItemId, 'item-1');

      final itemList = tester
          .widgetList<ReorderableListView>(find.byType(ReorderableListView))
          .elementAt(1);
      itemList.onReorder(1, 0);
      await tester.pumpAndSettle();

      expect(
        writeService.reorderedSessionItemDraft?.orderedSessionItemIds,
        orderedEquals(const ['item-2', 'item-1']),
      );
    },
  );

  testWidgets('ignores no-op session item reorder requests', (tester) async {
    final writeService = _FakePlanningWriteService();

    await tester.pumpWidget(
      buildApp(
        planDetailValue: _planDetailWithItemsFixture(),
        writeService: writeService,
        visibleSongs: const [
          SongSummary(id: 'song-1', slug: 'alpha', title: 'Alpha'),
          SongSummary(id: 'song-2', slug: 'beta', title: 'Beta'),
        ],
        catalogSnapshotState: const CatalogSnapshotState(
          context: null,
          connectionStatus: CatalogConnectionStatus.online,
          refreshStatus: CatalogRefreshStatus.idle,
          sessionStatus: CatalogSessionStatus.verified,
          hasCachedCatalog: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final itemList = tester
        .widgetList<ReorderableListView>(find.byType(ReorderableListView))
        .elementAt(1);
    itemList.onReorder(0, 0);
    await tester.pumpAndSettle();

    expect(writeService.reorderedSessionItemDraft, isNull);
  });

  testWidgets('queues session item reorder requests while one is in flight', (
    tester,
  ) async {
    final firstReorderCompleter = Completer<void>();
    final writeService = _FakePlanningWriteService(
      reorderSessionItemsCompleter: firstReorderCompleter,
    );

    await tester.pumpWidget(
      buildApp(
        planDetailValue: _planDetailWithItemsFixture(),
        writeService: writeService,
        visibleSongs: const [
          SongSummary(id: 'song-1', slug: 'alpha', title: 'Alpha'),
          SongSummary(id: 'song-2', slug: 'beta', title: 'Beta'),
        ],
        catalogSnapshotState: const CatalogSnapshotState(
          context: null,
          connectionStatus: CatalogConnectionStatus.online,
          refreshStatus: CatalogRefreshStatus.idle,
          sessionStatus: CatalogSessionStatus.verified,
          hasCachedCatalog: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final itemList = tester
        .widgetList<ReorderableListView>(find.byType(ReorderableListView))
        .elementAt(1);
    itemList.onReorder(0, 2);
    await tester.pump();
    itemList.onReorder(1, 0);
    await tester.pump();

    expect(writeService.reorderSessionItemsCallCount, 1);

    firstReorderCompleter.complete();
    await tester.pumpAndSettle();

    expect(writeService.reorderSessionItemsCallCount, 2);
    expect(writeService.reorderedSessionItemDrafts, hasLength(2));
  });

  testWidgets('shows reordered session items before local write completes', (
    tester,
  ) async {
    final reorderCompleter = Completer<void>();
    final writeService = _FakePlanningWriteService(
      reorderSessionItemsCompleter: reorderCompleter,
    );

    await tester.pumpWidget(
      buildApp(
        planDetailValue: _planDetailWithItemsFixture(),
        writeService: writeService,
        visibleSongs: const [
          SongSummary(id: 'song-1', slug: 'alpha', title: 'Alpha'),
          SongSummary(id: 'song-2', slug: 'beta', title: 'Beta'),
        ],
        catalogSnapshotState: const CatalogSnapshotState(
          context: null,
          connectionStatus: CatalogConnectionStatus.online,
          refreshStatus: CatalogRefreshStatus.idle,
          sessionStatus: CatalogSessionStatus.verified,
          hasCachedCatalog: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final itemList = tester
        .widgetList<ReorderableListView>(find.byType(ReorderableListView))
        .elementAt(1);
    itemList.onReorder(1, 0);
    await tester.pump();

    expect(
      tester.getTopLeft(find.textContaining('Beta')).dy,
      lessThan(tester.getTopLeft(find.textContaining('Alpha')).dy),
    );
    expect(writeService.reorderedSessionItemDraft, isNull);

    reorderCompleter.complete();
    await tester.pumpAndSettle();

    expect(
      writeService.reorderedSessionItemDraft?.orderedSessionItemIds,
      orderedEquals(const ['item-2', 'item-1']),
    );
  });

  testWidgets('stale item reorder result does not clear newer order', (
    tester,
  ) async {
    final firstReorderCompleter = Completer<void>();
    var reorderCalls = 0;
    final writeService = _FakePlanningWriteService(
      onReorderSessionItems: (_) async {
        reorderCalls += 1;
        if (reorderCalls == 1) {
          await firstReorderCompleter.future;
          throw StateError('late item reorder failure');
        }
      },
    );

    await tester.pumpWidget(
      buildApp(
        planDetailValue: _planDetailWithThreeItemsFixture(),
        writeService: writeService,
        visibleSongs: const [
          SongSummary(id: 'song-1', slug: 'alpha', title: 'Alpha'),
          SongSummary(id: 'song-2', slug: 'beta', title: 'Beta'),
          SongSummary(id: 'song-3', slug: 'gamma', title: 'Gamma'),
        ],
        catalogSnapshotState: const CatalogSnapshotState(
          context: null,
          connectionStatus: CatalogConnectionStatus.online,
          refreshStatus: CatalogRefreshStatus.idle,
          sessionStatus: CatalogSessionStatus.verified,
          hasCachedCatalog: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final itemList = tester
        .widgetList<ReorderableListView>(find.byType(ReorderableListView))
        .elementAt(1);
    itemList.onReorder(0, 2);
    await tester.pump();
    itemList.onReorder(1, 3);
    await tester.pump();

    expect(
      tester.getTopLeft(find.textContaining('Alpha')).dy,
      greaterThan(tester.getTopLeft(find.textContaining('Beta')).dy),
    );
    expect(
      tester.getTopLeft(find.textContaining('Alpha')).dy,
      greaterThan(tester.getTopLeft(find.textContaining('Gamma')).dy),
    );

    firstReorderCompleter.complete();
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.textContaining('Alpha')).dy,
      greaterThan(tester.getTopLeft(find.textContaining('Beta')).dy),
    );
    expect(
      tester.getTopLeft(find.textContaining('Alpha')).dy,
      greaterThan(tester.getTopLeft(find.textContaining('Gamma')).dy),
    );
  });

  testWidgets('rolls the session item order back when the write fails', (
    tester,
  ) async {
    final failCompleter = Completer<void>();
    final writeService = _FakePlanningWriteService(
      onReorderSessionItems: (_) async {
        await failCompleter.future;
        throw StateError('item reorder failed');
      },
    );

    await tester.pumpWidget(
      buildApp(
        planDetailValue: _planDetailWithItemsFixture(),
        writeService: writeService,
        visibleSongs: const [
          SongSummary(id: 'song-1', slug: 'alpha', title: 'Alpha'),
          SongSummary(id: 'song-2', slug: 'beta', title: 'Beta'),
        ],
        catalogSnapshotState: const CatalogSnapshotState(
          context: null,
          connectionStatus: CatalogConnectionStatus.online,
          refreshStatus: CatalogRefreshStatus.idle,
          sessionStatus: CatalogSessionStatus.verified,
          hasCachedCatalog: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final itemList = tester
        .widgetList<ReorderableListView>(find.byType(ReorderableListView))
        .elementAt(1);
    itemList.onReorder(1, 0);
    await tester.pump();

    expect(
      tester.getTopLeft(find.textContaining('Beta')).dy,
      lessThan(tester.getTopLeft(find.textContaining('Alpha')).dy),
    );

    failCompleter.complete();
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.textContaining('Alpha')).dy,
      lessThan(tester.getTopLeft(find.textContaining('Beta')).dy),
    );
    expect(tester.takeException(), isA<StateError>());
  });

  testWidgets('shows a validation error for invalid scheduled-for input', (
    tester,
  ) async {
    final writeService = _FakePlanningWriteService();

    await tester.pumpWidget(
      buildApp(
        planDetailValue: _editablePlanDetailFixture(),
        writeService: writeService,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(AppStrings.planEditAction));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('plan-editor-scheduled-for')),
      'not-a-date',
    );
    await tester.tap(find.text(AppStrings.planSaveAction));
    await tester.pumpAndSettle();

    expect(
      find.text(AppStrings.planScheduledForInvalidMessage),
      findsOneWidget,
    );
    expect(writeService.editedDraft, isNull);
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
            planningMutationEntriesProvider.overrideWith(
              (ref) async => const <PlanningMutationRecord>[],
            ),
            planningMutationStoreProvider.overrideWithValue(
              _PlanDetailTestPlanningMutationStore(),
            ),
            planningWriteServiceProvider.overrideWithValue(
              _FakePlanningWriteService(),
            ),
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
            activePlanningContextProvider.overrideWithValue(
              const ActivePlanningReadContext(
                userId: 'user-1',
                organizationId: 'org-1',
              ),
            ),
            capabilityResolverProvider.overrideWith(
              (_) => CapabilityResolver(
                gateway: _PlanDetailStaticCapabilityGateway(
                  Capability.values.toSet(),
                ),
              ),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('plan-session-item-item-1')));
      await tester.pumpAndSettle();

      expect(find.text('A forrasnal'), findsWidgets);
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
    'session items stay tappable from preserved planning song slug when canonical song is missing',
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
          GoRoute(
            path: AppRoutes.planSessionSongReader.path,
            builder: (context, state) => const Scaffold(body: Text('Reader')),
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
            planningMutationEntriesProvider.overrideWith(
              (ref) async => const <PlanningMutationRecord>[],
            ),
            planningMutationStoreProvider.overrideWithValue(
              _PlanDetailTestPlanningMutationStore(),
            ),
            planningWriteServiceProvider.overrideWithValue(
              _FakePlanningWriteService(),
            ),
            activePlanningContextProvider.overrideWithValue(
              const ActivePlanningReadContext(
                userId: 'user-1',
                organizationId: 'org-1',
              ),
            ),
            capabilityResolverProvider.overrideWith(
              (_) => CapabilityResolver(
                gateway: _PlanDetailStaticCapabilityGateway(
                  Capability.values.toSet(),
                ),
              ),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('plan-session-item-item-1')));
      await tester.pumpAndSettle();

      expect(find.text('Reader'), findsOneWidget);
    },
  );

  testWidgets('hides plan edit and session create buttons for read-only user', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildApp(
        planDetailValue: _editablePlanDetailFixture(),
        capabilityResolver: CapabilityResolver(
          gateway: _PlanDetailStaticCapabilityGateway({Capability.viewSongs}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip(AppStrings.planEditAction), findsNothing);
    expect(find.byTooltip(AppStrings.sessionCreateAction), findsNothing);
  });

  testWidgets('shows plan edit and session create buttons for org member', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildApp(
        planDetailValue: _editablePlanDetailFixture(),
        capabilityResolver: CapabilityResolver(
          gateway: _PlanDetailStaticCapabilityGateway(
            Capability.values.toSet(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip(AppStrings.planEditAction), findsOneWidget);
    expect(find.byTooltip(AppStrings.sessionCreateAction), findsOneWidget);
  });

  testWidgets('hides session delete button for read-only user', (tester) async {
    await tester.pumpWidget(
      buildApp(
        planDetailValue: _editablePlanDetailFixture(),
        capabilityResolver: CapabilityResolver(
          gateway: _PlanDetailStaticCapabilityGateway({Capability.viewSongs}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byTooltip('${AppStrings.sessionDeleteAction}: Warm-Up'),
      findsNothing,
    );
  });

  testWidgets('hides session item delete button for read-only user', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildApp(
        planDetailValue: _planDetailWithThreeItemsFixture(),
        capabilityResolver: CapabilityResolver(
          gateway: _PlanDetailStaticCapabilityGateway({Capability.viewSongs}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byTooltip('${AppStrings.sessionItemDeleteAction}: Alpha'),
      findsNothing,
    );
  });
}

PlanDetail _editablePlanDetailFixture() {
  return PlanDetail(
    plan: PlanSummary(
      id: 'plan-1',
      slug: 'team-rehearsal',
      name: 'Team Rehearsal',
      description: 'Fixture',
      scheduledFor: DateTime(2026, 4, 10, 18),
      updatedAt: DateTime(2026, 3, 31, 9),
    ),
    sessions: const [
      SessionSummary(
        id: 'session-1',
        slug: 'warm-up',
        name: 'Warm-Up',
        position: 10,
        items: [],
      ),
      SessionSummary(
        id: 'session-2',
        slug: 'closing',
        name: 'Closing',
        position: 20,
        items: [],
      ),
    ],
  );
}

PlanDetail _editablePlanDetailWithThreeSessionsFixture() {
  return PlanDetail(
    plan: PlanSummary(
      id: 'plan-1',
      slug: 'team-rehearsal',
      name: 'Team Rehearsal',
      description: 'Fixture',
      scheduledFor: DateTime(2026, 4, 10, 18),
      updatedAt: DateTime(2026, 3, 31, 9),
    ),
    sessions: const [
      SessionSummary(
        id: 'session-1',
        slug: 'warm-up',
        name: 'Warm-Up',
        position: 10,
        items: [],
      ),
      SessionSummary(
        id: 'session-2',
        slug: 'main-set',
        name: 'Main Set',
        position: 20,
        items: [],
      ),
      SessionSummary(
        id: 'session-3',
        slug: 'closing',
        name: 'Closing',
        position: 30,
        items: [],
      ),
    ],
  );
}

class _ReorderHandleHarness extends StatefulWidget {
  const _ReorderHandleHarness();

  @override
  State<_ReorderHandleHarness> createState() => _ReorderHandleHarnessState();
}

class _ReorderHandleHarnessState extends State<_ReorderHandleHarness> {
  final List<String> _items = ['Warm-Up', 'Closing'];

  void _reorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    setState(() {
      final moved = _items.removeAt(oldIndex);
      _items.insert(newIndex, moved);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: ReorderableListView.builder(
          buildDefaultDragHandles: false,
          itemCount: _items.length,
          onReorder: _reorder,
          itemBuilder: (context, index) {
            final label = _items[index];
            return ListTile(
              key: ValueKey(label),
              leading: ReorderableDelayedDragStartListener(
                index: index,
                child: SizedBox(
                  key: ValueKey('session-drag-handle-${label.toLowerCase()}'),
                  width: 40,
                  height: 40,
                  child: const Center(child: Icon(Icons.drag_indicator)),
                ),
              ),
              title: Text(label),
            );
          },
        ),
      ),
    );
  }
}

PlanDetail _planDetailWithItemsFixture() {
  return PlanDetail(
    plan: PlanSummary(
      id: 'plan-1',
      slug: 'team-rehearsal',
      name: 'Team Rehearsal',
      description: 'Fixture',
      scheduledFor: DateTime(2026, 4, 10, 18),
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
            song: SongSummary(id: 'song-1', slug: 'alpha', title: 'Alpha'),
          ),
          SessionItemSummary(
            id: 'item-2',
            position: 20,
            song: SongSummary(id: 'song-2', slug: 'beta', title: 'Beta'),
          ),
        ],
      ),
      SessionSummary(
        id: 'session-2',
        slug: 'closing',
        name: 'Closing',
        position: 20,
        items: [],
      ),
    ],
  );
}

PlanDetail _planDetailWithThreeItemsFixture() {
  return PlanDetail(
    plan: PlanSummary(
      id: 'plan-1',
      slug: 'team-rehearsal',
      name: 'Team Rehearsal',
      description: 'Fixture',
      scheduledFor: DateTime(2026, 4, 10, 18),
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
            song: SongSummary(id: 'song-1', slug: 'alpha', title: 'Alpha'),
          ),
          SessionItemSummary(
            id: 'item-2',
            position: 20,
            song: SongSummary(id: 'song-2', slug: 'beta', title: 'Beta'),
          ),
          SessionItemSummary(
            id: 'item-3',
            position: 30,
            song: SongSummary(id: 'song-3', slug: 'gamma', title: 'Gamma'),
          ),
        ],
      ),
      SessionSummary(
        id: 'session-2',
        slug: 'closing',
        name: 'Closing',
        position: 20,
        items: [],
      ),
    ],
  );
}

class _FakePlanningWriteService extends PlanningWriteService {
  _FakePlanningWriteService({
    this.addSongCompleter,
    this.addSongException,
    this.onReorderSessions,
    this.onReorderSessionItems,
    this.reorderSessionItemsCompleter,
  }) : super(
         _PlanDetailTestPlanningRepository(),
         mutationStore: _PlanDetailTestPlanningMutationStore(),
         activeContextReader: () async => const ActivePlanningReadContext(
           userId: 'user-1',
           organizationId: 'org-1',
         ),
       );

  final Completer<void>? addSongCompleter;
  final Completer<void>? reorderSessionItemsCompleter;
  final Object? addSongException;
  final Future<void> Function(SessionReorderDraft draft)? onReorderSessions;
  final Future<void> Function(SessionItemReorderDraft draft)?
  onReorderSessionItems;
  PlanEditDraft? editedDraft;
  SessionCreateDraft? createdSessionDraft;
  SessionRenameDraft? renamedSessionDraft;
  SessionDeleteDraft? deletedSessionDraft;
  SessionReorderDraft? reorderedSessionDraft;
  var reorderSessionsCallCount = 0;
  final List<SessionReorderDraft> reorderedSessionDrafts = [];
  SessionItemCreateSongDraft? createdSessionItemDraft;
  PlanningWriteContext? createdSongContext;
  SessionItemDeleteDraft? deletedSessionItemDraft;
  SessionItemReorderDraft? reorderedSessionItemDraft;
  var reorderSessionItemsCallCount = 0;
  final List<SessionItemReorderDraft> reorderedSessionItemDrafts = [];

  @override
  Future<void> editPlan({
    required PlanningWriteContext context,
    required PlanEditDraft draft,
  }) async {
    editedDraft = draft;
  }

  @override
  Future<void> createSession({
    required PlanningWriteContext context,
    required SessionCreateDraft draft,
  }) async {
    createdSessionDraft = draft;
  }

  @override
  Future<void> renameSession({
    required PlanningWriteContext context,
    required SessionRenameDraft draft,
  }) async {
    renamedSessionDraft = draft;
  }

  @override
  Future<void> deleteSession({
    required PlanningWriteContext context,
    required SessionDeleteDraft draft,
  }) async {
    deletedSessionDraft = draft;
  }

  @override
  Future<void> reorderSessions({
    required PlanningWriteContext context,
    required SessionReorderDraft draft,
  }) async {
    reorderSessionsCallCount += 1;
    reorderedSessionDraft = draft;
    reorderedSessionDrafts.add(draft);
    if (onReorderSessions != null) {
      await onReorderSessions!(draft);
      return;
    }
  }

  @override
  Future<void> addSongSessionItem({
    required PlanningWriteContext context,
    required SessionItemCreateSongDraft draft,
  }) async {
    createdSongContext = context;
    createdSessionItemDraft = draft;
    if (addSongException != null) {
      throw addSongException!;
    }
    if (addSongCompleter != null) {
      await addSongCompleter!.future;
    }
  }

  @override
  Future<void> deleteSessionItem({
    required PlanningWriteContext context,
    required SessionItemDeleteDraft draft,
  }) async {
    deletedSessionItemDraft = draft;
  }

  @override
  Future<void> reorderSessionItems({
    required PlanningWriteContext context,
    required SessionItemReorderDraft draft,
  }) async {
    reorderSessionItemsCallCount += 1;
    if (onReorderSessionItems != null) {
      await onReorderSessionItems!(draft);
      return;
    }
    if (reorderSessionItemsCompleter != null) {
      await reorderSessionItemsCompleter!.future;
    }
    reorderedSessionItemDraft = draft;
    reorderedSessionItemDrafts.add(draft);
  }
}

class _DelayedPlanningWriteService extends _FakePlanningWriteService {
  _DelayedPlanningWriteService({required this.onEditPlan});

  final Future<void> Function() onEditPlan;

  @override
  Future<void> editPlan({
    required PlanningWriteContext context,
    required PlanEditDraft draft,
  }) async {
    editedDraft = draft;
    await onEditPlan();
  }
}

class _PlanDetailTestPlanningRepository implements PlanningRepository {
  @override
  Future<PlanDetail> getPlanDetail(String planId) async =>
      _editablePlanDetailFixture();

  @override
  Future<PlanDetail?> getPlanDetailBySlug(String planSlug) async =>
      _editablePlanDetailFixture();

  @override
  Future<PlanSummary?> getPlanSummaryBySlug(String planSlug) async =>
      _editablePlanDetailFixture().plan;

  @override
  Future<List<PlanSummary>> listPlans() async => [
    _editablePlanDetailFixture().plan,
  ];
}

class _PlanDetailTestPlanningMutationStore implements PlanningMutationStore {
  @override
  Future<String> allocatePlanSlug({
    required String userId,
    required String organizationId,
    required String name,
  }) async => 'unused';

  @override
  Future<String> allocateSessionSlug({
    required String userId,
    required String organizationId,
    required String planId,
    required String name,
  }) async => 'unused';

  @override
  Future<void> clearMutation({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
  }) async {}

  @override
  Future<bool> hasUnsyncedMutations({required String userId}) async => false;

  @override
  Future<List<PlanningMutationRecord>> readAllMutations({
    required String userId,
    required String organizationId,
  }) async => const [];

  @override
  Future<PlanningMutationRecord?> readMutation({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
  }) async => null;

  @override
  Future<List<PlanningMutationRecord>> readPendingMutations({
    required String userId,
    required String organizationId,
  }) async => const [];

  @override
  Future<List<PlanningMutationRecord>> readActionableMutations({
    required String userId,
    required String organizationId,
  }) async => const [];

  @override
  Future<void> recordPlanCreate({
    required PlanningMutationContext context,
    required PlanningPlanCreateMutationDraft draft,
  }) async {}

  @override
  Future<void> recordPlanEdit({
    required PlanningMutationContext context,
    required PlanningPlanEditMutationDraft draft,
  }) async {}

  @override
  Future<void> recordSessionCreate({
    required PlanningMutationContext context,
    required PlanningSessionCreateMutationDraft draft,
  }) async {}

  @override
  Future<void> recordSessionDelete({
    required PlanningMutationContext context,
    required PlanningSessionDeleteMutationDraft draft,
  }) async {}

  @override
  Future<void> recordSessionItemCreateSong({
    required PlanningMutationContext context,
    required PlanningSessionItemCreateSongMutationDraft draft,
  }) async {}

  @override
  Future<void> recordSessionItemDelete({
    required PlanningMutationContext context,
    required PlanningSessionItemDeleteMutationDraft draft,
  }) async {}

  @override
  Future<void> recordSessionItemReorder({
    required PlanningMutationContext context,
    required PlanningSessionItemReorderMutationDraft draft,
  }) async {}

  @override
  Future<void> recordSessionReorder({
    required PlanningMutationContext context,
    required PlanningSessionReorderMutationDraft draft,
  }) async {}

  @override
  Future<void> recordSessionRename({
    required PlanningMutationContext context,
    required PlanningSessionRenameMutationDraft draft,
  }) async {}

  @override
  Future<void> retryMutation({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
  }) async {}

  @override
  Future<void> saveSyncAttemptResult({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
    required PlanningMutationSyncStatus syncStatus,
    PlanningMutationSyncErrorCode? errorCode,
    String? errorMessage,
  }) async {}
}

class _PlanDetailStaticCapabilityGateway implements CapabilityGateway {
  const _PlanDetailStaticCapabilityGateway(this._capabilities);

  final Set<Capability> _capabilities;

  @override
  Future<Set<Capability>> resolve(String organizationId) async => _capabilities;
}
