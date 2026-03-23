import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyrica_app/src/application/auth/app_auth_controller.dart';
import 'package:lyrica_app/src/application/auth/auth_repository.dart';
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

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  throw UnimplementedError('authRepositoryProvider must be overridden.');
});

final appAuthControllerProvider = Provider<AppAuthController>((ref) {
  final controller = AppAuthController(ref.read(authRepositoryProvider));
  ref.onDispose(controller.dispose);
  return controller;
});

final appAuthListenableProvider = Provider<Listenable>((ref) {
  return ref.read(appAuthControllerProvider);
});
