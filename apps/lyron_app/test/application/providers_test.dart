import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/domain/planning/planning_repository.dart';
import 'package:lyron_app/src/infrastructure/planning/supabase_planning_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('allows overriding the shared Supabase client provider', () {
    final client = SupabaseClient('http://127.0.0.1:54321', 'anon-key');
    final container = ProviderContainer(
      overrides: [supabaseClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);

    expect(container.read(supabaseClientProvider), same(client));
  });

  test('selects a stable active organization id from RPC results', () {
    expect(
      selectActiveOrganizationId(const ['org-b', 'org-a', 'org-c']),
      'org-a',
    );
    expect(selectActiveOrganizationId(const []), isNull);
    expect(selectActiveOrganizationId('unexpected'), isNull);
  });

  test('wires PlanningRepository through the shared provider graph', () {
    final client = SupabaseClient('http://127.0.0.1:54321', 'anon-key');
    final container = ProviderContainer(
      overrides: [supabaseClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);

    expect(
      container.read(planningRepositoryProvider),
      isA<PlanningRepository>().having(
        (repository) => repository,
        'runtime type',
        isA<SupabasePlanningRepository>(),
      ),
    );
  });
}
