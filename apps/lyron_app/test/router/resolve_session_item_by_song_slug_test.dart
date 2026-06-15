import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/domain/planning/session_item_summary.dart';
import 'package:lyron_app/src/domain/planning/session_summary.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/router/slug_route_resolvers.dart';

void main() {
  SessionSummary sessionWith(List<SessionItemSummary> items) => SessionSummary(
    id: 'session-1',
    slug: 'main-set',
    name: 'Main Set',
    position: 10,
    items: items,
  );

  group('resolveSessionItemBySongSlug', () {
    test(
      'matches against the canonical library slug when plan detail lacks it',
      () {
        // Offline plan detail: the cached song has no slug, so SongSummary falls
        // back to the song id. Neighbor navigation builds the URL from the
        // library's canonical slug, so the resolver must canonicalize too.
        final session = sessionWith(const [
          SessionItemSummary(
            id: 'item-1',
            position: 10,
            song: SongSummary(id: 'song-1', title: 'A forrásnál'),
          ),
        ]);
        final songsById = {
          'song-1': const SongSummary(
            id: 'song-1',
            slug: 'a-forrasnal',
            title: 'A forrásnál',
          ),
        };

        final item = resolveSessionItemBySongSlug(
          session: session,
          songSlug: 'a-forrasnal',
          songsById: songsById,
        );

        expect(item?.id, 'item-1');
      },
    );

    test('matches against the song id (legacy/initial url form)', () {
      final session = sessionWith(const [
        SessionItemSummary(
          id: 'item-1',
          position: 10,
          song: SongSummary(id: 'song-1', title: 'A forrásnál'),
        ),
      ]);

      final item = resolveSessionItemBySongSlug(
        session: session,
        songSlug: 'song-1',
        songsById: const {},
      );

      expect(item?.id, 'item-1');
    });

    test('matches against the raw plan detail slug (online form)', () {
      final session = sessionWith(const [
        SessionItemSummary(
          id: 'item-1',
          position: 10,
          song: SongSummary(
            id: 'song-1',
            slug: 'a-forrasnal',
            title: 'A forrásnál',
          ),
        ),
      ]);

      final item = resolveSessionItemBySongSlug(
        session: session,
        songSlug: 'a-forrasnal',
        songsById: const {},
      );

      expect(item?.id, 'item-1');
    });

    test('returns null when no item matches', () {
      final session = sessionWith(const [
        SessionItemSummary(
          id: 'item-1',
          position: 10,
          song: SongSummary(id: 'song-1', title: 'A forrásnál'),
        ),
      ]);

      final item = resolveSessionItemBySongSlug(
        session: session,
        songSlug: 'missing',
        songsById: const {},
      );

      expect(item, isNull);
    });

    test('returns null when the match is ambiguous', () {
      final session = sessionWith(const [
        SessionItemSummary(
          id: 'item-1',
          position: 10,
          song: SongSummary(id: 'song-1', title: 'A forrásnál'),
        ),
        SessionItemSummary(
          id: 'item-2',
          position: 20,
          song: SongSummary(id: 'song-2', title: 'A forrásnál (reprise)'),
        ),
      ]);
      // Both library songs canonicalize to the same slug.
      final songsById = {
        'song-1': const SongSummary(
          id: 'song-1',
          slug: 'a-forrasnal',
          title: 'A forrásnál',
        ),
        'song-2': const SongSummary(
          id: 'song-2',
          slug: 'a-forrasnal',
          title: 'A forrásnál (reprise)',
        ),
      };

      final item = resolveSessionItemBySongSlug(
        session: session,
        songSlug: 'a-forrasnal',
        songsById: songsById,
      );

      expect(item, isNull);
    });
  });
}
