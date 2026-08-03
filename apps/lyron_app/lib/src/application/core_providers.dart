import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/application/storage/catalog_storage_accountant.dart';
import 'package:lyron_app/src/application/storage/local_storage_budget.dart';
import 'package:lyron_app/src/application/storage/local_storage_monitor.dart';
import 'package:lyron_app/src/application/storage/planning_storage_accountant.dart';
import 'package:lyron_app/src/application/storage/song_catalog_evictor.dart';
import 'package:lyron_app/src/application/sync/sync_overview.dart';
import 'package:lyron_app/src/offline/local_store_contract.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';
import 'package:lyron_app/src/offline/sync_policy.dart';
import 'package:meta/meta.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final syncOverviewProvider = Provider<SyncOverview>((ref) {
  return const SyncOverview(
    storeContract: defaultLocalStoreContract,
    policy: defaultSyncPolicy,
  );
});

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

SongCatalogDatabase? _sharedSongCatalogDatabase;
PlanningLocalDatabase? _sharedPlanningLocalDatabase;

final songCatalogDatabaseProvider = Provider<SongCatalogDatabase>((ref) {
  // Drift expects a singleton database per app lifecycle to avoid
  // multi-instance races during rapid provider/container churn in tests.
  return _sharedSongCatalogDatabase ??= SongCatalogDatabase.local();
});

Future<void> closeSharedDatabases() async {
  final songCatalogDatabase = _sharedSongCatalogDatabase;
  final planningLocalDatabase = _sharedPlanningLocalDatabase;
  _sharedSongCatalogDatabase = null;
  _sharedPlanningLocalDatabase = null;

  await Future.wait([
    if (songCatalogDatabase != null) songCatalogDatabase.close(),
    if (planningLocalDatabase != null) planningLocalDatabase.close(),
  ]);
}

final planningLocalDatabaseProvider = Provider<PlanningLocalDatabase>((ref) {
  // Match the song catalog lifecycle so provider/container churn does not
  // create overlapping Drift database instances in tests.
  return _sharedPlanningLocalDatabase ??= PlanningLocalDatabase.local();
});

final localStorageBudgetProvider = Provider<LocalStorageBudget>((ref) {
  return const LocalStorageBudget();
});

/// Monotonic invalidation seam for SQL-derived local-storage measurements.
final localStorageFootprintRevisionProvider = StateProvider<int>((ref) => 0);

final planningStorageAccountantProvider = Provider<PlanningStorageAccountant>((
  ref,
) {
  return PlanningStorageAccountant(ref.watch(planningLocalDatabaseProvider));
});

final catalogStorageAccountantProvider = Provider<CatalogStorageAccountant>((
  ref,
) {
  return CatalogStorageAccountant(ref.watch(songCatalogDatabaseProvider));
});

final songCatalogEvictorProvider = Provider<SongCatalogEvictor>((ref) {
  return SongCatalogEvictor(
    database: ref.watch(songCatalogDatabaseProvider),
    accountant: ref.watch(catalogStorageAccountantProvider),
  );
});

final localStorageMonitorProvider = Provider<LocalStorageMonitor>((ref) {
  return LocalStorageMonitor(
    planningAccountant: ref.watch(planningStorageAccountantProvider),
    catalogAccountant: ref.watch(catalogStorageAccountantProvider),
    budget: ref.watch(localStorageBudgetProvider),
  );
});

/// Monotonic epoch used to invalidate stale last-known-identity persistence
/// writes when membership is verified empty. Internal to the application
/// provider library: read by [lastKnownIdentityPersistenceProvider] (auth) and
/// the verified-empty cleanup coordinator (planning). Not exported from the
/// `providers.dart` barrel.
@internal
final class LastKnownIdentityPersistenceEpoch {
  int _value = 0;

  int invalidate() {
    _value += 1;
    return _value;
  }

  bool isCurrent(int value) => _value == value;
}

@internal
final lastKnownIdentityPersistenceEpochProvider =
    Provider<LastKnownIdentityPersistenceEpoch>(
      (_) => LastKnownIdentityPersistenceEpoch(),
    );
