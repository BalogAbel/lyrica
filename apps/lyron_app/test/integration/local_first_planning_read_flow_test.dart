import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/planning/planning_remote_refresh_repository.dart';
import 'package:lyron_app/src/application/planning/planning_sync_controller.dart';
import 'package:lyron_app/src/application/planning/planning_sync_payload.dart';
import 'package:lyron_app/src/application/planning/planning_sync_state.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/infrastructure/config/supabase_config.dart';
import 'package:lyron_app/src/infrastructure/planning/supabase_planning_repository.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
const _demoOrganizationId = '11111111-1111-1111-1111-111111111111';
const _multiSessionPlanId = '44444444-4444-4444-4444-444444444442';

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
    'keeps planning reads locally available after the persistent planning cache is reopened offline',
    () async {
      final previousDontWarn =
          driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(() {
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = previousDontWarn;
      });

      final config = SupabaseConfig.fromEnvironment();
      final client = SupabaseClient(config.url, config.anonKey);
      final tempDir = await Directory.systemTemp.createTemp(
        'local-first-planning-read-flow',
      );
      final dbFile = File(p.join(tempDir.path, 'planning.sqlite'));
      var database = PlanningLocalDatabase.connect(
        NativeDatabase.createInBackground(dbFile),
      );
      var store = DriftPlanningLocalStore(database);

      addTearDown(() async {
        await client.auth.signOut();
        await client.dispose();
        await database.close();
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      await client.auth.signOut();
      await client.auth.signInWithPassword(
        email: 'demo@lyron.local',
        password: 'LyronDemo123!',
      );
      final userId = client.auth.currentSession!.user.id;

      final onlineController = PlanningSyncController(
        localStore: () => store,
        remoteRepository: () => SupabasePlanningRepository(client),
        authSessionReader: _currentSessionReader(client),
      );

      await onlineController.handleActiveContextChanged(
        ActivePlanningReadContext(
          userId: userId,
          organizationId: _demoOrganizationId,
        ),
      );

      expect(onlineController.state.refreshStatus, PlanningRefreshStatus.idle);
      expect(onlineController.state.hasLocalPlanningData, isTrue);

      await database.close();
      database = PlanningLocalDatabase.connect(
        NativeDatabase.createInBackground(dbFile),
      );
      store = DriftPlanningLocalStore(database);

      final localRepository = PlanningLocalReadRepository(
        store: store,
        contextReader: () async => ActivePlanningReadContext(
          userId: userId,
          organizationId: _demoOrganizationId,
        ),
      );

      final cachedPlans = await localRepository.listPlans();
      expect(
        cachedPlans.map((plan) => plan.name).toList(growable: false),
        const ['Sunday Morning', 'Evening Gathering', 'Team Rehearsal'],
      );

      final offlineController = PlanningSyncController(
        localStore: () => store,
        remoteRepository: () =>
            _ThrowingPlanningRemoteRepository(const SocketException('offline')),
        authSessionReader: _currentSessionReader(client),
      );
      await offlineController.handleActiveContextChanged(
        ActivePlanningReadContext(
          userId: userId,
          organizationId: _demoOrganizationId,
        ),
      );

      expect(
        offlineController.state.refreshStatus,
        PlanningRefreshStatus.failed,
      );
      expect(offlineController.state.hasLocalPlanningData, isTrue);

      final detail = await localRepository.getPlanDetail(_multiSessionPlanId);
      expect(detail.plan.name, 'Team Rehearsal');
      expect(
        detail.sessions.map((session) => session.name).toList(growable: false),
        const ['Warm-Up', 'Run-Through'],
      );
      expect(
        detail.sessions.last.items
            .map((item) => item.id)
            .toList(growable: false),
        const [
          '66666666-6666-6666-6666-666666666664',
          '66666666-6666-6666-6666-666666666665',
        ],
      );
    },
    skip: _supabaseUrl.isEmpty || _supabaseAnonKey.isEmpty,
  );

  test(
    'explicit sign-out removes cached authenticated planning access immediately',
    () async {
      final config = SupabaseConfig.fromEnvironment();
      final client = SupabaseClient(config.url, config.anonKey);
      final database = PlanningLocalDatabase.inMemory();
      final store = DriftPlanningLocalStore(database);

      addTearDown(() async {
        await client.auth.signOut();
        await client.dispose();
        await database.close();
      });

      await client.auth.signOut();
      await client.auth.signInWithPassword(
        email: 'demo@lyron.local',
        password: 'LyronDemo123!',
      );
      final userId = client.auth.currentSession!.user.id;

      final controller = PlanningSyncController(
        localStore: () => store,
        remoteRepository: () => SupabasePlanningRepository(client),
        authSessionReader: _currentSessionReader(client),
      );

      await controller.handleActiveContextChanged(
        ActivePlanningReadContext(
          userId: userId,
          organizationId: _demoOrganizationId,
        ),
      );
      await controller.handleExplicitSignOut();
      await client.auth.signOut();

      expect(
        await store.readPlanSummaries(
          userId: userId,
          organizationId: _demoOrganizationId,
        ),
        isEmpty,
      );
    },
    skip: _supabaseUrl.isEmpty || _supabaseAnonKey.isEmpty,
  );
}

PlanningAuthSessionReader _currentSessionReader(SupabaseClient client) {
  return () {
    final session = client.auth.currentSession;
    final email = session?.user.email;
    if (session == null || email == null || email.isEmpty) {
      return null;
    }

    return AppAuthSession(userId: session.user.id, email: email);
  };
}

class _ThrowingPlanningRemoteRepository
    implements PlanningRemoteRefreshRepository {
  const _ThrowingPlanningRemoteRepository(this._error);

  final Object _error;

  @override
  Future<PlanningSyncPayload> fetchPlanningSyncPayload({
    required String organizationId,
  }) async {
    throw _error;
  }
}

class _PassthroughHttpOverrides extends HttpOverrides {}
