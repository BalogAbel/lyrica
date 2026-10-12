import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/shared/keyset_paging.dart';

/// Serves scripted pages and records every `(after, limit)` call.
class _ScriptedFetcher<R, K> {
  _ScriptedFetcher(this.pages);

  final List<List<R>> pages;
  final calls = <({K? after, int limit})>[];

  Future<List<R>> call({required K? after, required int limit}) async {
    calls.add((after: after, limit: limit));
    final index = calls.length - 1;
    return index < pages.length ? pages[index] : <R>[];
  }
}

/// Keyset semantics over a sorted list, with a server cap below the limit.
class _CappedServer {
  _CappedServer(this.rows, {required this.cap});

  final List<int> rows;
  final int cap;
  final calls = <({int? after, int limit})>[];

  Future<List<int>> call({required int? after, required int limit}) async {
    calls.add((after: after, limit: limit));
    final take = limit < cap ? limit : cap;
    return rows.where((r) => after == null || r > after).take(take).toList();
  }
}

int _compareInts(int a, int b) => a.compareTo(b);

List<int> _bytesOf(String uuid) {
  final hex = uuid.replaceAll('-', '');
  return [
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ];
}

int _byteCompare(String a, String b) {
  final x = _bytesOf(a);
  final y = _bytesOf(b);
  for (var i = 0; i < x.length; i++) {
    final c = x[i].compareTo(y[i]);
    if (c != 0) return c.sign;
  }
  return 0;
}

