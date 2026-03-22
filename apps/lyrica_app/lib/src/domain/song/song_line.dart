import 'package:lyrica_app/src/domain/song/lyric_segment.dart';

class SongLine {
  SongLine({required List<LyricSegment> segments})
    : segments = List.unmodifiable(segments);

  final List<LyricSegment> segments;

  @override
  bool operator ==(Object other) {
    return other is SongLine && _listEquals(other.segments, segments);
  }

  @override
  int get hashCode => Object.hashAll(segments);
}

bool _listEquals<T>(List<T> left, List<T> right) {
  if (identical(left, right)) {
    return true;
  }

  if (left.length != right.length) {
    return false;
  }

  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }

  return true;
}
