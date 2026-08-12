import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';

/// A run of adjacent segments that belong to the same word.
///
/// ChordPro splits a lyric line at chord positions, so a chord placed inside a
/// word produces two adjacent segments with no whitespace between them.
/// Grouping them keeps the line's `Wrap` from breaking inside the word and
/// carrying the second segment's chord onto the wrong syllable.
class SongReaderWordGroup {
  const SongReaderWordGroup(this.segments);

  final List<SongReaderSegmentProjection> segments;
}

/// Groups [segments] so a break is only possible where the source text had
/// whitespace.
///
/// A piece that is ENTIRELY [readerBreakableWhitespace] (non-empty, every
/// character breakable) never starts a group on its own, regardless of its
/// own leading/trailing whitespace: [splitSegmentsAtWordBoundaries] can produce
/// one as the very first piece of a segment whose text begins with
/// whitespace (e.g. a chord landing right after the previous word --
/// "word[C] next" splits into "word" and " next", and " next" itself splits
/// into " " and "next"). Applying the ordinary rule to that lone " " piece
/// would let it end the previous group AND start a new one -- a stray box
/// free to open its own outer-`Wrap` row, indistinguishable from a real
/// blank leading indent, that never existed before this segment was split
/// (pre-split, the space was harmless leading whitespace inside one `Text`).
/// It stays glued to whatever group is already open instead; a real word
/// immediately after it still starts a fresh group normally, since the
/// whitespace piece itself ends with whitespace.
///
/// This does not apply to an EMPTY piece (a chord-only slot): that case is
/// already handled below it, since `_startsWithWhitespace('')` is false --
/// an empty piece never forces a break on its own either, for the same
/// "nothing to break at" reason, and this comment does not change that.
List<SongReaderWordGroup> groupSegmentsIntoWords(
  List<SongReaderSegmentProjection> segments,
) {
  final groups = <SongReaderWordGroup>[];
  var current = <SongReaderSegmentProjection>[];

  for (final segment in segments) {
    final isWhitespaceOnlyPiece = _isEntirelyBreakableWhitespace(segment.text);
    final startsNewGroup =
        current.isNotEmpty &&
        !isWhitespaceOnlyPiece &&
        (_endsWithWhitespace(current.last.text) ||
            _startsWithWhitespace(segment.text));
    if (startsNewGroup) {
      groups.add(SongReaderWordGroup(current));
      current = <SongReaderSegmentProjection>[];
    }
    current.add(segment);
  }

  if (current.isNotEmpty) {
    groups.add(SongReaderWordGroup(current));
  }
  return groups;
}

bool _endsWithWhitespace(String value) =>
    value.isNotEmpty &&
    readerBreakableWhitespace.hasMatch(value[value.length - 1]);

bool _startsWithWhitespace(String value) =>
    value.isNotEmpty && readerBreakableWhitespace.hasMatch(value[0]);

/// True when [value] is non-empty and every character is
/// [readerBreakableWhitespace] -- e.g. a single space, a run of tabs, or a
/// lone ZWSP. Deliberately per-character against the shared class rather
/// than `value.trim().isEmpty`: `String.trim*` does not recognize U+200B
/// ZERO WIDTH SPACE (see [readerBreakableWhitespace]'s doc), so a
/// trim-based check would miss a whitespace-only piece made of nothing but
/// ZWSP and let it start a group on its own -- the exact bug this class of
/// check exists to prevent, through a different separator.
bool _isEntirelyBreakableWhitespace(String value) {
  if (value.isEmpty) return false;
  for (var i = 0; i < value.length; i++) {
    if (!readerBreakableWhitespace.hasMatch(value[i])) return false;
  }
  return true;
}

