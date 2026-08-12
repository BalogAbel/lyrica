import 'dart:io';

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

  test('a whitespace-only segment joins the group before it, not its own', () {
    // A bare separator segment ends with whitespace, so the word after it
    // still starts a fresh group normally -- but the separator itself is
    // never left free to start a NEW group on its own (PR review round,
    // 2026-08-12): that would make it a standalone box the outer Wrap could
    // place at the START of a wrapped row, indistinguishable from a real
    // blank leading indent. Landing at the END of the previous group instead
    // is invisible at that same wrap point, exactly as trailing whitespace
    // on any other piece already is.
    final groups = groupSegmentsIntoWords([
      _segment('minden', chord: 'C'),
      _segment(' '),
      _segment('porcikám', chord: 'D'),
    ]);

    expect(groups, hasLength(2));
    expect(groups[0].segments.map((s) => s.text), ['minden', ' ']);
    expect(groups[1].segments.map((s) => s.text), ['porcikám']);
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

  test('a whitespace-only segment carrying its own chord still joins the '
      'group before it (PR review round, 2026-08-12)', () {
    // Not every whitespace-only segment comes from
    // splitSegmentsAtWordBoundaries -- the real parser can emit one
    // directly (song_line_view_test.dart has a fixture: a bare '   '
    // segment carrying a chord, used to align a chord that has no lyric
    // syllable of its own under it). The "joins the group before it" rule
    // applies the same way regardless of source: the chord still renders
    // (SongReaderWordGroup keeps every segment, including this one), but
    // the segment itself cannot open a fresh outer-Wrap row by itself.
    final groups = groupSegmentsIntoWords([
      _segment('minden', chord: 'C'),
      _segment('   ', chord: 'A'),
      _segment('porcikám', chord: 'D'),
    ]);

    expect(groups, hasLength(2));
    expect(groups[0].segments.map((s) => s.text).toList(), ['minden', '   ']);
    expect(groups[0].segments.map((s) => s.displayChord).toList(), ['C', 'A']);
    expect(groups[1].segments.single.text, 'porcikám');
  });

  test('a mandatory line-break character also ends a group (PR review round, '
      '2026-08-12)', () {
    // \n, \r, U+2028, U+2029, U+0085, U+000B and U+000C force a real line
    // break wherever Flutter's line breaker sees them, independent of
    // available width -- the same set song_reader_fit.dart's
    // _mandatoryLineBreak models. A forced break is always a safe place
    // for the outer Wrap to break too (a superset of an ordinary
    // readerBreakableWhitespace opportunity), so a piece ending in one of
    // these must still end its group, the same as it did before
    // _endsWithWhitespace moved off String.trim* onto the shared
    // whitespace class (trim* happened to strip these too; the class
    // alone does not, since they are forced breaks, not ordinary
    // whitespace opportunities).
    final mandatoryBreakCodes = [
      0x0A, // LINE FEED
      0x0D, // CARRIAGE RETURN
      0x2028, // LINE SEPARATOR
      0x2029, // PARAGRAPH SEPARATOR
      0x0085, // NEXT LINE
      0x000B, // VERTICAL TAB
      0x000C, // FORM FEED
    ];
    for (final code in mandatoryBreakCodes) {
      final mandatoryBreak = String.fromCharCode(code);
      final groups = groupSegmentsIntoWords([
        _segment('minden$mandatoryBreak', chord: 'C'),
        _segment('porcikám', chord: 'D'),
      ]);
      expect(
        groups,
        hasLength(2),
        reason: 'failed for U+${code.toRadixString(16)}',
      );
    }
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
        SongReaderSegmentProjection(
          displayChord: 'E',
          text: 'alpha beta gamma',
        ),
      ]);

      expect(result.map((s) => s.text).toList(), ['alpha ', 'beta ', 'gamma']);
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
        SongReaderSegmentProjection(
          displayChord: null,
          text: 'alpha\tbeta　gamma',
        ),
      ]);

      expect(result.map((s) => s.text).toList(), ['alpha\t', 'beta　', 'gamma']);
    });

    test(
      'skips leading whitespace when assigning chord to first content piece',
      () {
        // ChordPro splits "alpha beta" at chord, producing segments with text
        // 'alpha' (no chord) and ' beta' (chord E). When ' beta' is split at
        // whitespace, the chord should land on 'beta', not on the leading ' '.
        // (The lone ' ' piece not being free to start its own outer-Wrap row
        // is a grouping concern, not a splitting one -- see
        // groupSegmentsIntoWords' "leading whitespace" test below.)
        final result = splitSegmentsAtWordBoundaries(const [
          SongReaderSegmentProjection(displayChord: null, text: 'alpha'),
          SongReaderSegmentProjection(displayChord: 'E', text: ' beta'),
        ]);

        expect(result.map((s) => s.text).toList(), ['alpha', ' ', 'beta']);
        expect(result.map((s) => s.displayChord).toList(), [
          null,
          null,
          'E', // Chord on 'beta', not on ' '
        ]);
      },
    );

    test('does not repeat the segment chord on a later piece', () {
      // A chord is drawn once, at the position where it starts sounding. Every
      // piece after the first belongs to the same chord, so repeating the label
      // would claim a chord change that the source never wrote -- and next to
      // the following segment's own chord it renders as two labels running
      // together over one word.
      final result = splitSegmentsAtWordBoundaries(const [
        SongReaderSegmentProjection(
          displayChord: 'G#m',
          text: 'g, több, mint elé',
        ),
        SongReaderSegmentProjection(displayChord: 'C#m', text: 'g, Igé'),
      ]);

      expect(result.map((s) => s.text).toList(), [
        'g, ',
        'több, ',
        'mint ',
        'elé',
        'g, ',
        'Igé',
      ]);
      expect(result.map((s) => s.displayChord).toList(), [
        'G#m',
        null,
        null,
        null, // 'elé' continues G#m; the label already stands over 'g, '.
        'C#m',
        null,
      ]);
    });
  });

  group('groupSegmentsIntoWords after splitting', () {
    test('a word split by a chord change stays in one group', () {
      // The reproduction: ChordPro splits "Igédben" at the chord.
      final groups = groupSegmentsIntoWords(
        splitSegmentsAtWordBoundaries(const [
          SongReaderSegmentProjection(
            displayChord: 'E',
            text: 'alpha beta Igé',
          ),
          SongReaderSegmentProjection(displayChord: 'G#m', text: 'dben gamma'),
        ]),
      );

      expect(groups.map((g) => g.segments.map((s) => s.text).join()).toList(), [
        'alpha ',
        'beta ',
        'Igédben ',
        'gamma',
      ]);
      // Inside the group, only the half where a chord actually starts carries a
      // label: 'Igé' still sounds under the E already drawn over 'alpha'.
      final splitWord = groups[2].segments;
      expect(splitWord.map((s) => s.displayChord).toList(), [null, 'G#m']);
    });
  });

  group('readerBreakableWhitespace edge cases (PR review round)', () {
    test(
      'a zero-width space is a real split point, not silently re-merged',
      () {
        // U+200B is in readerBreakableWhitespace (Flutter's line breaker treats
        // it as a break opportunity), but String.trim* does not recognize it --
        // using trim* to decide group boundaries let the splitter cut a piece
        // at a ZWSP that the grouper then silently glued back together,
        // undoing the split.
        final pieces = splitSegmentsAtWordBoundaries(const [
          SongReaderSegmentProjection(displayChord: 'E', text: 'alpha​beta'),
        ]);
        expect(pieces.map((s) => s.text).toList(), ['alpha​', 'beta']);

        final groups = groupSegmentsIntoWords(pieces);
        expect(
          groups.map((g) => g.segments.map((s) => s.text).toList()).toList(),
          [
            ['alpha​'],
            ['beta'],
          ],
          reason:
              'a ZWSP-terminated piece must end a group like any other '
              'breakable-whitespace-terminated piece',
        );
      },
    );

    test('a lone leading-whitespace piece joins the previous group, not its '
        'own', () {
      // "word[C] next" -> segments ('word', null) and (' next', 'C').
      // Splitting cuts ' next''s leading space off as its own piece
      // ('word', ' ', 'next'); grouping must not let that lone ' ' piece
      // end 'word''s group AND start a fresh one -- that would be a stray
      // box free to open its own outer-Wrap row, which never existed
      // before this segment was split (the space was harmless leading
      // whitespace inside one Text). 'word' itself stays its own exact
      // piece (unglued -- other code, and other tests, key off a segment's
      // text unchanged), just sharing a group with the space that follows.
      final pieces = splitSegmentsAtWordBoundaries(const [
        SongReaderSegmentProjection(displayChord: null, text: 'word'),
        SongReaderSegmentProjection(displayChord: 'C', text: ' next'),
      ]);
      expect(pieces.map((s) => s.text).toList(), ['word', ' ', 'next']);
      expect(pieces.map((s) => s.displayChord).toList(), [null, null, 'C']);

      final groups = groupSegmentsIntoWords(pieces);
      expect(
        groups.map((g) => g.segments.map((s) => s.text).toList()).toList(),
        [
          ['word', ' '],
          ['next'],
        ],
      );
    });

    test(
      'a lone ZWSP leading-whitespace piece also joins the previous group',
      () {
        // Same shape as the plain-space case above, but the leading
        // whitespace piece is a single U+200B ZERO WIDTH SPACE instead of an
        // ASCII space. isEntirelyBreakableWhitespace must test per-character
        // against readerBreakableWhitespace, not `.trim().isEmpty`: trim*
        // does not recognize ZWSP, so a trim-based check would miss this
        // piece and let it start its own group -- the exact bug this
        // grouping rule exists to prevent, through a different separator.
        final pieces = splitSegmentsAtWordBoundaries(const [
          SongReaderSegmentProjection(displayChord: null, text: 'word'),
          SongReaderSegmentProjection(displayChord: 'C', text: '​next'),
        ]);
        expect(pieces.map((s) => s.text).toList(), ['word', '​', 'next']);

        final groups = groupSegmentsIntoWords(pieces);
        expect(
          groups.map((g) => g.segments.map((s) => s.text).toList()).toList(),
          [
            ['word', '​'],
            ['next'],
          ],
        );
      },
    );

    test('a chord-only slot may share a group with a following whitespace '
        'piece, but its own text stays untouched', () {
      // A chord-only segment's empty text is load-bearing: song_line_view
      // keys its rendering off text.isEmpty to keep the slot's own chord.
      // Grouping (unlike a discarded earlier version of this fix, which
      // glued at the splitting stage) never rewrites a piece's text, so the
      // slot's own piece stays exactly empty even when the grouper puts it
      // in the same group as the ' ' that follows.
      final pieces = splitSegmentsAtWordBoundaries(const [
        SongReaderSegmentProjection(displayChord: 'Am', text: ''),
        SongReaderSegmentProjection(displayChord: 'C', text: ' next'),
      ]);
      expect(pieces.map((s) => s.text).toList(), ['', ' ', 'next']);
      expect(pieces.first.text, isEmpty);

      final groups = groupSegmentsIntoWords(pieces);
      expect(groups.first.segments.first.text, isEmpty);
      expect(groups.first.segments.first.displayChord, 'Am');
    });
  });

  test('the estimator does not keep its own copy of the breakable-whitespace '
      'class', () {
    // A guard, not a behaviour test: song_reader_fit.dart must import
    // readerBreakableWhitespace rather than defining its own RegExp, or the
    // two layers can silently drift onto different character classes.
    final estimator = File(
      'lib/src/presentation/song_reader/song_reader_fit.dart',
    ).readAsStringSync();

    expect(
      estimator.contains('readerBreakableWhitespace'),
      isTrue,
      reason: 'must reference the shared constant',
    );
    expect(
      estimator.contains(RegExp(r'RegExp\S*\s*_breakableWhitespace\s*=')),
      isFalse,
      reason: 'must not keep its own private copy of the character class',
    );
  });

  test('the renderer and the estimator both split before grouping', () {
    // A guard, not a behaviour test: both call sites must apply the splitter,
    // or the estimate stops describing what is drawn. Checked by source
    // inspection because the two call sites are in different layers and
    // neither exposes its grouping.
    final renderer = File(
      'lib/src/presentation/song_reader/widgets/song_line_view.dart',
    ).readAsStringSync();
    final estimator = File(
      'lib/src/presentation/song_reader/song_reader_fit.dart',
    ).readAsStringSync();

    for (final source in [renderer, estimator]) {
      expect(source.contains('groupSegmentsIntoWords'), isTrue);
      expect(
        source.contains(
          RegExp(r'groupSegmentsIntoWords\(\s*splitSegmentsAtWordBoundaries\('),
        ),
        isTrue,
        reason:
            'groupSegmentsIntoWords must be called on split segments; '
            'grouping raw ChordPro segments reintroduces the mid-word break',
      );
    }
  });
}
