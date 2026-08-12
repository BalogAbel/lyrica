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
    value.isNotEmpty && _isGroupBreakChar(value[value.length - 1]);

bool _startsWithWhitespace(String value) =>
    value.isNotEmpty && _isGroupBreakChar(value[0]);

bool _isGroupBreakChar(String char) =>
    readerBreakableWhitespace.hasMatch(char) ||
    _mandatoryBreakChar.hasMatch(char);

/// The seven characters Flutter's line breaker honors as a FORCED line
/// break wherever they occur, regardless of available width: LINE FEED,
/// CARRIAGE RETURN, LINE SEPARATOR, PARAGRAPH SEPARATOR, NEXT LINE,
/// VERTICAL TAB and FORM FEED. Written as `\u` escapes rather than raw
/// bytes so the set stays legible (and diffable) in review, an editor, or
/// after a copy-paste, unlike an invisible literal control character.
///
/// The canonical definition: `song_reader_fit.dart`'s `_mandatoryLineBreak`
/// builds its own pattern from this rather than keeping a hand-copied
/// second list, for the same reason `readerBreakableWhitespace` above is
/// canonical here rather than duplicated in that file -- a hand-kept second
/// copy is exactly the kind of drift this file's whitespace handling has
/// already been bitten by twice. See that pattern's own doc comment (in
/// `song_reader_fit.dart`) for the `TextPainter` measurements this set is
/// pinned by.
///
/// U+FEFF ZERO WIDTH NO-BREAK SPACE is ALSO whitespace-adjacent (stripped
/// by `String.trim*`, the same family of gap that motivated
/// [readerBreakableWhitespace] moving off `trim*` in the first place), but
/// is deliberately NOT included here or in [readerBreakableWhitespace]: it
/// isn't pinned by a `TextPainter` measurement the way every character in
/// both of those sets is, and this file's whitespace decisions are made by
/// measuring, not by inference from a Unicode category name -- adding it
/// without that verification would be exactly the kind of unverified
/// assumption this codebase's review history keeps finding gaps in one
/// round later. A pre-existing, separate gap either way: it was never part
/// of the estimator's numeric model, so this is not a regression this
/// round introduces.
const readerMandatoryBreakChars = '\r\n\u2028\u2029\u0085\u000B\u000C';

/// A character that forces a line break wherever it occurs -- a SUPERSET
/// case for grouping: if the render is forced to break here no matter
/// what, the piece boundary is always a safe place for the outer `Wrap` to
/// break too, in addition to every ordinary [readerBreakableWhitespace]
/// opportunity. Individual characters, not `song_reader_fit.dart`'s `\r\n`
/// pairing -- that pairing only matters there to avoid double-counting a
/// CRLF as two lines when measuring height; grouping only asks "can a
/// break happen at this boundary", so treating `\r` and `\n` independently
/// is correct here.
///
/// Not extended to [_isEntirelyBreakableWhitespace]: none of these
/// characters can become a lone piece via [_splitKeepingTrailingWhitespace]
/// (which only cuts at [readerBreakableWhitespace]), so a piece "entirely"
/// one of these never arises from splitting.
final _mandatoryBreakChar = RegExp('[$readerMandatoryBreakChars]');

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
