import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/application/providers.dart';

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
