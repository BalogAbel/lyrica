import 'package:lyrica_app/src/domain/song/parse_diagnostic.dart';
import 'package:lyrica_app/src/domain/song/song_section.dart';

export 'lyric_segment.dart';
export 'parse_diagnostic.dart';
export 'song_line.dart';
export 'song_section.dart';

class ParsedSong {
  const ParsedSong({
    required this.title,
    this.subtitle,
    this.sourceKey,
    required this.sections,
    required this.diagnostics,
  });

  final String title;
  final String? subtitle;
  final String? sourceKey;
  final List<SongSection> sections;
  final List<ParseDiagnostic> diagnostics;

  @override
  bool operator ==(Object other) {
    return other is ParsedSong &&
        other.title == title &&
        other.subtitle == subtitle &&
        other.sourceKey == sourceKey &&
        _listEquals(other.sections, sections) &&
        _listEquals(other.diagnostics, diagnostics);
  }

  @override
  int get hashCode => Object.hash(
    title,
    subtitle,
    sourceKey,
    Object.hashAll(sections),
    Object.hashAll(diagnostics),
  );
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
