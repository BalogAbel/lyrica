import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/infrastructure/song_library/supabase_song_repository.dart';
import 'package:lyron_app/src/shared/keyset_paging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/keyset_pages.dart';

void main() {
  catalogTests();
}

const _org = 'org-1';

Map<String, dynamic> _songRow(
  String id,
  String title, {
  Object? source = '{title:x}',
  String? slug,
  int? version,
}) => {
  'id': id,
  'slug': slug,
  'title': title,
  'version': version,
  'chordpro_source': source,
};

class _CatalogCall {
  _CatalogCall(this.organizationId, this.after, this.limit);

  final String organizationId;
  final String? after;
  final int limit;
}

SupabaseSongRepository _catalogRepository(
  List<Map<String, dynamic>> rows, {
  int? cap,
  int pageSize = 100,
  List<_CatalogCall>? calls,
  Future<void> Function(int callIndex)? onPage,
}) {
  var index = 0;
  return SupabaseSongRepository.testing(
    catalogPageSize: pageSize,
    fetchCatalogPage:
        ({required organizationId, required after, required limit}) async {
          calls?.add(_CatalogCall(organizationId, after, limit));
          await onPage?.call(index++);
          return keysetPage(rows, after: after, limit: limit, cap: cap);
        },
  );
}

void catalogTests() {
  group('fetchCatalog (PG3, PG4)', () {
    const a = '00000000-0000-4000-8000-00000000000a';
    const b = '00000000-0000-4000-8000-00000000000b';
    const c = '00000000-0000-4000-8000-00000000000c';
    const d = '00000000-0000-4000-8000-00000000000d';

    test(
      'S1 every page request carries the organization id and the cursor',
      () async {
        final calls = <_CatalogCall>[];
        final repository = _catalogRepository(
          [_songRow(a, 'A'), _songRow(b, 'B'), _songRow(c, 'C')],
          pageSize: 2,
          calls: calls,
        );

        await repository.fetchCatalog(organizationId: _org);

        expect(calls.map((call) => call.organizationId), everyElement(_org));
        expect(calls.map((call) => call.after), [null, b, c]);
        expect(calls.map((call) => call.limit), everyElement(2));
      },
    );

    test('S2 summaries and sources come from the same rows, sorted by title '
        'then id', () async {
      final repository = _catalogRepository([
        _songRow(d, 'Beta', source: 'src-d', version: 3, slug: 'beta-d'),
        _songRow(c, 'Alpha', source: 'src-c'),
        _songRow(b, 'Beta', source: 'src-b', slug: 'beta-b'),
        _songRow(a, 'Zeta', source: 'src-a'),
      ], pageSize: 3);

      final payload = await repository.fetchCatalog(organizationId: _org);

      expect(payload.summaries, [
        const SongSummary(id: c, title: 'Alpha'),
        const SongSummary(id: b, title: 'Beta', slug: 'beta-b', version: 1),
        const SongSummary(id: d, title: 'Beta', slug: 'beta-d', version: 3),
        const SongSummary(id: a, title: 'Zeta'),
      ]);
      expect(payload.sources.map((source) => source.id), [c, b, d, a]);
      expect(payload.sources.map((source) => source.source), [
        'src-c',
        'src-b',
        'src-d',
        'src-a',
      ]);
    });

    test('S3 with a cap below the page size the catalog is complete', () async {
      final calls = <_CatalogCall>[];
      final repository = _catalogRepository(
        [
          _songRow(a, 'A'),
          _songRow(b, 'B'),
          _songRow(c, 'C'),
          _songRow(d, 'D'),
        ],
        cap: 1,
        pageSize: 100,
        calls: calls,
      );

      final payload = await repository.fetchCatalog(organizationId: _org);

      expect(payload.summaries.map((song) => song.id), [a, b, c, d]);
      expect(payload.sources, hasLength(4));
      expect(calls, hasLength(5));
    });

    test('S4 a page failure throws', () async {
      final repository = _catalogRepository(
        [_songRow(a, 'A'), _songRow(b, 'B')],
        pageSize: 1,
        onPage: (index) async {
          if (index == 1) throw StateError('page boom');
        },
      );

      await expectLater(
        repository.fetchCatalog(organizationId: _org),
        throwsA(isA<StateError>()),
      );
    });

    test('S4 a row without a chordpro_source string throws', () async {
      final repository = _catalogRepository([
        _songRow(a, 'A'),
        _songRow(b, 'B', source: null),
      ]);

      await expectLater(
        repository.fetchCatalog(organizationId: _org),
        throwsA(isA<StateError>()),
      );
    });

    test(
      'the production query pages ascending by id within the organization',
      () async {
        final requests = <Uri>[];
        final client = SupabaseClient(
          'http://localhost:54321',
          'test-anon-key',
          httpClient: MockClient((request) async {
            requests.add(request.url);
            return http.Response(
              '[]',
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }),
        );
        addTearDown(client.dispose);
        final repository = SupabaseSongRepository(client, catalogPageSize: 7);

        await repository.fetchCatalog(organizationId: _org);

        expect(requests, hasLength(1));
        final query = requests.single.queryParameters;
        expect(requests.single.path, endsWith('/rest/v1/songs'));
        expect(query['order'], startsWith('id.asc'));
        expect(query['organization_id'], 'eq.$_org');
        expect(query['limit'], '7');
        expect(query['select'], contains('chordpro_source'));
        expect(query.containsKey('id'), isFalse);
      },
    );

    test('the production query resumes after the cursor with gt', () async {
      const first = '00000000-0000-4000-8000-00000000000a';
      final requests = <Uri>[];
      final client = SupabaseClient(
        'http://localhost:54321',
        'test-anon-key',
        httpClient: MockClient((request) async {
          requests.add(request.url);
          final body = requests.length == 1
              ? '[{"id":"$first","slug":"s","title":"T","version":1,'
                    '"chordpro_source":"x"}]'
              : '[]';
          return http.Response(
            body,
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      final repository = SupabaseSongRepository(client, catalogPageSize: 1);

      final payload = await repository.fetchCatalog(organizationId: _org);

      expect(payload.summaries.single.id, first);
      expect(requests, hasLength(2));
      expect(requests[1].queryParameters['id'], 'gt.$first');
      expect(requests[1].queryParameters['order'], startsWith('id.asc'));
    });

    test('an empty first page gives an empty payload', () async {
      final repository = _catalogRepository(const []);

      final payload = await repository.fetchCatalog(organizationId: _org);

      expect(payload.summaries, isEmpty);
      expect(payload.sources, isEmpty);
    });

    test('shouldContinue false aborts without fetching', () async {
      final calls = <_CatalogCall>[];
      final repository = _catalogRepository([_songRow(a, 'A')], calls: calls);

      await expectLater(
        repository.fetchCatalog(
          organizationId: _org,
          shouldContinue: () => false,
        ),
        throwsA(isA<PagedReadAbortedException>()),
      );
      expect(calls, isEmpty);
    });

    test('a PostgrestException from a page propagates unchanged', () async {
      const failure = PostgrestException(
        message: 'permission denied',
        code: '42501',
      );
      final repository = _catalogRepository([
        _songRow(a, 'A'),
      ], onPage: (index) async => throw failure);

      await expectLater(
        repository.fetchCatalog(organizationId: _org),
        throwsA(same(failure)),
      );
    });
  });
}
