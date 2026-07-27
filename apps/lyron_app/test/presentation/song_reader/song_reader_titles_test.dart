import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/domain/planning/plan_detail.dart';
import 'package:lyron_app/src/domain/planning/plan_summary.dart';
import 'package:lyron_app/src/domain/planning/session_item_summary.dart';
import 'package:lyron_app/src/domain/planning/session_summary.dart';
import 'package:lyron_app/src/domain/song/parsed_song.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/presentation/song_reader/session_scoped_reader_context.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_titles.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

SongReaderProjection _projectionWithTitle(String title) {
  return SongReaderProjection(
    song: ParsedSong(title: title, sections: const [], diagnostics: const []),
    state: SongReaderState(),
  );
}

SessionScopedReaderContext _scopedContext({required String selectedTitle}) {
  return SessionScopedReaderContext(
    planId: 'plan-1',
    planSlug: 'plan-1',
    sessionId: 'session-1',
    sessionSlug: 'session-1',
    sessionItemId: 'item-1',
    songId: 'song-1',
    selectedItem: SessionScopedReaderNeighbor(
      sessionItemId: 'item-1',
      songId: 'song-1',
      title: selectedTitle,
    ),
    previousItem: null,
    nextItem: null,
  );
}

void main() {
  group('resolveCurrentTitle', () {
    test('prefers the scoped item title when non-empty', () {
      final title = resolveCurrentTitle(
        scopedContext: _scopedContext(selectedTitle: 'Scoped Title'),
        projection: _projectionWithTitle('Parsed Title'),
      );

      expect(title, 'Scoped Title');
    });

    test(
      'falls back to the parsed song title when the scoped title is blank',
      () {
        final title = resolveCurrentTitle(
          scopedContext: _scopedContext(selectedTitle: '   '),
          projection: _projectionWithTitle('Parsed Title'),
        );

        expect(title, 'Parsed Title');
      },
    );

    test(
      'falls back to the parsed song title when there is no scoped context',
      () {
        final title = resolveCurrentTitle(
          scopedContext: null,
          projection: _projectionWithTitle('Parsed Title'),
        );

        expect(title, 'Parsed Title');
      },
    );
  });

  group('resolvePreservedScopedTitle', () {
    test('prefers the scoped item title when non-empty', () {
      final title = resolvePreservedScopedTitle(
        scopedContext: _scopedContext(selectedTitle: 'Scoped Title'),
        warmPlanDetail: null,
        sessionItemId: 'item-1',
        songId: 'song-1',
      );

      expect(title, 'Scoped Title');
    });

    test(
      'falls back to the matching item title preserved in warmPlanDetail',
      () {
        final planDetail = PlanDetail(
          plan: PlanSummary(
            id: 'plan-1',
            slug: 'plan-1',
            name: 'Plan',
            description: null,
            scheduledFor: null,
            updatedAt: DateTime(2026, 1, 1),
          ),
          sessions: const [
            SessionSummary(
              id: 'session-1',
              slug: 'session-1',
              name: 'Session',
              position: 10,
              items: [
                SessionItemSummary(
                  id: 'item-1',
                  position: 10,
                  song: SongSummary(id: 'song-1', title: 'Preserved Title'),
                ),
              ],
            ),
          ],
        );

        final title = resolvePreservedScopedTitle(
          scopedContext: null,
          warmPlanDetail: planDetail,
          sessionItemId: 'item-1',
          songId: 'song-1',
        );

        expect(title, 'Preserved Title');
      },
    );

    test(
      'falls back to the generic reader title when nothing else resolves',
      () {
        final title = resolvePreservedScopedTitle(
          scopedContext: null,
          warmPlanDetail: null,
          sessionItemId: null,
          songId: 'song-1',
        );

        expect(title, AppStrings.songReaderTitle);
      },
    );

    test(
      'does not use a warmPlanDetail item that does not match the song id',
      () {
        final planDetail = PlanDetail(
          plan: PlanSummary(
            id: 'plan-1',
            slug: 'plan-1',
            name: 'Plan',
            description: null,
            scheduledFor: null,
            updatedAt: DateTime(2026, 1, 1),
          ),
          sessions: const [
            SessionSummary(
              id: 'session-1',
              slug: 'session-1',
              name: 'Session',
              position: 10,
              items: [
                SessionItemSummary(
                  id: 'item-1',
                  position: 10,
                  song: SongSummary(id: 'song-other', title: 'Wrong Song'),
                ),
              ],
            ),
          ],
        );

        final title = resolvePreservedScopedTitle(
          scopedContext: null,
          warmPlanDetail: planDetail,
          sessionItemId: 'item-1',
          songId: 'song-1',
        );

        expect(title, AppStrings.songReaderTitle);
      },
    );
  });

  group('resolveNeighborTitle', () {
    test('trims a non-empty title', () {
      expect(resolveNeighborTitle('  Next Song  '), 'Next Song');
    });

    test('returns null for a null title', () {
      expect(resolveNeighborTitle(null), isNull);
    });

    test('returns null for a blank title', () {
      expect(resolveNeighborTitle('   '), isNull);
    });
  });
}
