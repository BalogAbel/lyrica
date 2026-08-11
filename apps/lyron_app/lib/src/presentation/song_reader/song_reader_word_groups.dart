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
List<SongReaderWordGroup> groupSegmentsIntoWords(
  List<SongReaderSegmentProjection> segments,
) {
  final groups = <SongReaderWordGroup>[];
  var current = <SongReaderSegmentProjection>[];

  for (final segment in segments) {
    final startsNewGroup =
        current.isNotEmpty &&
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
    value.isNotEmpty && value.trimRight().length != value.length;

bool _startsWithWhitespace(String value) =>
    value.isNotEmpty && value.trimLeft().length != value.length;

/// Whitespace that Flutter's line breaker treats as a break opportunity.
///
/// Deliberately the same character class `song_reader_fit.dart`'s
/// `_breakableWhitespace` uses, and for the same reason: the estimator and the
/// renderer must agree on where a break may happen. See
/// docs/deferred/2026-07-28-reader-fit-conservatism-margin.md for the
/// `TextPainter` measurements behind this set.
final _breakableWhitespace = RegExp('[ 	   -​  　]');

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
      final shouldKeepChord =
          !foundFirstContentPiece && piece.trim().isNotEmpty;
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
    if (!_breakableWhitespace.hasMatch(text[index])) {
      index++;
      continue;
    }

    // Consume the whole whitespace run so "alpha   beta" yields "alpha   ".
    var end = index;
    while (end < text.length && _breakableWhitespace.hasMatch(text[end])) {
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
