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
import 'package:lyron_app/src/domain/song/song_summary.dart';
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
        listVisibleSongs: ({required userId, required organizationId}) async =>
            const [
              SongSummary(id: 'song-1', slug: 'alpha', title: 'Alpha'),
              SongSummary(id: 'song-2', slug: 'beta', title: 'Beta'),
            ],
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
      await service.createSession(
        context: PlanningWriteContext(
          userId: context.userId,
          organizationId: context.organizationId,
        ),
        draft: SessionCreateDraft(
          planId: createdPlan.aggregateId,
          name: 'Message',
        ),
      );
      detail = await repository.getPlanDetail(createdPlan.aggregateId);
      final secondSessionId = detail.sessions
          .firstWhere((session) => session.id != createdSessionId)
          .id;

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
      await service.reorderSessions(
        context: PlanningWriteContext(
          userId: context.userId,
          organizationId: context.organizationId,
        ),
        draft: SessionReorderDraft(
          planId: createdPlan.aggregateId,
          orderedSessionIds: [secondSessionId, createdSessionId],
        ),
      );
      await service.addSongSessionItem(
        context: PlanningWriteContext(
          userId: context.userId,
          organizationId: context.organizationId,
        ),
        draft: SessionItemCreateSongDraft(
          sessionId: createdSessionId,
          planId: createdPlan.aggregateId,
          songId: 'song-1',
        ),
      );
      await service.addSongSessionItem(
        context: PlanningWriteContext(
          userId: context.userId,
          organizationId: context.organizationId,
        ),
        draft: SessionItemCreateSongDraft(
          sessionId: createdSessionId,
          planId: createdPlan.aggregateId,
          songId: 'song-2',
        ),
      );
      detail = await repository.getPlanDetail(createdPlan.aggregateId);
      final itemIds = detail.sessions
          .firstWhere((session) => session.id == createdSessionId)
          .items
          .map((item) => item.id)
          .toList(growable: false);
      await service.reorderSessionItems(
        context: PlanningWriteContext(
          userId: context.userId,
          organizationId: context.organizationId,
        ),
        draft: SessionItemReorderDraft(
          sessionId: createdSessionId,
          planId: createdPlan.aggregateId,
          orderedSessionItemIds: [itemIds[1], itemIds[0]],
        ),
      );
      await service.deleteSessionItem(
        context: PlanningWriteContext(
          userId: context.userId,
          organizationId: context.organizationId,
        ),
        draft: SessionItemDeleteDraft(
          sessionItemId: itemIds[0],
          sessionId: createdSessionId,
          planId: createdPlan.aggregateId,
        ),
      );

      expect((await repository.listPlans()).single.name, 'Weekend Service');
      detail = await repository.getPlanDetail(createdPlan.aggregateId);
      expect(
        detail.sessions.map((session) => session.id),
        orderedEquals([secondSessionId, createdSessionId]),
      );
      expect(detail.sessions.last.name, 'Warm-Up Updated');
      expect(
        detail.sessions.last.items.map((item) => item.song.title),
        orderedEquals(const ['Beta']),
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
      expect(
        detail.sessions.map((session) => session.id),
        orderedEquals([secondSessionId, createdSessionId]),
      );
      expect(detail.sessions.last.name, 'Warm-Up Updated');
      expect(
        detail.sessions.last.items.map((item) => item.song.title),
        orderedEquals(const ['Beta']),
      );
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
        )).sessions.last.name,
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
