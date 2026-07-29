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
