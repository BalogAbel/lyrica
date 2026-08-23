import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/last_known_identity.dart';
import 'package:lyron_app/src/application/planning/drift_planning_mutation_store.dart';
import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_reconciler.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_controller.dart';
import 'package:lyron_app/src/application/planning/planning_sync_controller.dart';
import 'package:lyron_app/src/application/planning/planning_write_service.dart';
import 'package:lyron_app/src/application/storage/local_data_lifecycle.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/infrastructure/config/supabase_config.dart';
import 'package:lyron_app/src/infrastructure/planning/supabase_planning_mutation_repository.dart';
import 'package:lyron_app/src/infrastructure/planning/supabase_planning_repository.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_store.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/drift_relaunch.dart';
import '../support/drift_test_setup.dart';

// Trivial LocalDataLifecycle wrapping the test's real planning store, for a
// test that only exercises planning sync -- song catalog/identity/events
// deps are never invoked by this flow.
LocalDataLifecycle _lifecycleFor(PlanningLocalStore store) {
  return LocalDataLifecycle(
    songCatalogStore: _NoopSongCatalogStore(),
    planningLocalStore: store,
    identityStore: _NoopLastKnownIdentityStore(),
    noteLastKnownIdentity: (_) {},
    eventsRecorder: _NoopLocalDataEventsRecorder(),
  );
}

class _NoopSongCatalogStore implements SongCatalogStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoopLastKnownIdentityStore implements LastKnownIdentityStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoopLocalDataEventsRecorder implements LocalDataEventsRecorder {
  @override
  Future<void> recordPurge({
    required PurgeTarget target,
    required PurgeReason reason,
    String? userId,
    int? rowsAffected,
  }) async {}

  @override
  Future<void> recordEviction({
    required String target,
    String? userId,
    int? rowsAffected,
  }) async {}

  @override
  Future<void> recordRejectedEmptySnapshot({
    required String userId,
    required String organizationId,
  }) async {}

  @override
  Future<void> recordStorageWriteFailure({String? userId}) async {}

  @override
  Future<void> recordMembershipRevocationMarked({required String userId}) async {}

  @override
  Future<void> recordMembershipRevocationCleared({required String userId}) async {}
}

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

// Seeded demo plan from the local stack fixtures (see
// plan_and_session_flow_test.dart): a multi-session plan owned by the
// visible demo organization, safe to edit and re-edit across test runs.
const _planIdToEdit = '44444444-4444-4444-4444-444444444442';
const _visibleOrganizationId = '11111111-1111-1111-1111-111111111111';

