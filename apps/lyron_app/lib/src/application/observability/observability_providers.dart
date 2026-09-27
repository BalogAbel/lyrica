import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/application/observability/observability.dart';

// `Observability` must exist before `Supabase.initialize` runs in
// bootstrap.dart (needed to construct `TracingHttpClient`), which itself
// runs before any `ProviderScope` exists -- so it cannot be resolved
// through Riverpod at the point it is first needed. This mirrors how
// `core_providers.dart`'s `supabaseClientProvider` reads the static
// `Supabase.instance.client` rather than constructing it. Tests should
// prefer `ProviderContainer(overrides: [observabilityProvider
// .overrideWithValue(fake)])` over this setter -- the setter exists only
// for the one call site (`bootstrap()`) that runs before any
// `ProviderScope` exists.
Observability _currentObservability = const NoopObservability();

void setCurrentObservability(Observability observability) {
  _currentObservability = observability;
}

final observabilityProvider = Provider<Observability>((ref) {
  return _currentObservability;
});
