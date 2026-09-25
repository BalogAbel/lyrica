import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/infrastructure/config/sentry_config.dart';

void main() {
  test('disabled when the DSN is empty', () {
    final config = SentryConfig.fromEnvironment(
      dsn: '',
      environment: 'development',
    );

    expect(config.isEnabled, isFalse);
    expect(config.dsn, '');
    expect(config.environment, 'development');
  });

  test('enabled when a non-empty DSN is provided', () {
    final config = SentryConfig.fromEnvironment(
      dsn: 'https://public@example.ingest.sentry.io/1',
      environment: 'production',
    );

    expect(config.isEnabled, isTrue);
    expect(config.environment, 'production');
  });

  test('defaults environment to development when not provided', () {
    final config = SentryConfig.fromEnvironment(dsn: '');

    expect(config.environment, 'development');
  });
}
