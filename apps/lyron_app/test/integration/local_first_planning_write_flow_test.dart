import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/drift_planning_mutation_store.dart';
import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/planning/planning_remote_refresh_repository.dart';
import 'package:lyron_app/src/application/planning/planning_sync_controller.dart';
import 'package:lyron_app/src/application/planning/planning_sync_payload.dart';
import 'package:lyron_app/src/application/planning/planning_write_service.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'local-first planning writes survive reopen and explicit sign-out clears both projection and mutations',
    () async {
      final previousDontWarn =
          driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(() {
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = previousDontWarn;
      });

      const context = ActivePlanningReadContext(
        userId: 'user-1',
        organizationId: 'org-1',
      );
      final tempDir = await Directory.systemTemp.createTemp(
        'local-first-planning-write-flow',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final dbFile = File(p.join(tempDir.path, 'planning.sqlite'));

      var database = PlanningLocalDatabase.connect(
        NativeDatabase.createInBackground(dbFile),
      );
      var localStore = DriftPlanningLocalStore(database);
      var mutationStore = DriftPlanningMutationStore(
        database: database,
        localStore: localStore,
      );
      var repository = PlanningLocalReadRepository(
        store: localStore,
        mutationStore: mutationStore,
        contextReader: () async => context,
      );
      var service = PlanningWriteService(
        repository,
        mutationStore: mutationStore,
        activeContextReader: () async => context,
      );

      final createdPlan = await service.createPlan(
        context: PlanningWriteContext(
          userId: context.userId,
          organizationId: context.organizationId,
        ),
        draft: const PlanCreateDraft(
          name: 'Weekend Service',
          description: 'Prepared offline',
        ),
      );
      await service.createSession(
        context: PlanningWriteContext(
          userId: context.userId,
          organizationId: context.organizationId,
        ),
        draft: SessionCreateDraft(
          planId: createdPlan.aggregateId,
          name: 'Warm-Up',
        ),
      );
      var detail = await repository.getPlanDetail(createdPlan.aggregateId);
      final createdSessionId = detail.sessions.single.id;

      await service.renameSession(
        context: PlanningWriteContext(
          userId: context.userId,
          organizationId: context.organizationId,
        ),
        draft: SessionRenameDraft(
          sessionId: createdSessionId,
          planId: createdPlan.aggregateId,
          name: 'Warm-Up Updated',
        ),
      );

      expect((await repository.listPlans()).single.name, 'Weekend Service');
      expect(
        (await repository.getPlanDetail(
          createdPlan.aggregateId,
        )).sessions.single.name,
        'Warm-Up Updated',
      );

      await database.close();
      database = PlanningLocalDatabase.connect(
        NativeDatabase.createInBackground(dbFile),
      );
      localStore = DriftPlanningLocalStore(database);
      mutationStore = DriftPlanningMutationStore(
        database: database,
        localStore: localStore,
      );
      repository = PlanningLocalReadRepository(
        store: localStore,
        mutationStore: mutationStore,
        contextReader: () async => context,
      );

      detail = await repository.getPlanDetail(createdPlan.aggregateId);
      expect(detail.plan.slug, 'weekend-service');
      expect(detail.sessions.single.name, 'Warm-Up Updated');
      expect(
        await mutationStore.hasUnsyncedMutations(userId: context.userId),
        isTrue,
      );

      final refreshController = PlanningSyncController(
        localStore: () => localStore,
        remoteRepository: () => const _EmptyPlanningRemoteRepository(),
        authSessionReader: () =>
            AppAuthSession(userId: context.userId, email: 'demo@lyron.local'),
      );
      await refreshController.handleActiveContextChanged(context);

      expect(
        await mutationStore.hasUnsyncedMutations(userId: context.userId),
        isTrue,
      );
      expect(
        (await repository.getPlanDetail(
          createdPlan.aggregateId,
        )).sessions.single.name,
        'Warm-Up Updated',
      );

      final syncController = PlanningSyncController(
        localStore: () => localStore,
        remoteRepository: () => const _EmptyPlanningRemoteRepository(),
        authSessionReader: () =>
            AppAuthSession(userId: context.userId, email: 'demo@lyron.local'),
      );
      await syncController.handleActiveContextChanged(context, refresh: false);
      await syncController.handleExplicitSignOut();

      expect(
        await mutationStore.hasUnsyncedMutations(userId: context.userId),
        isFalse,
      );
      expect(await repository.listPlans(), isEmpty);

      await database.close();
    },
  );
}

class _EmptyPlanningRemoteRepository
    implements PlanningRemoteRefreshRepository {
  const _EmptyPlanningRemoteRepository();

  @override
  Future<PlanningSyncPayload> fetchPlanningSyncPayload({
    required String organizationId,
  }) async {
    return const PlanningSyncPayload(plans: [], sessions: [], items: []);
  }
}
