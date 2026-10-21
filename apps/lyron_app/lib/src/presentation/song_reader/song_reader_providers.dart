import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/application/provider_retry_policy.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/domain/core/capability.dart';

/// Overridable provider that resolves the current user's ID.
///
/// Defaults to reading from [supabaseClientProvider] so production behaviour is
/// unchanged. Tests override this with a [Provider.value] to avoid initialising
/// a real [SupabaseClient].
final readerUserIdProvider = Provider<String?>((ref) {
  try {
    return ref.watch(supabaseClientProvider).auth.currentUser?.id;
  } catch (_) {
    return null;
  }
});

/// Whether the member may edit sessions in [organizationId] (PS26): the answer
/// the reader falls back to while the capability resolver has no cached one.
/// Fail-closed: loading and any error read as no, so Save to plan never
/// appears on a guess.
final readerCanEditSessionsProvider = FutureProvider.autoDispose
    .family<bool, String>((ref, organizationId) async {
      try {
        return await ref
            .watch(capabilityResolverProvider)
            .hasCapability(organizationId, Capability.editSessions);
      } catch (_) {
        return false;
      }
    }, retry: noAutomaticProviderRetry);
