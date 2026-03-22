import 'package:lyrica_app/src/domain/song/song_line.dart';

enum SongSectionKind { verse, chorus, bridge, other }

class SongSection {
  const SongSection({
    required this.kind,
    required this.label,
    this.number,
    this.lines = const [],
  });

  final SongSectionKind kind;
  final String label;
  final int? number;
  final List<SongLine> lines;

  @override
  bool operator ==(Object other) {
    return other is SongSection &&
        other.kind == kind &&
        other.label == label &&
        other.number == number &&
        _listEquals(other.lines, lines);
  }

  @override
  int get hashCode => Object.hash(kind, label, number, Object.hashAll(lines));
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
