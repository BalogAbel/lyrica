import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/planning_sync_payload.dart';
import 'package:lyron_app/src/infrastructure/config/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/backend_planning_reads.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
const _hiddenPlanId = '44444444-4444-4444-4444-444444444444';
const _multiSessionPlanId = '44444444-4444-4444-4444-444444444442';
const _visibleOrganizationId = '11111111-1111-1111-1111-111111111111';
const _hiddenOrganizationId = '11111111-1111-1111-1111-111111111112';

void main() {
  late HttpOverrides? originalHttpOverrides;

  setUpAll(() {
    originalHttpOverrides = HttpOverrides.current;
    HttpOverrides.global = _PassthroughHttpOverrides();
  });

  tearDownAll(() {
    HttpOverrides.global = originalHttpOverrides;
  });

  test(
    'demo user reads ordered visible plans and one ordered plan detail',
    () async {
      final config = SupabaseConfig.fromEnvironment();
      final client = SupabaseClient(config.url, config.anonKey);

      addTearDown(() async {
        await client.auth.signOut();
        await client.dispose();
      });

      await _signInDemoUser(client);

      final payload = await readBackendPlanningPayload(
        client,
        organizationId: _visibleOrganizationId,
      );
      expect(
        payload.plans.map((plan) => plan.name).toList(growable: false),
        const ['Sunday Morning', 'Evening Gathering', 'Team Rehearsal'],
      );

      final detail = await readBackendPlanDetail(
        client,
        organizationId: _visibleOrganizationId,
        planId: _multiSessionPlanId,
      );
      expect(detail.plan.name, 'Team Rehearsal');
      expect(
        detail.sessions.map((session) => session.name).toList(growable: false),
        const ['Warm-Up', 'Run-Through'],
      );
      expect(detail.sessions.first.items.single.song.title, 'Egy út');
      expect(
        detail.sessions.last.items
            .map((item) => item.song.title)
            .toList(growable: false),
        const ['A forrásnál', 'A mi Istenünk (Leborulok előtted)'],
      );
    },
    skip: _supabaseUrl.isEmpty || _supabaseAnonKey.isEmpty,
  );

  test(
    'demo user cannot read hidden-organization plans',
    () async {
      final config = SupabaseConfig.fromEnvironment();
      final client = SupabaseClient(config.url, config.anonKey);

      addTearDown(() async {
        await client.auth.signOut();
        await client.dispose();
      });

      await _signInDemoUser(client);

      final visible = await readBackendPlanningPayload(
        client,
        organizationId: _visibleOrganizationId,
      );
      expect(visible.plans.any((plan) => plan.id == _hiddenPlanId), isFalse);

      final hidden = await readBackendPlanningPayload(
        client,
        organizationId: _hiddenOrganizationId,
      );
      expect(hidden.plans, isEmpty);
      expect(hidden.sessions, isEmpty);
      expect(hidden.items, isEmpty);

      await expectLater(
        readBackendPlanDetail(
          client,
          organizationId: _hiddenOrganizationId,
          planId: _hiddenPlanId,
        ),
        throwsA(isA<StateError>()),
      );
    },
    skip: _supabaseUrl.isEmpty || _supabaseAnonKey.isEmpty,
  );

  test(
    'R2: a page size of 1 reads the same planning payload as the default',
    () async {
      final config = SupabaseConfig.fromEnvironment();
      final client = SupabaseClient(config.url, config.anonKey);

      addTearDown(() async {
        await client.auth.signOut();
        await client.dispose();
      });

      await _signInDemoUser(client);

      final paged = await readBackendPlanningPayload(
        client,
        organizationId: _visibleOrganizationId,
        pageSize: 1,
      );
      final standard = await readBackendPlanningPayload(
        client,
        organizationId: _visibleOrganizationId,
      );

      expect(standard.plans, isNotEmpty);
      expect(standard.sessions, isNotEmpty);
      expect(standard.items, isNotEmpty);
      expect(_signature(paged), _signature(standard));
    },
    skip: _supabaseUrl.isEmpty || _supabaseAnonKey.isEmpty,
  );

  test(
    'demo user reads visible organization planning tables only',
    () async {
      final config = SupabaseConfig.fromEnvironment();
      final client = SupabaseClient(config.url, config.anonKey);

      addTearDown(() async {
        await client.auth.signOut();
        await client.dispose();
      });

      await _signInDemoUser(client);

      final visiblePlans = await client
          .from('plans')
          .select('id')
          .eq('organization_id', _visibleOrganizationId);
      final visibleSessions = await client
          .from('sessions')
          .select('id')
          .eq('organization_id', _visibleOrganizationId);
      final visibleItems = await client
          .from('session_items')
          .select('id')
          .eq('organization_id', _visibleOrganizationId);

      final hiddenPlans = await client
          .from('plans')
          .select('id')
          .eq('organization_id', _hiddenOrganizationId);
      final hiddenSessions = await client
          .from('sessions')
          .select('id')
          .eq('organization_id', _hiddenOrganizationId);
      final hiddenItems = await client
          .from('session_items')
          .select('id')
          .eq('organization_id', _hiddenOrganizationId);

      expect(visiblePlans, isNotEmpty);
      expect(visibleSessions, isNotEmpty);
      expect(visibleItems, isNotEmpty);
      expect(hiddenPlans, isEmpty);
      expect(hiddenSessions, isEmpty);
      expect(hiddenItems, isEmpty);
    },
    skip: _supabaseUrl.isEmpty || _supabaseAnonKey.isEmpty,
  );
}

class _PassthroughHttpOverrides extends HttpOverrides {}

/// Every field of every row, in order, so two payloads compare by value.
List<String> _signature(PlanningSyncPayload payload) => [
  for (final plan in payload.plans)
    'plan|${plan.id}|${plan.slug}|${plan.name}|${plan.description}|'
        '${plan.scheduledFor}|${plan.updatedAt}|${plan.version}|'
        '${plan.contentVersion}',
  for (final session in payload.sessions)
    'session|${session.id}|${session.planId}|${session.slug}|'
        '${session.position}|${session.name}|${session.version}',
  for (final item in payload.items)
    'item|${item.id}|${item.planId}|${item.sessionId}|${item.position}|'
        '${item.songId}|${item.songTitle}',
];

Future<void> _signInDemoUser(SupabaseClient client) async {
  await client.auth.signOut();
  final authResponse = await client.auth.signInWithPassword(
    email: 'demo@lyron.local',
    password: 'LyronDemo123!',
  );
  expect(authResponse.session, isNotNull);
}
