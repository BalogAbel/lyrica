import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lyron_app/src/infrastructure/planning/supabase_planning_repository.dart';
import 'package:lyron_app/src/shared/keyset_paging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/keyset_pages.dart';

const _org = 'org-1';

/// Canonical lowercase uuid whose order follows [n].
String _id(int n) =>
    '00000000-0000-4000-8000-${n.toRadixString(16).padLeft(12, '0')}';

Map<String, dynamic> _plan(
  String id, {
  String? name,
  String? scheduledFor,
  String updatedAt = '2026-03-31T09:00:00Z',
  int? contentVersion,
}) => {
  'id': id,
  'organization_id': _org,
  'slug': id,
  'name': name ?? 'Plan $id',
  'description': null,
  'scheduled_for': scheduledFor,
  'updated_at': updatedAt,
  'version': 1,
  'content_version': contentVersion,
};

Map<String, dynamic> _session(
  String id,
  String planId, {
  int position = 10,
  String? name,
}) => {
  'id': id,
  'plan_id': planId,
  'slug': id,
  'name': name ?? 'Session $id',
  'position': position,
  'version': 1,
};

Map<String, dynamic> _item(
  String id,
  String sessionId, {
  int position = 10,
  Object? song = const {'id': 'song-1', 'slug': 'song-1', 'title': 'Song'},
}) => {'id': id, 'session_id': sessionId, 'position': position, 'song': song};

class _Call {
  _Call(this.stream, this.organizationId, this.after, this.limit);

  final String stream;
  final String organizationId;
  final String? after;
  final int limit;
}

SupabasePlanningRepository _repository({
  List<Map<String, dynamic>> plans = const [],
  List<Map<String, dynamic>> sessions = const [],
  List<Map<String, dynamic>> items = const [],
  int? cap,
  int pageSize = 500,
  List<_Call>? log,
  Future<List<Map<String, dynamic>>?> Function(String stream)? override,
}) {
  Future<List<Map<String, dynamic>>> serve(
    String stream,
    List<Map<String, dynamic>> rows,
    String organizationId,
    String? after,
    int limit,
  ) async {
    log?.add(_Call(stream, organizationId, after, limit));
    final overridden = await override?.call(stream);
    return overridden ?? keysetPage(rows, after: after, limit: limit, cap: cap);
  }

  return SupabasePlanningRepository.testing(
    pageSize: pageSize,
    fetchPlanPage:
        ({required organizationId, required after, required limit}) =>
            serve('plans', plans, organizationId, after, limit),
    fetchSessionPage:
        ({required organizationId, required after, required limit}) =>
            serve('sessions', sessions, organizationId, after, limit),
    fetchSessionItemPage:
        ({required organizationId, required after, required limit}) =>
            serve('session_items', items, organizationId, after, limit),
  );
}

