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

  group('splitSegmentsAtWordBoundaries', () {
    test('splits a multi-word segment, keeping the space on the left piece', () {
      final result = splitSegmentsAtWordBoundaries(const [
        SongReaderSegmentProjection(displayChord: 'E', text: 'alpha beta gamma'),
      ]);

      expect(
        result.map((s) => s.text).toList(),
        ['alpha ', 'beta ', 'gamma'],
      );
      // The chord belongs to the segment's start, so only the first piece keeps it.
      expect(result.map((s) => s.displayChord).toList(), ['E', null, null]);
    });

    test('concatenating the pieces reproduces the original text exactly', () {
      const original = '  alpha   beta  ';
      final result = splitSegmentsAtWordBoundaries(const [
        SongReaderSegmentProjection(displayChord: null, text: original),
      ]);

      expect(result.map((s) => s.text).join(), original);
    });

    test('leaves a single-word segment alone', () {
      final result = splitSegmentsAtWordBoundaries(const [
        SongReaderSegmentProjection(displayChord: 'G', text: 'alpha'),
      ]);

      expect(result, hasLength(1));
      expect(result.single.text, 'alpha');
      expect(result.single.displayChord, 'G');
    });

    test('leaves a chord-only segment alone', () {
      final result = splitSegmentsAtWordBoundaries(const [
        SongReaderSegmentProjection(displayChord: 'Am', text: ''),
        SongReaderSegmentProjection(displayChord: 'F', text: ''),
      ]);

      expect(result, hasLength(2));
      expect(result.map((s) => s.displayChord).toList(), ['Am', 'F']);
    });

    test('splits on tabs and unicode spaces, not only the ASCII space', () {
      final result = splitSegmentsAtWordBoundaries(const [
        SongReaderSegmentProjection(displayChord: null, text: 'alpha\tbeta　gamma'),
      ]);

      expect(result.map((s) => s.text).toList(), ['alpha\t', 'beta　', 'gamma']);
    });

    test('skips leading whitespace when assigning chord to first content piece', () {
      // ChordPro splits "alpha beta" at chord, producing segments with text
      // 'alpha' (no chord) and ' beta' (chord E). When ' beta' is split at
      // whitespace, the chord should land on 'beta', not on the leading ' '.
      final result = splitSegmentsAtWordBoundaries(const [
        SongReaderSegmentProjection(displayChord: null, text: 'alpha'),
        SongReaderSegmentProjection(displayChord: 'E', text: ' beta'),
      ]);

      expect(result.map((s) => s.text).toList(), [
        'alpha',
        ' ',
        'beta',
      ]);
      expect(result.map((s) => s.displayChord).toList(), [
        null,
        null,
        'E', // Chord on 'beta', not on ' '
      ]);
    });
  });

  group('groupSegmentsIntoWords after splitting', () {
    test('a word split by a chord change stays in one group', () {
      // The reproduction: ChordPro splits "Igédben" at the chord.
      final groups = groupSegmentsIntoWords(
        splitSegmentsAtWordBoundaries(const [
          SongReaderSegmentProjection(displayChord: 'E', text: 'alpha beta Igé'),
          SongReaderSegmentProjection(displayChord: 'G#m', text: 'dben gamma'),
        ]),
      );

      expect(
        groups.map((g) => g.segments.map((s) => s.text).join()).toList(),
        ['alpha ', 'beta ', 'Igédben ', 'gamma'],
      );
      // The chorded half of the split word keeps its own chord inside the group.
      final splitWord = groups[2].segments;
      expect(splitWord.map((s) => s.displayChord).toList(), ['E', 'G#m']);
    });
  });
}
