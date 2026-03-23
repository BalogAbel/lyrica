class SupabaseConfig {
  const SupabaseConfig({required this.url, required this.anonKey});

  final String url;
  final String anonKey;

  factory SupabaseConfig.fromEnvironment({
    String url = const String.fromEnvironment('SUPABASE_URL'),
    String anonKey = const String.fromEnvironment('SUPABASE_ANON_KEY'),
  }) {
    if (url.isEmpty) {
      throw ArgumentError.value(url, 'url', 'SUPABASE_URL must not be empty.');
    }

    if (anonKey.isEmpty) {
      throw ArgumentError.value(
        anonKey,
        'anonKey',
        'SUPABASE_ANON_KEY must not be empty.',
      );
    }

    return SupabaseConfig(url: url, anonKey: anonKey);
  }
}