void main() {
  group('fetchPlanningSyncPayload ordering and mapping', () {
    test(
      'plans are ordered by schedule, then updated_at desc, then id',
      () async {
        final repository = _repository(
          plans: [
            _plan(_id(1), updatedAt: '2026-03-31T10:00:00Z'),
            _plan(
              _id(2),
              scheduledFor: '2026-04-06T09:00:00Z',
              updatedAt: '2026-03-31T09:00:00Z',
            ),
            _plan(
              _id(3),
              scheduledFor: '2026-04-05T09:00:00Z',
              updatedAt: '2026-03-31T08:00:00Z',
            ),
            _plan(
              _id(4),
              scheduledFor: '2026-04-06T09:00:00Z',
              updatedAt: '2026-03-31T11:00:00Z',
            ),
            _plan(
              _id(6),
              scheduledFor: '2026-04-07T09:00:00Z',
              updatedAt: '2026-03-31T07:00:00Z',
            ),
            _plan(
              _id(5),
              scheduledFor: '2026-04-07T09:00:00Z',
              updatedAt: '2026-03-31T07:00:00Z',
            ),
          ],
        );

        final payload = await repository.fetchPlanningSyncPayload(
          organizationId: _org,
        );

        expect(payload.plans.map((plan) => plan.id), [
          _id(3),
          _id(4),
          _id(2),
          _id(5),
          _id(6),
          _id(1),
        ]);
      },
    );

    test('sessions follow their plan by position then id, items by position '
        'then id, with the plan id carried onto sessions and items', () async {
      // plan A sorts before plan B (earlier schedule).
      final planA = _id(1);
      final planB = _id(2);
      final repository = _repository(
        plans: [
          _plan(planB, scheduledFor: '2026-04-06T09:00:00Z'),
          _plan(planA, scheduledFor: '2026-04-05T09:00:00Z'),
        ],
        sessions: [
          _session(_id(10), planA, position: 20),
          _session(_id(11), planA, position: 20),
          _session(_id(12), planA, position: 10),
          _session(_id(13), planB, position: 10),
        ],
        items: [
          _item(_id(20), _id(10), position: 20),
          _item(_id(21), _id(10), position: 10),
          _item(_id(22), _id(10), position: 10),
          _item(
            _id(23),
            _id(13),
            song: const {'id': 'song-2', 'slug': 'song-2', 'title': 'Second'},
          ),
        ],
      );

      final payload = await repository.fetchPlanningSyncPayload(
        organizationId: _org,
      );

      expect(payload.plans.map((plan) => plan.id), [planA, planB]);
      expect(payload.sessions.map((session) => session.id), [
        _id(12),
        _id(10),
        _id(11),
        _id(13),
      ]);
      expect(payload.sessions.map((session) => session.planId), [
        planA,
        planA,
        planA,
        planB,
      ]);
      expect(payload.items.map((item) => item.id), [
        _id(21),
        _id(22),
        _id(20),
        _id(23),
      ]);
      expect(payload.items.map((item) => item.sessionId), [
        _id(10),
        _id(10),
        _id(10),
        _id(13),
      ]);
      expect(payload.items.map((item) => item.planId), [
        planA,
        planA,
        planA,
        planB,
      ]);
      expect(payload.items.last.songId, 'song-2');
      expect(payload.items.last.songTitle, 'Second');
    });

    test('plan content_version is carried (D4)', () async {
      final repository = _repository(
        plans: [
          _plan(_id(1), contentVersion: 5),
          _plan(_id(2), contentVersion: 2),
        ],
      );

      final payload = await repository.fetchPlanningSyncPayload(
        organizationId: _org,
      );

      expect(payload.plans.map((plan) => plan.contentVersion), [5, 2]);
    });

    test('an item without a readable song fails the refresh', () async {
      final repository = _repository(
        plans: [_plan(_id(1))],
        sessions: [_session(_id(2), _id(1))],
        items: [_item(_id(3), _id(2), song: null)],
      );

      await expectLater(
        repository.fetchPlanningSyncPayload(organizationId: _org),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('paged streams (PG5)', () {
    test(
      'P1 a server cap below the page size still yields every row',
      () async {
        final plans = [for (var i = 1; i <= 7; i++) _plan(_id(i))];
        final sessions = [
          for (var i = 1; i <= 7; i++) _session(_id(100 + i), _id(i)),
        ];
        final items = [
          for (var i = 1; i <= 7; i++) _item(_id(200 + i), _id(100 + i)),
        ];
        final repository = _repository(
          plans: plans,
          sessions: sessions,
          items: items,
          cap: 2,
          pageSize: 5,
        );

        final payload = await repository.fetchPlanningSyncPayload(
          organizationId: _org,
        );

        expect(payload.plans, hasLength(7));
        expect(payload.sessions, hasLength(7));
        expect(payload.items, hasLength(7));
      },
    );

    test('P2 every plan page precedes every session page, which precedes '
        'every item page (I7)', () async {
      final log = <_Call>[];
      final repository = _repository(
        plans: [for (var i = 1; i <= 3; i++) _plan(_id(i))],
        sessions: [for (var i = 1; i <= 3; i++) _session(_id(100 + i), _id(i))],
        items: [for (var i = 1; i <= 3; i++) _item(_id(200 + i), _id(100 + i))],
        pageSize: 2,
        log: log,
      );

      await repository.fetchPlanningSyncPayload(organizationId: _org);

      final streams = log.map((call) => call.stream).toList();
      expect(streams, [
        'plans',
        'plans',
        'plans',
        'sessions',
        'sessions',
        'sessions',
        'session_items',
        'session_items',
        'session_items',
      ]);
    });

    test('P3 a failure in any of the three streams throws', () async {
      for (final failing in ['plans', 'sessions', 'session_items']) {
        final repository = _repository(
          plans: [_plan(_id(1))],
          sessions: [_session(_id(2), _id(1))],
          items: [_item(_id(3), _id(2))],
          override: (stream) async =>
              stream == failing ? throw StateError('boom $failing') : null,
        );

        await expectLater(
          repository.fetchPlanningSyncPayload(organizationId: _org),
          throwsA(isA<StateError>()),
          reason: failing,
        );
      }
    });

    test('P4 an item whose session is unknown is dropped', () async {
      final repository = _repository(
        plans: [_plan(_id(1))],
        sessions: [_session(_id(2), _id(1))],
        items: [_item(_id(3), _id(2)), _item(_id(4), _id(99))],
      );

      final payload = await repository.fetchPlanningSyncPayload(
        organizationId: _org,
      );

      expect(payload.items.map((item) => item.id), [_id(3)]);
    });

    test('P4b a session whose plan is unknown is dropped, and so are its '
        'items', () async {
      final repository = _repository(
        plans: [_plan(_id(1))],
        sessions: [_session(_id(2), _id(1)), _session(_id(3), _id(99))],
        items: [_item(_id(4), _id(2)), _item(_id(5), _id(3))],
      );

      final payload = await repository.fetchPlanningSyncPayload(
        organizationId: _org,
      );

      expect(payload.sessions.map((session) => session.id), [_id(2)]);
      expect(payload.items.map((item) => item.id), [_id(4)]);
    });

    test('P5 shouldContinue false aborts and stops fetching', () async {
      final log = <_Call>[];
      final repository = _repository(
        plans: [_plan(_id(1))],
        sessions: [_session(_id(2), _id(1))],
        items: [_item(_id(3), _id(2))],
        log: log,
      );

      await expectLater(
        repository.fetchPlanningSyncPayload(
          organizationId: _org,
          shouldContinue: () => false,
        ),
        throwsA(isA<PagedReadAbortedException>()),
      );
      expect(log, isEmpty);
    });

    test('P5 an abort between streams fetches no later stream', () async {
      final log = <_Call>[];
      final repository = _repository(
        plans: [_plan(_id(1))],
        sessions: [_session(_id(2), _id(1))],
        items: [_item(_id(3), _id(2))],
        log: log,
      );

      await expectLater(
        repository.fetchPlanningSyncPayload(
          organizationId: _org,
          // true for the first plan page and its empty tail page, then stale.
          shouldContinue: () =>
              log.where((c) => c.stream == 'plans').length < 2,
        ),
        throwsA(isA<PagedReadAbortedException>()),
      );
      expect(log.map((call) => call.stream).toSet(), {'plans'});
    });

    test('P6 a session with more than 1000 items is complete', () async {
      final items = [
        for (var i = 1; i <= 1200; i++) _item(_id(1000 + i), _id(2)),
      ];
      final repository = _repository(
        plans: [_plan(_id(1))],
        sessions: [_session(_id(2), _id(1))],
        items: items,
        cap: 1000,
        pageSize: 1500,
      );

      final payload = await repository.fetchPlanningSyncPayload(
        organizationId: _org,
      );

      expect(payload.items, hasLength(1200));
    });

    test('P7 every stream is filtered by the organization id', () async {
      final log = <_Call>[];
      final repository = _repository(
        plans: [_plan(_id(1))],
        sessions: [_session(_id(2), _id(1))],
        items: [_item(_id(3), _id(2))],
        log: log,
      );

      await repository.fetchPlanningSyncPayload(organizationId: _org);

      expect(log, isNotEmpty);
      expect(log.map((call) => call.organizationId).toSet(), {_org});
      expect(log.map((call) => call.stream).toSet(), {
        'plans',
        'sessions',
        'session_items',
      });
    });

    test('the default page size is 500', () async {
      final log = <_Call>[];
      final repository = _repository(log: log);

      await repository.fetchPlanningSyncPayload(organizationId: _org);

      expect(log.map((call) => call.limit).toSet(), {500});
    });
  });

  group('production queries', () {
    SupabaseClient clientFor(
      List<Uri> requests,
      String Function(Uri url) bodyFor,
    ) {
      final client = SupabaseClient(
        'http://localhost:54321',
        'test-anon-key',
        httpClient: MockClient((request) async {
          requests.add(request.url);
          return http.Response(
            bodyFor(request.url),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      return client;
    }

    test('each stream is an org-scoped id.asc keyset query', () async {
      final requests = <Uri>[];
      final repository = SupabasePlanningRepository(
        clientFor(requests, (_) => '[]'),
        pageSize: 7,
      );

      await repository.fetchPlanningSyncPayload(organizationId: _org);

      expect(requests, hasLength(3));
      final expectations = {
        '/rest/v1/plans': 'content_version',
        '/rest/v1/sessions': 'plan_id',
        '/rest/v1/session_items': 'song:songs(id,slug,title)',
      };
      expect(requests.map((url) => url.path).toList(), expectations.keys);
      for (final url in requests) {
        final query = url.queryParameters;
        expect(query['order'], startsWith('id.asc'));
        expect(query['organization_id'], 'eq.$_org');
        expect(query['limit'], '7');
        expect(query.containsKey('id'), isFalse);
        expect(query['select'], contains(expectations[url.path]!));
      }
      expect(
        requests[2].queryParameters['select'],
        'id,session_id,position,song:songs(id,slug,title)',
      );
    });

    test('the production queries resume after the cursor with gt', () async {
      final planId = _id(1);
      final sessionId = _id(2);
      final itemId = _id(3);
      final requests = <Uri>[];
      final repository = SupabasePlanningRepository(
        clientFor(requests, (url) {
          final resumed = url.queryParameters.containsKey('id');
          if (resumed) {
            return '[]';
          }
          return switch (url.path) {
            '/rest/v1/plans' =>
              '[{"id":"$planId","organization_id":"$_org","slug":"p",'
                  '"name":"P","description":null,"scheduled_for":null,'
                  '"updated_at":"2026-03-31T09:00:00Z","version":1,'
                  '"content_version":1}]',
            '/rest/v1/sessions' =>
              '[{"id":"$sessionId","plan_id":"$planId","slug":"s",'
                  '"name":"S","position":1,"version":1}]',
            _ =>
              '[{"id":"$itemId","session_id":"$sessionId","position":1,'
                  '"song":{"id":"song-1","slug":"s","title":"T"}}]',
          };
        }),
        pageSize: 1,
      );

      final payload = await repository.fetchPlanningSyncPayload(
        organizationId: _org,
      );

      expect(requests, hasLength(6));
      expect(requests[1].path, '/rest/v1/plans');
      expect(requests[1].queryParameters['id'], 'gt.$planId');
      expect(requests[3].path, '/rest/v1/sessions');
      expect(requests[3].queryParameters['id'], 'gt.$sessionId');
      expect(requests[5].path, '/rest/v1/session_items');
      expect(requests[5].queryParameters['id'], 'gt.$itemId');
      expect(
        requests.map((url) => url.queryParameters['order']),
        everyElement(startsWith('id.asc')),
      );
      expect(payload.items.single.id, itemId);
    });
  });
}
