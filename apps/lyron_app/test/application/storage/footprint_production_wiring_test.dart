import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/storage/local_storage_footprint.dart';
import 'package:lyron_app/src/application/storage/local_storage_monitor.dart';
import 'package:lyron_app/src/application/storage/local_storage_write_recovery.dart';
import 'package:lyron_app/src/domain/song/song_source.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';
import 'package:lyron_app/src/presentation/sync/unified_sync_providers.dart';

import '../../support/drift_test_setup.dart';

/// Pins that a real write through the *production* provider graph -- not a
/// hand-bumped revision, not a store constructed with its own test-injected
/// callback -- reaches `localStorageFootprintChangedProvider` and causes a
/// mounted `localStorageFootprintProvider` to remeasure.
///
/// `unified_sync_providers_test.dart` already proves the revision provider
/// triggers a remeasure; it bumps the revision by hand. The store tests
/// (`song_catalog_store_test.dart`, `planning_local_store_test.dart`,
/// `planning_mutation_store_test.dart`, `song_catalog_evictor_test.dart`)
/// each construct their subject directly with a callback they supply
/// themselves. None of that exercises `core_providers.dart`,
/// `planning_providers.dart`, or `song_catalog_providers.dart` actually
/// wiring `onStorageFootprintChanged` into `songCatalogStoreProvider`,
/// `planningLocalStoreProvider`, `planningMutationStoreProvider`, or
/// `songCatalogEvictorProvider` -- the parameter is optional and nullable,
/// so dropping any one of those four wiring arguments still compiles and
/// leaves every other test green.
void main() {
  suppressDriftMultipleDatabaseWarnings();

  group('production footprint wiring', () {
    late SongCatalogDatabase songDatabase;
    late PlanningLocalDatabase planningDatabase;
    late ProviderContainer container;
    late _CountingLocalStorageMonitor monitor;

    setUp(() {
      songDatabase = SongCatalogDatabase.inMemory();
      planningDatabase = PlanningLocalDatabase.inMemory();
    });

    tearDown(() async {
      container.dispose();
      await songDatabase.close();
      await planningDatabase.close();
    });

    ProviderContainer buildContainer() {
      final built = ProviderContainer(
        overrides: [
          songCatalogDatabaseProvider.overrideWithValue(songDatabase),
          planningLocalDatabaseProvider.overrideWithValue(planningDatabase),
          activePlanningContextProvider.overrideWithValue(
            const ActivePlanningReadContext(
              userId: 'user-1',
              organizationId: 'org-1',
            ),
          ),
          // Wraps the real, production-composed monitor (built from the
          // same accountants core_providers.dart wires, over the same
          // overridden databases) only to count invocations. The wiring
          // under test -- each store/evictor provider's
          // onStorageFootprintChanged argument -- is left untouched.
          localStorageMonitorProvider.overrideWith((ref) {
            final real = LocalStorageMonitor(
              planningAccountant: ref.watch(planningStorageAccountantProvider),
              catalogAccountant: ref.watch(catalogStorageAccountantProvider),
              budget: ref.watch(localStorageBudgetProvider),
            );
            return monitor = _CountingLocalStorageMonitor(real);
          }),
        ],
      );
      addTearDown(built.dispose);
      return built;
    }

    test(
      'a committed song catalog store write remeasures the mounted footprint',
      () async {
        container = buildContainer();
        final subscription = container.listen(
          localStorageFootprintProvider,
          (_, _) {},
        );
        addTearDown(subscription.close);

        final first = await container.read(
          localStorageFootprintProvider.future,
        );
        expect(first.catalogBytes, 0);
        expect(monitor.measurementCount, 1);
        final revisionBefore = container.read(
          localStorageFootprintRevisionProvider,
        );

        await container
            .read(songCatalogStoreProvider)
            .replaceActiveSnapshot(
              userId: 'user-1',
              organizationId: 'org-1',
              summaries: const [SongSummary(id: 'song-1', title: 'Song One')],
              sources: const [
                SongSource(id: 'song-1', source: 'chordpro body'),
              ],
              refreshedAt: DateTime.utc(2026, 8, 2, 12),
            );

        final second = await container.read(
          localStorageFootprintProvider.future,
        );
        expect(
          container.read(localStorageFootprintRevisionProvider),
          revisionBefore + 1,
        );
        expect(monitor.measurementCount, 2);
        expect(second.catalogBytes, greaterThan(0));
      },
    );

    test(
      'a committed planning local store write remeasures the mounted footprint',
      () async {
        container = buildContainer();
        final subscription = container.listen(
          localStorageFootprintProvider,
          (_, _) {},
        );
        addTearDown(subscription.close);

        final first = await container.read(
          localStorageFootprintProvider.future,
        );
        expect(first.projectionBytes, 0);
        expect(monitor.measurementCount, 1);
        final revisionBefore = container.read(
          localStorageFootprintRevisionProvider,
        );

        await container
            .read(planningLocalStoreProvider)
            .replaceActiveProjection(
              userId: 'user-1',
              organizationId: 'org-1',
              plans: [
                CachedPlanRecord(
                  id: 'plan-1',
                  name: 'Weekend Service',
                  description: 'Draft',
                  scheduledFor: null,
                  updatedAt: DateTime.utc(2026, 8, 2),
                ),
              ],
              sessions: const [],
              items: const [],
              refreshedAt: DateTime.utc(2026, 8, 2, 12),
            );

        final second = await container.read(
          localStorageFootprintProvider.future,
        );
        expect(
          container.read(localStorageFootprintRevisionProvider),
          revisionBefore + 1,
        );
        expect(monitor.measurementCount, 2);
        expect(second.projectionBytes, greaterThan(0));
      },
    );

    test(
      'a committed planning mutation store write remeasures the mounted footprint',
      () async {
        container = buildContainer();
        final subscription = container.listen(
          localStorageFootprintProvider,
          (_, _) {},
        );
        addTearDown(subscription.close);

        final first = await container.read(
          localStorageFootprintProvider.future,
        );
        expect(first.mutationCount, 0);
        expect(monitor.measurementCount, 1);
        final revisionBefore = container.read(
          localStorageFootprintRevisionProvider,
        );

        await container
            .read(planningMutationStoreProvider)
            .recordPlanCreate(
              context: const PlanningMutationContext(
                userId: 'user-1',
                organizationId: 'org-1',
              ),
              draft: const PlanningPlanCreateMutationDraft(
                planId: 'plan-1',
                slug: 'weekend-service',
                name: 'Weekend Service',
              ),
            );

        final second = await container.read(
          localStorageFootprintProvider.future,
        );
        expect(
          container.read(localStorageFootprintRevisionProvider),
          revisionBefore + 1,
        );
        expect(monitor.measurementCount, 2);
        expect(second.mutationCount, 1);
      },
    );

    test(
      'a committed catalog eviction remeasures the mounted footprint',
      () async {
        container = buildContainer();

        // Seed one droppable cached source directly (no pending mutation
        // protects it), mirroring song_catalog_evictor_test.dart's setup.
        await songDatabase
            .into(songDatabase.cachedCatalogSnapshots)
            .insert(
              CachedCatalogSnapshotsCompanion.insert(
                userId: 'user-1',
                organizationId: 'org-1',
                snapshotVersion: 1,
                refreshedAt: DateTime.utc(2026, 8, 2),
              ),
            );
        await songDatabase
            .into(songDatabase.cachedCatalogSummaries)
            .insert(
              CachedCatalogSummariesCompanion.insert(
                userId: 'user-1',
                organizationId: 'org-1',
                snapshotVersion: 1,
                songId: 'song-droppable',
                slug: 'song-droppable',
                title: 'Droppable Song',
                version: 1,
              ),
            );
        await songDatabase
            .into(songDatabase.cachedCatalogSources)
            .insert(
              CachedCatalogSourcesCompanion.insert(
                userId: 'user-1',
                organizationId: 'org-1',
                snapshotVersion: 1,
                songId: 'song-droppable',
                source: 'body ' * 200,
              ),
            );

        final subscription = container.listen(
          localStorageFootprintProvider,
          (_, _) {},
        );
        addTearDown(subscription.close);

        final first = await container.read(
          localStorageFootprintProvider.future,
        );
        expect(first.catalogBytes, greaterThan(0));
        expect(monitor.measurementCount, 1);
        final revisionBefore = container.read(
          localStorageFootprintRevisionProvider,
        );

        final freed = await container
            .read(songCatalogEvictorProvider)
            .evictDroppable();
        expect(freed, greaterThan(0));

        final second = await container.read(
          localStorageFootprintProvider.future,
        );
        expect(
          container.read(localStorageFootprintRevisionProvider),
          revisionBefore + 1,
        );
        expect(monitor.measurementCount, 2);
        expect(second.catalogBytes, lessThan(first.catalogBytes));
      },
    );
  });

  group('BudgetedPlanningMutationStore shared write-recovery boundary '
      '(M1, PR #64 review)', () {
    // ADR-028 and the PR body both claim ONE shared LocalStorageWriteRecovery
    // boundary across every guarded local write. BudgetedPlanningMutationStore
    // used to build its own instance internally instead of taking the
    // provider-supplied one, which made that claim false for the planning
    // mutation path (and left localStorageWriteRecoveryProvider partly dead
    // code for it). This is a structural pin, not a behavioural one: it
    // asserts the decorator calls through the EXACT recovery instance the
    // provider graph supplies, not one it constructs for itself.
    test('planningMutationStoreProvider routes a guarded write through the '
        'localStorageWriteRecoveryProvider instance', () async {
      final songDatabase = SongCatalogDatabase.inMemory();
      final planningDatabase = PlanningLocalDatabase.inMemory();
      addTearDown(songDatabase.close);
      addTearDown(planningDatabase.close);

      var guardCalls = 0;
      final container = ProviderContainer(
        overrides: [
          songCatalogDatabaseProvider.overrideWithValue(songDatabase),
          planningLocalDatabaseProvider.overrideWithValue(planningDatabase),
          localStorageWriteRecoveryProvider.overrideWith((ref) {
            return _CountingLocalStorageWriteRecovery(
              evictor: ref.watch(songCatalogEvictorProvider),
              onGuard: () => guardCalls += 1,
            );
          }),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(planningMutationStoreProvider)
          .recordPlanCreate(
            context: const PlanningMutationContext(
              userId: 'user-1',
              organizationId: 'org-1',
            ),
            draft: const PlanningPlanCreateMutationDraft(
              planId: 'plan-1',
              slug: 'weekend-service',
              name: 'Weekend Service',
            ),
          );

      expect(
        guardCalls,
        1,
        reason:
            'the write must have gone through the recovery instance the '
            'provider graph supplies -- a store that built its own '
            'internally would leave this at 0',
      );
    });
  });
}

/// Subclasses the real [LocalStorageWriteRecovery] (rather than reimplementing
/// its policy) purely to count [guard] invocations, so the test above can
/// tell whether `planningMutationStoreProvider`'s store actually called
/// through THIS instance.
class _CountingLocalStorageWriteRecovery extends LocalStorageWriteRecovery {
  _CountingLocalStorageWriteRecovery({
    required super.evictor,
    required this._onGuard,
  });

  final void Function() _onGuard;

  @override
  Future<T> guard<T>(Future<T> Function() write) {
    _onGuard();
    return super.guard(write);
  }
}

class _CountingLocalStorageMonitor implements LocalStorageMonitor {
  _CountingLocalStorageMonitor(this._delegate);

  final LocalStorageMonitor _delegate;
  int measurementCount = 0;

  @override
  Future<LocalStorageFootprint> measure({
    required String userId,
    required String organizationId,
  }) async {
    measurementCount += 1;
    return _delegate.measure(userId: userId, organizationId: organizationId);
  }

  @override
  LocalStoragePressure pressureOf(LocalStorageFootprint footprint) =>
      _delegate.pressureOf(footprint);
}
