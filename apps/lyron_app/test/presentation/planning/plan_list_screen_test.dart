import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_controller.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/application/planning/planning_write_service.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/domain/planning/plan_detail.dart';
import 'package:lyron_app/src/domain/planning/plan_summary.dart';
import 'package:lyron_app/src/domain/planning/planning_repository.dart';
import 'package:lyron_app/src/presentation/planning/plan_list_screen.dart';
import 'package:lyron_app/src/presentation/planning/planning_providers.dart';
import 'package:lyron_app/src/router/app_routes.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

void main() {
  final originalDontWarnAboutMultipleDatabases =
      driftRuntimeOptions.dontWarnAboutMultipleDatabases;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases =
        originalDontWarnAboutMultipleDatabases;
  });

  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildApp({
    Object? listPlansValue = const <PlanSummary>[],
    Future<List<PlanningMutationRecord>> Function()? loadMutationEntries,
    PlanningWriteService? writeService,
    PlanningMutationSyncController? mutationSyncController,
    bool? hasUnsyncedPlanningMutations,
  }) {
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
            final planSlug = state.pathParameters['planSlug']!;
            return Material(child: Text('plan-detail:$planSlug'));
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
        if (loadMutationEntries != null)
          planningMutationEntriesProvider.overrideWith((ref) {
            return loadMutationEntries();
          }),
        if (writeService != null)
          planningWriteServiceProvider.overrideWithValue(writeService),
        if (mutationSyncController != null)
          planningMutationSyncControllerProvider.overrideWithValue(
            mutationSyncController,
          ),
        if (hasUnsyncedPlanningMutations != null)
          hasUnsyncedPlanningMutationsProvider.overrideWith(
            (ref) async => hasUnsyncedPlanningMutations,
          ),
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

  testWidgets('renders visible plans in the order provided by the list', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildApp(
        listPlansValue: [
          PlanSummary(
            id: 'plan-2',
            slug: 'zulu-rehearsal',
            name: 'Zulu Rehearsal',
            description: 'Multi-session rehearsal fixture',
            scheduledFor: null,
            updatedAt: DateTime(2026, 3, 31, 12),
          ),
          PlanSummary(
            id: 'plan-1',
            slug: 'alpha-morning',
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
            slug: 'sunday-morning',
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

    expect(find.text('plan-detail:sunday-morning'), findsOneWidget);
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

  testWidgets('shows the create-plan affordance', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.planCreateAction), findsOneWidget);
  });

  testWidgets(
    'creates a plan locally and navigates to the reconciled detail route',
    (tester) async {
      final writeService = _FakePlanningWriteService(
        createdPlan: PlanningMutationRecord(
          aggregateId: 'plan-local-1',
          organizationId: 'org-1',
          slug: 'weekend-service',
          name: 'Weekend Service',
          description: 'Local draft',
          kind: PlanningMutationKind.planCreate,
          syncStatus: PlanningMutationSyncStatus.pending,
          orderKey: 1,
          updatedAt: DateTime.utc(2026),
        ),
      );
      var listReadCount = 0;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            planningPlanListProvider.overrideWith((ref) async {
              listReadCount += 1;
              if (listReadCount == 1) {
                return const <PlanSummary>[];
              }
              return [
                PlanSummary(
                  id: 'plan-local-1',
                  slug: 'weekend-service-2',
                  name: 'Weekend Service',
                  description: 'Local draft',
                  scheduledFor: null,
                  updatedAt: DateTime(2026, 4, 10),
                ),
              ];
            }),
            planningMutationEntriesProvider.overrideWith(
              (ref) async => const [],
            ),
            planningWriteServiceProvider.overrideWithValue(writeService),
            activePlanningContextProvider.overrideWithValue(
              const ActivePlanningReadContext(
                userId: 'user-1',
                organizationId: 'org-1',
              ),
            ),
          ],
          child: MaterialApp.router(
            routerConfig: GoRouter(
              initialLocation: AppRoutes.planList.path,
              routes: [
                GoRoute(
                  path: AppRoutes.planList.path,
                  builder: (context, state) => const PlanListScreen(),
                ),
                GoRoute(
                  path: AppRoutes.planDetail.path,
                  builder: (context, state) {
                    final planSlug = state.pathParameters['planSlug']!;
                    return Material(child: Text('plan-detail:$planSlug'));
                  },
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(AppStrings.planCreateAction));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('plan-editor-name')),
        'Weekend Service',
      );
      await tester.enterText(
        find.byKey(const ValueKey('plan-editor-description')),
        'Local draft',
      );
      await tester.tap(find.text(AppStrings.planSaveAction));
      await tester.pumpAndSettle();

      expect(writeService.createdDraft?.name, 'Weekend Service');
      expect(find.text('plan-detail:weekend-service-2'), findsOneWidget);
    },
  );

  testWidgets('shows failed planning mutations and retries them explicitly', (
    tester,
  ) async {
    final syncController = _FakePlanningMutationSyncController();

    await tester.pumpWidget(
      buildApp(
        mutationSyncController: syncController,
        loadMutationEntries: () async => [
          PlanningMutationRecord(
            aggregateId: 'plan-1',
            organizationId: 'org-1',
            name: 'Weekend Service',
            kind: PlanningMutationKind.planEdit,
            syncStatus: PlanningMutationSyncStatus.conflict,
            errorCode: PlanningMutationSyncErrorCode.conflict,
            errorMessage: 'base_version_conflict',
            orderKey: 1,
            updatedAt: DateTime.utc(2026),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Weekend Service'), findsOneWidget);
    expect(find.text(AppStrings.planConflictMessage), findsOneWidget);

    await tester.tap(find.text(AppStrings.retryAction));
    await tester.pumpAndSettle();

    expect(syncController.retriedAggregateIds, ['plan-1']);
  });

  testWidgets('shows a validation error for invalid scheduled-for input', (
    tester,
  ) async {
    final writeService = _FakePlanningWriteService(
      createdPlan: PlanningMutationRecord(
        aggregateId: 'plan-local-1',
        organizationId: 'org-1',
        slug: 'weekend-service',
        name: 'Weekend Service',
        kind: PlanningMutationKind.planCreate,
        syncStatus: PlanningMutationSyncStatus.pending,
        orderKey: 1,
        updatedAt: DateTime.utc(2026),
      ),
    );

    await tester.pumpWidget(buildApp(writeService: writeService));
    await tester.pumpAndSettle();

    await tester.tap(find.text(AppStrings.planCreateAction));
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
    expect(writeService.createdDraft, isNull);
  });
}

class _FakePlanningWriteService extends PlanningWriteService {
  _FakePlanningWriteService({required this.createdPlan})
    : super(
        _FakePlanningRepository(),
        mutationStore: _FakePlanningMutationStore(),
        activeContextReader: () async => const ActivePlanningReadContext(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
      );

  final PlanningMutationRecord createdPlan;
  PlanCreateDraft? createdDraft;

  @override
  Future<PlanningMutationRecord> createPlan({
    required PlanningWriteContext context,
    required PlanCreateDraft draft,
  }) async {
    createdDraft = draft;
    return createdPlan;
  }
}

class _FakePlanningMutationSyncController
    extends PlanningMutationSyncController {
  _FakePlanningMutationSyncController()
    : super(
        mutationStore: () => _FakePlanningMutationStore(),
        remoteRepository: () => _FakePlanningMutationRemoteRepository(),
        refreshPlanning: () async => true,
        shouldReconcileAcceptedMutation: (_) async => true,
        reconcileAcceptedMutation: (_, _) async {},
      );

  final List<String> retriedAggregateIds = [];

  @override
  Future<void> retryMutation(
    ActivePlanningReadContext context, {
    required String aggregateType,
    required String aggregateId,
  }) async {
    retriedAggregateIds.add(aggregateId);
  }
}

class _FakePlanningRepository implements PlanningRepository {
  @override
  Future<PlanDetail> getPlanDetail(String planId) async =>
      throw UnimplementedError();

  @override
  Future<PlanDetail?> getPlanDetailBySlug(String planSlug) async =>
      throw UnimplementedError();

  @override
  Future<PlanSummary?> getPlanSummaryBySlug(String planSlug) async =>
      throw UnimplementedError();

  @override
  Future<List<PlanSummary>> listPlans() async => const [];
}

class _FakePlanningMutationStore implements PlanningMutationStore {
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

class _FakePlanningMutationRemoteRepository
    implements PlanningMutationRemoteRepository {
  @override
  Future<PlanningMutationRecord> syncMutation({
    required String organizationId,
    required PlanningMutationRecord record,
  }) async => record;
}