/// Breakable whitespace: characters Flutter's line breaker treats as an
/// ordinary word-boundary break OPPORTUNITY (not a forced line end), verified
/// with a real `TextPainter` rather than assumed from the Unicode category
/// name (`song_line_view_estimate_consistency_test.dart`'s empirical probe):
/// ASCII space and TAB, plus the Unicode Zs "space separator" characters
/// (U+00A0, U+1680, U+2000-U+200A, U+202F, U+205F, U+3000) and U+200B ZERO
/// WIDTH SPACE. Every one of these was confirmed via
/// `TextPainter.getLineBoundary` to place the same trailing-whitespace line
/// boundary a plain ASCII space does. Full measurements in
/// docs/deferred/2026-07-28-reader-fit-conservatism-margin.md.
///
/// This deliberately includes U+00A0 NO-BREAK SPACE and U+202F NARROW
/// NO-BREAK SPACE: despite the names, Flutter's line breaker does NOT
/// special-case either as non-breaking -- both break exactly like a plain
/// space.
///
/// The single shared definition: `song_reader_fit.dart` imports this rather
/// than keeping its own copy, so the estimator and the renderer can never
/// silently drift onto two different character classes.
///
/// [_endsWithWhitespace] and [_startsWithWhitespace] test against this class
/// directly rather than `String.trim*`, which recognizes a different,
/// Dart-defined whitespace set that does NOT include U+200B ZERO WIDTH
/// SPACE — even though it's a real break opportunity in this class and in
/// Flutter's own line breaker. Testing against `trim*` let
/// [splitSegmentsAtWordBoundaries] cut a piece at a ZWSP that
/// [groupSegmentsIntoWords] then silently re-merged, undoing the split.
final readerBreakableWhitespace = RegExp('[ 	   -​  　]');

/// Splits each segment's text at internal whitespace so that every piece holds
/// at most one word.
///
/// ChordPro splits a lyric line at chord positions, which has nothing to do
/// with where words begin and end: one segment can hold a whole clause, and a
/// single word can span two segments. [groupSegmentsIntoWords] can only start a
/// group at a segment boundary, so without this pre-pass a multi-word segment
/// and its chord-split neighbour collapse into one indivisible group covering
/// most of a line — and when that group does not fit, the only break available
/// is the segment boundary, in the middle of a word.
///
/// The trailing whitespace stays on the LEFT piece: the concatenated text must
/// be byte-identical to the original (the rendered line's spacing comes from
/// the text itself, since the `Wrap` uses `spacing: 0`), and
/// [groupSegmentsIntoWords] reads exactly that trailing whitespace to decide
/// where a group ends.
///
/// [SongReaderSegmentProjection.displayChord] rides on the first piece that has
/// content: a chord is drawn once, where it starts sounding, and leading
/// whitespace is not that place. Every later piece of the same segment is still
/// under that chord, so it carries no label -- a repeated label would claim a
/// chord change the source never wrote, and next to the following segment's own
/// chord it renders as two labels running together over a single word.
List<SongReaderSegmentProjection> splitSegmentsAtWordBoundaries(
  List<SongReaderSegmentProjection> segments,
) {
  final result = <SongReaderSegmentProjection>[];

  for (final segment in segments) {
    // A chord-only segment (an instrumental bar's slot) has no words to split
    // and must stay one box, or it loses its own chord slot.
    if (segment.text.isEmpty) {
      result.add(segment);
      continue;
    }

    final pieces = _splitKeepingTrailingWhitespace(segment.text);
    if (pieces.length == 1) {
      result.add(segment);
      continue;
    }

    bool foundFirstContentPiece = false;

    for (final piece in pieces) {
      final hasContent = piece.trim().isNotEmpty;
      final shouldKeepChord = !foundFirstContentPiece && hasContent;
      if (shouldKeepChord) {
        foundFirstContentPiece = true;
      }

      result.add(
        SongReaderSegmentProjection(
          displayChord: shouldKeepChord ? segment.displayChord : null,
          text: piece,
        ),
      );
    }
  }

  return List.unmodifiable(result);
}

/// Cuts [text] after each run of breakable whitespace, so every piece except
/// the last ends with the whitespace that terminated it and the pieces
/// concatenate back to [text].
List<String> _splitKeepingTrailingWhitespace(String text) {
  final pieces = <String>[];
  var start = 0;
  var index = 0;

  while (index < text.length) {
    if (!readerBreakableWhitespace.hasMatch(text[index])) {
      index++;
      continue;
    }

    // Consume the whole whitespace run so "alpha   beta" yields "alpha   ".
    var end = index;
    while (end < text.length && readerBreakableWhitespace.hasMatch(text[end])) {
      end++;
    }
    pieces.add(text.substring(start, end));
    start = end;
    index = end;
  }

  if (start < text.length) {
    pieces.add(text.substring(start));
  }

  return pieces;
}
