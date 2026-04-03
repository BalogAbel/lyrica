import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/app_auth_controller.dart';
import 'package:lyron_app/src/application/auth/auth_repository.dart';
import 'package:lyron_app/src/application/planning/active_planning_context_controller.dart';
import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/planning/planning_remote_refresh_repository.dart';
import 'package:lyron_app/src/application/planning/planning_sync_controller.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/song_library/active_catalog_context.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/planning/planning_repository.dart';
import 'package:lyron_app/src/infrastructure/planning/supabase_planning_repository.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('allows overriding the shared Supabase client provider', () {
    final client = SupabaseClient('http://127.0.0.1:54321', 'anon-key');
    final container = ProviderContainer(
      overrides: [supabaseClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);

    expect(container.read(supabaseClientProvider), same(client));
  });

  test('selects a stable active organization id from RPC results', () {
    expect(
      selectActiveOrganizationId(const ['org-b', 'org-a', 'org-c']),
      'org-a',
    );
    expect(selectActiveOrganizationId(const []), isNull);
    expect(selectActiveOrganizationId('unexpected'), isNull);
  });

  test('wires PlanningRepository through the shared provider graph', () {
    final client = SupabaseClient('http://127.0.0.1:54321', 'anon-key');
    final database = PlanningLocalDatabase.inMemory();
    final container = ProviderContainer(
      overrides: [
        supabaseClientProvider.overrideWithValue(client),
        planningLocalDatabaseProvider.overrideWithValue(database),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await database.close();
    });

    expect(
      container.read(planningRepositoryProvider),
      isA<PlanningRepository>().having(
        (repository) => repository,
        'runtime type',
        isA<PlanningLocalReadRepository>(),
      ),
    );
  });

  test('wires planning local-first seams through the provider graph', () {
    final client = SupabaseClient('http://127.0.0.1:54321', 'anon-key');
    final database = PlanningLocalDatabase.inMemory();
    final container = ProviderContainer(
      overrides: [
        supabaseClientProvider.overrideWithValue(client),
        planningLocalDatabaseProvider.overrideWithValue(database),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await database.close();
    });

    expect(
      container.read(planningLocalStoreProvider),
      isA<PlanningLocalStore>(),
    );
    expect(
      container.read(planningLocalReadRepositoryProvider),
      isA<PlanningLocalReadRepository>(),
    );
    expect(
      container.read(planningRemoteRefreshRepositoryProvider),
      isA<PlanningRemoteRefreshRepository>().having(
        (repository) => repository,
        'runtime type',
        isA<SupabasePlanningRepository>(),
      ),
    );
    expect(
      container.read(planningSyncControllerProvider),
      isA<PlanningSyncController>(),
    );
    expect(
      container.read(activePlanningContextControllerProvider),
      isA<ActivePlanningContextController>(),
    );
  });

  test(
    'propagates active catalog context changes into the planning context controller',
    () async {
      final client = SupabaseClient('http://127.0.0.1:54321', 'anon-key');
      final database = PlanningLocalDatabase.inMemory();
      final authController = AppAuthController(_SignedInAuthRepository());
      await authController.signIn(
        email: 'demo@lyron.local',
        password: 'secret',
      );
      final catalogContextProvider = StateProvider<ActiveCatalogContext?>(
        (ref) => null,
      );
      final container = ProviderContainer(
        overrides: [
          supabaseClientProvider.overrideWithValue(client),
          planningLocalDatabaseProvider.overrideWithValue(database),
          appAuthControllerProvider.overrideWithValue(authController),
          activeCatalogContextProvider.overrideWith(
            (ref) => ref.watch(catalogContextProvider),
          ),
          activeOrganizationReaderProvider.overrideWithValue(
            () async => throw StateError('offline'),
          ),
        ],
      );
      addTearDown(() async {
        container.dispose();
        authController.dispose();
        await database.close();
      });

      container.read(activePlanningContextControllerProvider);
      container.read(catalogContextProvider.notifier).state =
          const ActiveCatalogContext(userId: 'user-1', organizationId: 'org-2');
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(activePlanningContextProvider),
        const ActivePlanningReadContext(
          userId: 'user-1',
          organizationId: 'org-2',
        ),
      );
    },
  );
}

class _SignedInAuthRepository implements AuthRepository {
  @override
  Future<AppAuthSession?> restoreSession() async => null;

  @override
  Stream<AppAuthSession?> watchSession() => const Stream.empty();

  @override
  Future<AppAuthSession> signIn({
    required String email,
    required String password,
  }) async => AppAuthSession(userId: 'user-1', email: email);

  @override
  Future<void> signOut() async {}
}
