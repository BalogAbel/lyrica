import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
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

/// Monotonic epoch used to invalidate stale last-known-identity persistence
/// writes when membership is verified empty. Internal to the application
/// provider library: read by [lastKnownIdentityPersistenceProvider] (auth) and
/// the verified-empty cleanup coordinator (planning). Not exported from the
/// `providers.dart` barrel.
@internal
final class LastKnownIdentityPersistenceEpoch {
  var _value = 0;

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
