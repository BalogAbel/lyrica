import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/observability/observability.dart';
import 'package:lyron_app/src/application/observability/observability_providers.dart';
import 'package:lyron_app/src/bootstrap/bootstrap.dart';
import 'package:lyron_app/src/infrastructure/config/sentry_config.dart';
import 'package:lyron_app/src/infrastructure/observability/sentry_observability.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

const _enabled = SentryConfig(
  dsn: 'https://public@o0.ingest.sentry.io/0',
  environment: 'test',
);
const _disabled = SentryConfig(dsn: '', environment: 'test');

void main() {
  setUp(() {
    addTearDown(() => setCurrentObservability(const NoopObservability()));
  });

  test('disabled config -> Noop, init never called', () async {
    var initCalls = 0;

    final result = await initObservability(
      _disabled,
      init: (_) async => initCalls++,
    );

    expect(result, isA<NoopObservability>());
    expect(result, isNot(isA<SentryObservability>()));
    expect(initCalls, 0);
  });

  test(
    'enabled + init succeeds -> SentryObservability, set globally',
    () async {
      final result = await initObservability(_enabled, init: (_) async {});

      expect(result, isA<SentryObservability>());
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(observabilityProvider), isA<SentryObservability>());
    },
  );

  test('options callback: dsn/env/sampling/pii/ANR', () async {
    FlutterOptionsConfiguration? configure;
    await initObservability(_enabled, init: (c) async => configure = c);

    final options = SentryFlutterOptions();
    await configure!(options);

    expect(options.dsn, _enabled.dsn);
    expect(options.environment, 'test');
    expect(options.tracesSampleRate, 1.0);
    expect(options.sendDefaultPii, isFalse);
    expect(options.anrEnabled, isTrue);
  });

  test(
    'enabled + init throws -> Noop returned and set globally, error reported, '
    'no rethrow',
    () async {
      final reported = <FlutterErrorDetails>[];
      final originalOnError = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = originalOnError);
      final boom = ArgumentError('bad dsn');

      final result = await initObservability(
        _enabled,
        init: (_) async => throw boom,
      );

      expect(result, isA<NoopObservability>());
      expect(result, isNot(isA<SentryObservability>()));
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final resolved = container.read(observabilityProvider);
      expect(resolved, isA<NoopObservability>());
      expect(resolved, isNot(isA<SentryObservability>()));
      expect(reported, hasLength(1));
      expect(reported.single.exception, same(boom));
    },
  );
}
