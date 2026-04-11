import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_controller.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/application/planning/planning_write_service.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/song_library/catalog_connection_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_refresh_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_session_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_snapshot_state.dart';
import 'package:lyron_app/src/application/song_library/song_reader_result.dart';
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
import 'package:lyron_app/src/router/app_routes.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildApp({
    Object? planDetailValue,
    PlanningWriteService? writeService,
    PlanningMutationSyncController? mutationSyncController,
    Future<List<PlanningMutationRecord>> Function()? loadMutationEntries,
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
          if (planDetailValue is Future<PlanDetail>) {
            return planDetailValue;
          }

          if (planDetailValue is Object && planDetailValue is! PlanDetail) {
            return Future<PlanDetail>.error(planDetailValue);
          }

          return Future.value(planDetailValue as PlanDetail);
        }),
        if (writeService != null)
          planningWriteServiceProvider.overrideWithValue(writeService),
        if (mutationSyncController != null)
          planningMutationSyncControllerProvider.overrideWithValue(
            mutationSyncController,
          ),
        if (loadMutationEntries != null)
          planningMutationEntriesProvider.overrideWith((ref) {
            return loadMutationEntries();
          }),
        activePlanningContextProvider.overrideWithValue(
          const ActivePlanningReadContext(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
        ),
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

    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
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

    await tester.tap(find.text(AppStrings.planEditAction));
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

    await tester.tap(find.text(AppStrings.sessionCreateAction));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('session-editor-name')),
      'Closing',
    );
    await tester.tap(find.text(AppStrings.planSaveAction));
    await tester.pumpAndSettle();

    expect(writeService.createdSessionDraft?.planId, 'plan-1');
    expect(writeService.createdSessionDraft?.name, 'Closing');

    await tester.tap(
      find.byTooltip('${AppStrings.sessionRenameAction}: Warm-Up'),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('session-editor-name')),
      'Warm-Up Updated',
    );
    await tester.tap(find.text(AppStrings.planSaveAction));
    await tester.pumpAndSettle();

    expect(writeService.renamedSessionDraft?.sessionId, 'session-1');
    expect(writeService.renamedSessionDraft?.name, 'Warm-Up Updated');
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

  testWidgets('shows failed planning mutations and retries them from detail', (
    tester,
  ) async {
    final syncController = _FakePlanningMutationSyncController();

    await tester.pumpWidget(
      buildApp(
        planDetailValue: _editablePlanDetailFixture(),
        mutationSyncController: syncController,
        loadMutationEntries: () async => [
          PlanningMutationRecord(
            aggregateId: 'plan-1',
            organizationId: 'org-1',
            name: 'Team Rehearsal',
            kind: PlanningMutationKind.planEdit,
            syncStatus: PlanningMutationSyncStatus.conflict,
            errorCode: PlanningMutationSyncErrorCode.conflict,
            errorMessage: 'base_version_conflict',
            orderKey: 2,
            updatedAt: DateTime.utc(2026),
          ),
          PlanningMutationRecord(
            aggregateId: 'plan-2',
            organizationId: 'org-1',
            name: 'Other Plan',
            kind: PlanningMutationKind.planEdit,
            syncStatus: PlanningMutationSyncStatus.failedAuthorization,
            errorCode: PlanningMutationSyncErrorCode.authorizationDenied,
            orderKey: 3,
            updatedAt: DateTime.utc(2026),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.planConflictMessage), findsOneWidget);
    expect(find.text('Other Plan'), findsNothing);

    await tester.tap(find.text(AppStrings.retryAction));
    await tester.pumpAndSettle();

    expect(syncController.retriedAggregateIds, ['plan-1']);
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

    await tester.tap(find.text(AppStrings.planEditAction));
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

class _FakePlanningWriteService extends PlanningWriteService {
  _FakePlanningWriteService()
    : super(
        _PlanDetailTestPlanningRepository(),
        mutationStore: _PlanDetailTestPlanningMutationStore(),
        activeContextReader: () async => const ActivePlanningReadContext(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
      );

  PlanEditDraft? editedDraft;
  SessionCreateDraft? createdSessionDraft;
  SessionRenameDraft? renamedSessionDraft;
  SessionDeleteDraft? deletedSessionDraft;

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
}

class _FakePlanningMutationSyncController
    extends PlanningMutationSyncController {
  _FakePlanningMutationSyncController()
    : super(
        mutationStore: () => _PlanDetailTestPlanningMutationStore(),
        remoteRepository: () =>
            _PlanDetailTestPlanningMutationRemoteRepository(),
        refreshPlanning: () async => true,
        reconcileAcceptedMutation: (_, _) async {},
      );

  final List<String> retriedAggregateIds = [];

  @override
  Future<void> retryMutation(
    ActivePlanningReadContext context, {
    required String aggregateId,
  }) async {
    retriedAggregateIds.add(aggregateId);
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
    required String aggregateId,
  }) async => null;

  @override
  Future<List<PlanningMutationRecord>> readPendingMutations({
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
  Future<void> recordSessionRename({
    required PlanningMutationContext context,
    required PlanningSessionRenameMutationDraft draft,
  }) async {}

  @override
  Future<void> retryMutation({
    required String userId,
    required String organizationId,
    required String aggregateId,
  }) async {}

  @override
  Future<void> saveSyncAttemptResult({
    required String userId,
    required String organizationId,
    required String aggregateId,
    required PlanningMutationSyncStatus syncStatus,
    PlanningMutationSyncErrorCode? errorCode,
    String? errorMessage,
  }) async {}
}

class _PlanDetailTestPlanningMutationRemoteRepository
    implements PlanningMutationRemoteRepository {
  @override
  Future<PlanningMutationRecord> syncMutation({
    required String organizationId,
    required PlanningMutationRecord record,
  }) async => record;
}