void main() {
  group('readAllKeysetPages', () {
    test(
      'H1 an empty first page returns [] after one fetch with after null',
      () async {
        final fetcher = _ScriptedFetcher<int, int>([<int>[]]);

        final rows = await readAllKeysetPages<int, int>(
          fetchPage: fetcher.call,
          keyOf: (r) => r,
          compareKeys: _compareInts,
          pageSize: 3,
        );

        expect(rows, isEmpty);
        expect(fetcher.calls, hasLength(1));
        expect(fetcher.calls.single.after, isNull);
        expect(fetcher.calls.single.limit, 3);
      },
    );

    test(
      'H2 full pages are concatenated; after is the previous last key',
      () async {
        final fetcher = _ScriptedFetcher<int, int>([
          [1, 2, 3],
          [4, 5, 6],
          [7],
        ]);

        final rows = await readAllKeysetPages<int, int>(
          fetchPage: fetcher.call,
          keyOf: (r) => r,
          compareKeys: _compareInts,
          pageSize: 3,
        );

        expect(rows, [1, 2, 3, 4, 5, 6, 7]);
        expect(fetcher.calls.map((c) => c.after), [null, 3, 6, 7]);
        expect(fetcher.calls.map((c) => c.limit), everyElement(3));
      },
    );

    test(
      'H3 a short page is not an end; only an empty page ends the read',
      () async {
        final server = _CappedServer([for (var i = 1; i <= 10; i++) i], cap: 4);

        final rows = await readAllKeysetPages<int, int>(
          fetchPage: server.call,
          keyOf: (r) => r,
          compareKeys: _compareInts,
          pageSize: 100,
        );

        expect(rows, [for (var i = 1; i <= 10; i++) i]);
        // 4 + 4 + 2 rows, then the empty page.
        expect(server.calls, hasLength(4));
        expect(server.calls.map((c) => c.after), [null, 4, 8, 10]);
      },
    );

    test(
      'H4 a key equal to or below the cursor throws keyNotIncreasing',
      () async {
        for (final overlap in [
          [3], // equal to the cursor (duplicate)
          [2, 4], // below the cursor (overlap with an earlier page)
        ]) {
          final fetcher = _ScriptedFetcher<int, int>([
            [1, 2, 3],
            overlap,
          ]);

          await expectLater(
            readAllKeysetPages<int, int>(
              fetchPage: fetcher.call,
              keyOf: (r) => r,
              compareKeys: _compareInts,
              pageSize: 3,
              stream: 'songs',
            ),
            throwsA(
              isA<PagedReadContractException>()
                  .having(
                    (e) => e.reason,
                    'reason',
                    PagedReadContractViolation.keyNotIncreasing,
                  )
                  .having((e) => e.stream, 'stream', 'songs')
                  .having((e) => e.pageIndex, 'pageIndex', 1),
            ),
          );
          expect(fetcher.calls, hasLength(2));
        }
      },
    );

    test(
      'H5 an out-of-order key inside a page throws keyNotIncreasing',
      () async {
        final fetcher = _ScriptedFetcher<int, int>([
          [1, 3, 2],
        ]);

        await expectLater(
          readAllKeysetPages<int, int>(
            fetchPage: fetcher.call,
            keyOf: (r) => r,
            compareKeys: _compareInts,
            pageSize: 5,
          ),
          throwsA(
            isA<PagedReadContractException>()
                .having(
                  (e) => e.reason,
                  'reason',
                  PagedReadContractViolation.keyNotIncreasing,
                )
                .having((e) => e.stream, 'stream', 'unnamed')
                .having((e) => e.pageIndex, 'pageIndex', 0),
          ),
        );
      },
    );

    test('H6 a page longer than limit throws pageOverLimit', () async {
      final fetcher = _ScriptedFetcher<int, int>([
        [1, 2, 3],
        [4, 5, 6],
      ]);

      await expectLater(
        readAllKeysetPages<int, int>(
          fetchPage: fetcher.call,
          keyOf: (r) => r,
          compareKeys: _compareInts,
          pageSize: 2,
        ),
        throwsA(
          isA<PagedReadContractException>()
              .having(
                (e) => e.reason,
                'reason',
                PagedReadContractViolation.pageOverLimit,
              )
              .having((e) => e.pageIndex, 'pageIndex', 0),
        ),
      );
      expect(fetcher.calls, hasLength(1));
    });

    test('the contract exception message carries no keys or row data', () {
      const exception = PagedReadContractException(
        stream: 'songs',
        pageIndex: 2,
        reason: PagedReadContractViolation.keyNotIncreasing,
      );

      final text = exception.toString();
      expect(text, contains('songs'));
      expect(text, contains('2'));
      expect(text, contains('keyNotIncreasing'));
    });

    test('H7 a failure on page k propagates and returns no result', () async {
      final error = StateError('boom');
      var call = 0;

      final future = readAllKeysetPages<int, int>(
        fetchPage: ({required int? after, required int limit}) async {
          call++;
          if (call == 3) throw error;
          return call == 1 ? [1, 2] : [3, 4];
        },
        keyOf: (r) => r,
        compareKeys: _compareInts,
        pageSize: 2,
      );

      await expectLater(future, throwsA(same(error)));
      expect(call, 3);
    });

    test(
      'H8 shouldContinue false between pages aborts and fetches nothing more',
      () async {
        final fetcher = _ScriptedFetcher<int, int>([
          [1, 2],
          [3, 4],
        ]);
        var allowed = true;

        await expectLater(
          readAllKeysetPages<int, int>(
            fetchPage: ({required int? after, required int limit}) {
              final result = fetcher.call(after: after, limit: limit);
              // The generation changes while the first page is in flight.
              allowed = false;
              return result;
            },
            keyOf: (r) => r,
            compareKeys: _compareInts,
            pageSize: 2,
            shouldContinue: () => allowed,
            stream: 'plans',
          ),
          throwsA(
            isA<PagedReadAbortedException>().having(
              (e) => e.stream,
              'stream',
              'plans',
            ),
          ),
        );
        expect(fetcher.calls, hasLength(1));
      },
    );

    test(
      'H8 shouldContinue false before the first fetch fetches nothing',
      () async {
        final fetcher = _ScriptedFetcher<int, int>([
          [1],
        ]);

        await expectLater(
          readAllKeysetPages<int, int>(
            fetchPage: fetcher.call,
            keyOf: (r) => r,
            compareKeys: _compareInts,
            pageSize: 2,
            shouldContinue: () => false,
          ),
          throwsA(isA<PagedReadAbortedException>()),
        );
        expect(fetcher.calls, isEmpty);
      },
    );

    test('H8 shouldContinue true throughout does not abort', () async {
      final fetcher = _ScriptedFetcher<int, int>([
        [1, 2],
      ]);

      final rows = await readAllKeysetPages<int, int>(
        fetchPage: fetcher.call,
        keyOf: (r) => r,
        compareKeys: _compareInts,
        pageSize: 2,
        shouldContinue: () => true,
      );

      expect(rows, [1, 2]);
    });

    test('H9 a generic integer key pages with an integer comparator', () async {
      final fetcher = _ScriptedFetcher<int, int>([
        [8, 9],
        [10, 11],
      ]);

      final rows = await readAllKeysetPages<int, int>(
        fetchPage: fetcher.call,
        keyOf: (r) => r,
        compareKeys: _compareInts,
        pageSize: 2,
      );

      // 10 after 9: numeric order, not string order.
      expect(rows, [8, 9, 10, 11]);
      expect(fetcher.calls.map((c) => c.after), [null, 9, 11]);
    });

    test('a non-positive pageSize throws ArgumentError', () async {
      final fetcher = _ScriptedFetcher<int, int>([]);

      for (final size in [0, -1]) {
        await expectLater(
          () => readAllKeysetPages<int, int>(
            fetchPage: fetcher.call,
            keyOf: (r) => r,
            compareKeys: _compareInts,
            pageSize: size,
          ),
          throwsArgumentError,
        );
      }
      expect(fetcher.calls, isEmpty);
    });
  });

  group('compareUuidKeys', () {
    test('H10 agrees with byte order for fixed canonical lowercase uuids', () {
      const pairs = [
        // digit/letter boundary
        (
          '00000000-0000-0000-0000-000000000009',
          '00000000-0000-0000-0000-00000000000a',
        ),
        (
          '9fffffff-ffff-ffff-ffff-ffffffffffff',
          'a0000000-0000-0000-0000-000000000000',
        ),
        // extremes
        (
          '00000000-0000-0000-0000-000000000000',
          'ffffffff-ffff-ffff-ffff-ffffffffffff',
        ),
        // difference in the last byte only / across a dash
        (
          '12345678-1234-1234-1234-123456789abc',
          '12345678-1234-1234-1234-123456789abd',
        ),
        (
          '12345678-1234-1234-1234-123456789abc',
          '12345678-1234-1235-0000-000000000000',
        ),
        // equal
        (
          'a1b2c3d4-0000-4000-8000-0123456789ab',
          'a1b2c3d4-0000-4000-8000-0123456789ab',
        ),
      ];

      for (final (a, b) in pairs) {
        expect(
          compareUuidKeys(a, b).sign,
          _byteCompare(a, b),
          reason: 'compareUuidKeys($a, $b)',
        );
        expect(
          compareUuidKeys(b, a).sign,
          _byteCompare(b, a),
          reason: 'compareUuidKeys($b, $a)',
        );
      }
    });
  });
}
