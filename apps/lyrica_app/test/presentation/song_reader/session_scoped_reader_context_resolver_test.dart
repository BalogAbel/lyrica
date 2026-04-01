import 'package:flutter_test/flutter_test.dart';
import 'package:lyrica_app/src/domain/planning/plan_detail.dart';
import 'package:lyrica_app/src/domain/planning/plan_summary.dart';
import 'package:lyrica_app/src/domain/planning/session_item_summary.dart';
import 'package:lyrica_app/src/domain/planning/session_summary.dart';
import 'package:lyrica_app/src/domain/song/song_summary.dart';
import 'package:lyrica_app/src/presentation/song_reader/session_scoped_reader_context.dart';
import 'package:lyrica_app/src/presentation/song_reader/session_scoped_reader_context_resolver.dart';

void main() {
  group('resolveSessionScopedReaderContext', () {
    test('resolves selected session item and same-session neighbors', () {
      final result = resolveSessionScopedReaderContext(
        planDetail: _planDetail(),
        planId: 'plan-1',
        sessionId: 'session-1',
        sessionItemId: 'item-20',
        songId: 'song-2',
      );

      expect(result, isA<ResolvedSessionScopedReaderContextResult>());
      final resolved = result as ResolvedSessionScopedReaderContextResult;
      expect(
        resolved.context,
        SessionScopedReaderContext(
          planId: 'plan-1',
          sessionId: 'session-1',
          sessionItemId: 'item-20',
          songId: 'song-2',
          selectedItem: const SessionScopedReaderNeighbor(
            sessionItemId: 'item-20',
            songId: 'song-2',
            title: 'Masodik',
          ),
          previousItem: const SessionScopedReaderNeighbor(
            sessionItemId: 'item-10',
            songId: 'song-1',
            title: 'Elso',
          ),
          nextItem: const SessionScopedReaderNeighbor(
            sessionItemId: 'item-30',
            songId: 'song-3',
            title: 'Harmadik',
          ),
        ),
      );
    });

    test('first item disables previous navigation', () {
      final result =
          resolveSessionScopedReaderContext(
                planDetail: _planDetail(),
                planId: 'plan-1',
                sessionId: 'session-1',
                sessionItemId: 'item-10',
                songId: 'song-1',
              )
              as ResolvedSessionScopedReaderContextResult;

      expect(result.context.previousItem, isNull);
      expect(result.context.nextItem?.sessionItemId, 'item-20');
    });

    test('last item disables next navigation', () {
      final result =
          resolveSessionScopedReaderContext(
                planDetail: _planDetail(),
                planId: 'plan-1',
                sessionId: 'session-1',
                sessionItemId: 'item-30',
                songId: 'song-3',
              )
              as ResolvedSessionScopedReaderContextResult;

      expect(result.context.previousItem?.sessionItemId, 'item-20');
      expect(result.context.nextItem, isNull);
    });

    test('single-item session disables both directions', () {
      final result =
          resolveSessionScopedReaderContext(
                planDetail: _singleItemPlanDetail(),
                planId: 'plan-1',
                sessionId: 'session-single',
                sessionItemId: 'item-1',
                songId: 'song-1',
              )
              as ResolvedSessionScopedReaderContextResult;

      expect(result.context.previousItem, isNull);
      expect(result.context.nextItem, isNull);
    });

    test('anchors duplicate-song navigation to session item id', () {
      final result =
          resolveSessionScopedReaderContext(
                planDetail: _duplicateSongPlanDetail(),
                planId: 'plan-1',
                sessionId: 'session-1',
                sessionItemId: 'item-20',
                songId: 'song-1',
              )
              as ResolvedSessionScopedReaderContextResult;

      expect(result.context.selectedItem.sessionItemId, 'item-20');
      expect(result.context.previousItem?.sessionItemId, 'item-10');
      expect(result.context.nextItem?.sessionItemId, 'item-30');
    });

    test(
      'returns explicit invalid result for mismatched session item song',
      () {
        final result = resolveSessionScopedReaderContext(
          planDetail: _planDetail(),
          planId: 'plan-1',
          sessionId: 'session-1',
          sessionItemId: 'item-20',
          songId: 'song-999',
        );

        expect(
          result,
          const SessionScopedReaderContextFailureResult(
            SessionScopedReaderContextFailure.invalidRouteContext,
          ),
        );
      },
    );
  });
}

PlanDetail _planDetail() {
  return PlanDetail(
    plan: PlanSummary(
      id: 'plan-1',
      name: 'Plan',
      description: 'Desc',
      scheduledFor: DateTime(2026, 4, 1, 10),
      updatedAt: DateTime(2026, 4, 1, 9),
    ),
    sessions: const [
      SessionSummary(
        id: 'session-1',
        name: 'Main',
        position: 10,
        items: [
          SessionItemSummary(
            id: 'item-10',
            position: 10,
            song: SongSummary(id: 'song-1', title: 'Elso'),
          ),
          SessionItemSummary(
            id: 'item-20',
            position: 20,
            song: SongSummary(id: 'song-2', title: 'Masodik'),
          ),
          SessionItemSummary(
            id: 'item-30',
            position: 30,
            song: SongSummary(id: 'song-3', title: 'Harmadik'),
          ),
        ],
      ),
    ],
  );
}

PlanDetail _singleItemPlanDetail() {
  return PlanDetail(
    plan: PlanSummary(
      id: 'plan-1',
      name: 'Plan',
      description: 'Desc',
      scheduledFor: DateTime(2026, 4, 1, 10),
      updatedAt: DateTime(2026, 4, 1, 9),
    ),
    sessions: const [
      SessionSummary(
        id: 'session-single',
        name: 'Solo',
        position: 10,
        items: [
          SessionItemSummary(
            id: 'item-1',
            position: 10,
            song: SongSummary(id: 'song-1', title: 'Elso'),
          ),
        ],
      ),
    ],
  );
}

PlanDetail _duplicateSongPlanDetail() {
  return PlanDetail(
    plan: PlanSummary(
      id: 'plan-1',
      name: 'Plan',
      description: 'Desc',
      scheduledFor: DateTime(2026, 4, 1, 10),
      updatedAt: DateTime(2026, 4, 1, 9),
    ),
    sessions: const [
      SessionSummary(
        id: 'session-1',
        name: 'Main',
        position: 10,
        items: [
          SessionItemSummary(
            id: 'item-10',
            position: 10,
            song: SongSummary(id: 'song-1', title: 'A forrasnal'),
          ),
          SessionItemSummary(
            id: 'item-20',
            position: 20,
            song: SongSummary(id: 'song-1', title: 'A forrasnal'),
          ),
          SessionItemSummary(
            id: 'item-30',
            position: 30,
            song: SongSummary(id: 'song-2', title: 'Kovetkezo'),
          ),
        ],
      ),
    ],
  );
}
