import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_word_groups.dart';

SongReaderSegmentProjection _segment(String text, {String? chord}) =>
    SongReaderSegmentProjection(text: text, displayChord: chord);

void main() {
  test('keeps a chord-split word in one group', () {
    final groups = groupSegmentsIntoWords([
      _segment('por', chord: 'C'),
      _segment('cikám,', chord: 'D'),
    ]);
    expect(groups, hasLength(1));
    expect(groups.single.segments.map((s) => s.text), ['por', 'cikám,']);
  });

  test('a whitespace-only segment stands alone between two words', () {
    // A bare separator segment has a boundary on both sides — it ends with
    // whitespace and starts with whitespace — so it neither glues its
    // neighbours together nor attaches to either of them.
    final groups = groupSegmentsIntoWords([
      _segment('minden', chord: 'C'),
      _segment(' '),
      _segment('porcikám', chord: 'D'),
    ]);

    expect(groups, hasLength(3));
    expect(groups[0].segments.map((s) => s.text), ['minden']);
    expect(groups[1].segments.map((s) => s.text), [' ']);
    expect(groups[2].segments.map((s) => s.text), ['porcikám']);
  });

  test('keeps every segment when a single group spans the whole line', () {
    // A long word carrying several chords stays one group even though it will
    // be wider than any realistic line; the renderer breaks it internally as a
    // last resort, but nothing may be dropped here.
    final segments = [
      for (var index = 0; index < 12; index++)
        _segment('szotag$index', chord: 'C'),
    ];

    final groups = groupSegmentsIntoWords(segments);

    expect(groups, hasLength(1));
    expect(groups.single.segments, hasLength(segments.length));
  });

  test('starts a new group after a trailing space', () {
    final groups = groupSegmentsIntoWords([
      _segment('minden ', chord: 'C'),
      _segment('porcikám', chord: 'D'),
    ]);
    expect(groups, hasLength(2));
  });

  test('starts a new group when the next segment leads with a space', () {
    final groups = groupSegmentsIntoWords([
      _segment('minden', chord: 'C'),
      _segment(' porcikám', chord: 'D'),
    ]);
    expect(groups, hasLength(2));
  });

  test('attaches a chord-only segment to the group that follows it', () {
    final groups = groupSegmentsIntoWords([
      _segment('', chord: 'C'),
      _segment('porcikám', chord: 'D'),
    ]);
    expect(groups, hasLength(1));
    expect(groups.single.segments, hasLength(2));
  });

  test('does not sub-split a segment that contains an internal space', () {
    final groups = groupSegmentsIntoWords([_segment('minden porcikám')]);
    expect(groups, hasLength(1));
    expect(groups.single.segments.single.text, 'minden porcikám');
  });

  test('returns no groups for an empty segment list', () {
    expect(groupSegmentsIntoWords(const []), isEmpty);
  });
}
