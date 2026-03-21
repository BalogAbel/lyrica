import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyrica_app/src/application/sync/sync_overview.dart';
import 'package:lyrica_app/src/offline/local_store_contract.dart';
import 'package:lyrica_app/src/offline/sync_policy.dart';

final syncOverviewProvider = Provider<SyncOverview>((ref) {
  return const SyncOverview(
    storeContract: defaultLocalStoreContract,
    policy: defaultSyncPolicy,
  );
});
