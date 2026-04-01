import 'package:lyron_app/src/offline/local_store_contract.dart';
import 'package:lyron_app/src/offline/sync_policy.dart';

class SyncOverview {
  const SyncOverview({required this.storeContract, required this.policy});

  final LocalStoreContract storeContract;
  final SyncPolicy policy;
}
