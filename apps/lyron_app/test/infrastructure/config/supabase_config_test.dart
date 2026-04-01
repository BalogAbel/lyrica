import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/infrastructure/config/supabase_config.dart';

void main() {
  test('returns the provided Supabase environment values', () {
    final config = SupabaseConfig.fromEnvironment(
      url: 'http://127.0.0.1:54321',
      anonKey: 'anon-key',
    );

    expect(config.url, 'http://127.0.0.1:54321');
    expect(config.anonKey, 'anon-key');
  });

  test('throws when the Supabase url is missing', () {
    expect(
      () => SupabaseConfig.fromEnvironment(url: '', anonKey: 'anon-key'),
      throwsArgumentError,
    );
  });

  test('throws when the Supabase anon key is missing', () {
    expect(
      () => SupabaseConfig.fromEnvironment(url: 'http://127.0.0.1:54321'),
      throwsArgumentError,
    );
  });
}
