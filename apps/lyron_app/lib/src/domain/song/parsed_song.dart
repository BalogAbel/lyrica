import 'package:lyron_app/src/domain/song/parse_diagnostic.dart';
import 'package:lyron_app/src/domain/song/song_section.dart';

export 'lyric_segment.dart';
export 'parse_diagnostic.dart';
export 'song_line.dart';
export 'song_section.dart';

class ParsedSong {
  ParsedSong({
    required this.title,
    this.subtitle,
    this.sourceKey,
    this.baseTranspose = 0,
    this.baseCapo = 0,
    required List<SongSection> sections,
    required List<ParseDiagnostic> diagnostics,
  }) : sections = List.unmodifiable(sections),
       diagnostics = List.unmodifiable(diagnostics);

  final String title;
  final String? subtitle;
  final String? sourceKey;
  final int baseTranspose;
  final int baseCapo;
  final List<SongSection> sections;
  final List<ParseDiagnostic> diagnostics;

  @override
  bool operator ==(Object other) {
    return other is ParsedSong &&
        other.title == title &&
        other.subtitle == subtitle &&
        other.sourceKey == sourceKey &&
        other.baseTranspose == baseTranspose &&
        other.baseCapo == baseCapo &&
        _listEquals(other.sections, sections) &&
        _listEquals(other.diagnostics, diagnostics);
  }

  @override
  int get hashCode => Object.hash(
    title,
    subtitle,
    sourceKey,
    baseTranspose,
    baseCapo,
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
