import 'package:lyron_app/src/domain/song/lyric_segment.dart';

sealed class SongLine {
  const SongLine();
}

class LyricLine extends SongLine {
  LyricLine({required List<LyricSegment> segments})
    : segments = List.unmodifiable(segments);

  final List<LyricSegment> segments;

  @override
  bool operator ==(Object other) =>
      other is LyricLine && _listEquals(other.segments, segments);

  @override
  int get hashCode => Object.hashAll(segments);
}

class CommentLine extends SongLine {
  const CommentLine({required this.text}) : super();
  final String text;

  @override
  bool operator ==(Object other) => other is CommentLine && other.text == text;

  @override
  int get hashCode => text.hashCode;
}

class TabBlock extends SongLine {
  TabBlock({required List<String> rawLines})
    : rawLines = List.unmodifiable(rawLines);
  final List<String> rawLines;

  @override
  bool operator ==(Object other) =>
      other is TabBlock && _listEquals(other.rawLines, rawLines);

  @override
  int get hashCode => Object.hashAll(rawLines);
}

class DirectiveLine extends SongLine {
  const DirectiveLine({required this.name, this.value}) : super();
  final String name;
  final String? value;

  @override
  bool operator ==(Object other) =>
      other is DirectiveLine && other.name == name && other.value == value;

  @override
  int get hashCode => Object.hash(name, value);
}

bool _listEquals<T>(List<T> left, List<T> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}
