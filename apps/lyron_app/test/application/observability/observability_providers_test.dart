import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/observability/observability.dart';
import 'package:lyron_app/src/application/observability/observability_providers.dart';

class _FakeObservability extends NoopObservability {
  const _FakeObservability();
}

void main() {
  test('observabilityProvider resolves to NoopObservability by default', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(observabilityProvider), isA<NoopObservability>());
  });

  test(
    'observabilityProvider is overridable in tests without touching the global setter',
    () {
      const fake = _FakeObservability();
      final container = ProviderContainer(
        overrides: [observabilityProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      expect(container.read(observabilityProvider), same(fake));
    },
  );

  test(
    'setCurrentObservability changes what a fresh provider read resolves to',
    () {
      const fake = _FakeObservability();
      setCurrentObservability(fake);
      addTearDown(() => setCurrentObservability(const NoopObservability()));

      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(observabilityProvider), same(fake));
    },
  );
}