void main() {
  late HttpOverrides? originalHttpOverrides;

  setUpAll(() {
    originalHttpOverrides = HttpOverrides.current;
    HttpOverrides.global = _PassthroughHttpOverrides();
  });

  tearDownAll(() {
    HttpOverrides.global = originalHttpOverrides;
  });

  test(
    'offline plan edit survives relaunch and converges after sync (LF-T1)',
    () async {
      await runWithSuppressedDriftMultipleDatabaseWarnings(() async {
        final config = SupabaseConfig.fromEnvironment();
        final client = SupabaseClient(config.url, config.anonKey);
        final dbFile = await createRelaunchDbFile(
          'offline-edit-relaunch-sync-flow',
        );

        // Track the currently-open database so a mid-test failure still
        // closes the live connection (freeing the sqlite file) before the
        // temp dir is removed, instead of relying on the explicit close()
        // calls below.
        PlanningLocalDatabase? openDb;
        addTearDown(() async {
          await openDb?.close();
          await client.auth.signOut();
          await client.dispose();
          if (await dbFile.parent.exists()) {
            await dbFile.parent.delete(recursive: true);
          }
        });

        // 1. Authenticate against the local stack and resolve the active
        // planning context (mirrors plan_and_session_flow_test.dart).
        await client.auth.signOut();
        await client.auth.signInWithPassword(
          email: 'demo@lyron.local',
          password: 'LyronDemo123!',
        );
        final userId = client.auth.currentSession!.user.id;
        final context = ActivePlanningReadContext(
          userId: userId,
          organizationId: _visibleOrganizationId,
        );

        var database = PlanningLocalDatabase.connect(
          NativeDatabase.createInBackground(dbFile),
        );
        openDb = database;
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

        // Seed the local projection from the real backend so there is a
        // base plan present to edit offline (the merged read overlays
        // pending mutations on top of this synced snapshot).
        final seedRepository = SupabasePlanningRepository(client);
        final seedDetail = await seedRepository.getPlanDetail(_planIdToEdit);
        await localStore.upsertSyncedPlan(
          userId: context.userId,
          organizationId: context.organizationId,
          refreshedAt: DateTime.now().toUtc(),
          plan: CachedPlanRecord(
            id: seedDetail.plan.id,
            slug: seedDetail.plan.slug,
            name: seedDetail.plan.name,
            description: seedDetail.plan.description,
            scheduledFor: seedDetail.plan.scheduledFor,
            updatedAt: seedDetail.plan.updatedAt,
            version: seedDetail.plan.version,
          ),
        );

        final writeService = PlanningWriteService(
          repository,
          mutationStore: mutationStore,
          activeContextReader: () async => context,
        );

        // 2. Simulate offline: edit the plan while the write path never
        // touches the network (PlanningWriteService only writes to the
        // local mutation store). This records a pending plan-edit
        // mutation in the local DB.
        const editedName = 'Team Rehearsal (offline edit)';
        await writeService.editPlan(
          context: PlanningWriteContext(
            userId: context.userId,
            organizationId: context.organizationId,
          ),
          draft: PlanEditDraft(planId: _planIdToEdit, name: editedName),
        );

        expect(
          await mutationStore.hasUnsyncedMutations(userId: context.userId),
          isTrue,
        );
        var detail = await repository.getPlanDetail(_planIdToEdit);
        expect(detail.plan.name, editedName);

        // 3. Close the planning DB and reopen from the same file (relaunch).
        await database.close();
        openDb = null;
        database = PlanningLocalDatabase.connect(openRelaunchExecutor(dbFile));
        openDb = database;
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

        detail = await repository.getPlanDetail(_planIdToEdit);
        expect(
          detail.plan.name,
          editedName,
          reason: 'offline edit must survive DB close + reopen (relaunch)',
        );
        expect(
          await mutationStore.hasUnsyncedMutations(userId: context.userId),
          isTrue,
        );

        // 4. Go online: run syncPendingMutations against the real backend.
        final remoteMutationRepository = SupabasePlanningMutationRepository(
          client,
        );
        final remoteRefreshRepository = SupabasePlanningRepository(client);
        final syncController = PlanningSyncController(
          localStore: () => localStore,
          localDataLifecycle: _lifecycleFor(localStore),
          remoteRepository: () => remoteRefreshRepository,
          authSessionReader: () =>
              AppAuthSession(userId: context.userId, email: 'demo@lyron.local'),
        );
        final mutationSyncController = PlanningMutationSyncController(
          mutationStore: () => mutationStore,
          remoteRepository: () => remoteMutationRepository,
          refreshPlanning: () async {
            await syncController.handleActiveContextChanged(
              context,
              refresh: false,
            );
            return syncController.refreshPlanning();
          },
          shouldReconcileAcceptedMutation: (_) async => true,
          reconcileAcceptedMutation: PlanningMutationReconciler(
            localStore: () => localStore,
          ).reconcile,
        );

        await mutationSyncController.syncPendingMutations(context);

        // 5. Assert convergence: backend reflects the edit AND the local
        // pending mutation is cleared.
        expect(
          await mutationStore.hasUnsyncedMutations(userId: context.userId),
          isFalse,
          reason: 'pending mutation must be cleared once synced',
        );

        final backendDetail = await SupabasePlanningRepository(
          client,
        ).getPlanDetail(_planIdToEdit);
        expect(backendDetail.plan.name, editedName);

        final convergedDetail = await repository.getPlanDetail(_planIdToEdit);
        expect(convergedDetail.plan.name, editedName);

        await database.close();
        openDb = null;
      });
    },
    skip: _supabaseUrl.isEmpty || _supabaseAnonKey.isEmpty,
  );
}

class _PassthroughHttpOverrides extends HttpOverrides {}
