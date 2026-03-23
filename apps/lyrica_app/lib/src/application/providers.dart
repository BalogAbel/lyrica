import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyrica_app/src/application/sync/sync_overview.dart';
import 'package:lyrica_app/src/offline/local_store_contract.dart';
import 'package:lyrica_app/src/offline/sync_policy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

export 'package:lyrica_app/src/presentation/song_library/song_library_providers.dart';

final syncOverviewProvider = Provider<SyncOverview>((ref) {
  return const SyncOverview(
    storeContract: defaultLocalStoreContract,
    policy: defaultSyncPolicy,
  );
});

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});
