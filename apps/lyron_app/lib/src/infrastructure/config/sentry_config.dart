/// Mirrors `SupabaseConfig`'s dart-define pattern, but fails soft: a
/// missing Sentry DSN disables telemetry ([isEnabled] == false) rather
/// than throwing, because telemetry is not a correctness-critical
/// dependency the way Supabase configuration is.
class SentryConfig {
  const SentryConfig({required this.dsn, required this.environment});

  final String dsn;
  final String environment;

  bool get isEnabled => dsn.isNotEmpty;

  factory SentryConfig.fromEnvironment({
    String dsn = const String.fromEnvironment('SENTRY_DSN'),
    String environment = const String.fromEnvironment(
      'SENTRY_ENVIRONMENT',
      defaultValue: 'development',
    ),
  }) {
    return SentryConfig(dsn: dsn, environment: environment);
  }
}
