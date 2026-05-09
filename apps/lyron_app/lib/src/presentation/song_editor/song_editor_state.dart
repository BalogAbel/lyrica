import 'package:lyron_app/src/domain/song/parse_diagnostic.dart';
import 'package:lyron_app/src/domain/song/parsed_song.dart';
import 'package:lyron_app/src/domain/song/song_section.dart';
import 'package:lyron_app/src/infrastructure/song_library/chordpro/chordpro_line_scanner.dart';
import 'package:lyron_app/src/infrastructure/song_library/chordpro/chordpro_parser.dart';

enum SongEditorCanonicalViewMode { source, preview }

class SongEditorState {
  SongEditorState({
    required this.source,
    this.canonicalViewMode = SongEditorCanonicalViewMode.source,
  }) : parsedSong = _parseSongEditorSource(source);

  final String source;
  final SongEditorCanonicalViewMode canonicalViewMode;
  final SongEditorParsedSong parsedSong;

  SongEditorState copyWith({
    String? source,
    SongEditorCanonicalViewMode? canonicalViewMode,
  }) {
    return SongEditorState(
      source: source ?? this.source,
      canonicalViewMode: canonicalViewMode ?? this.canonicalViewMode,
    );
  }
}

class SongEditorParsedSong {
  SongEditorParsedSong({
    required this.title,
    required this.artist,
    required this.sourceKey,
    required this.tempoBpm,
    List<String> tags = const [],
    required this.baseTranspose,
    required this.baseCapo,
    required List<SongSection> sections,
    required List<ParseDiagnostic> diagnostics,
  }) : tags = List.unmodifiable(tags),
       sections = List.unmodifiable(sections),
       diagnostics = List.unmodifiable(diagnostics);

  final String title;
  final String artist;
  final String? sourceKey;
  final int? tempoBpm;
  final List<String> tags;
  final int baseTranspose;
  final int baseCapo;
  final List<SongSection> sections;
  final List<ParseDiagnostic> diagnostics;

  ParsedSong toReaderSong() {
    return ParsedSong(
      title: title,
      sourceKey: sourceKey,
      baseTranspose: baseTranspose,
      baseCapo: baseCapo,
      sections: sections,
      diagnostics: diagnostics,
    );
  }
}

SongEditorParsedSong _parseSongEditorSource(String source) {
  final parser = ChordproParser();
  final parsedSong = parser.parse(source);
  final transpose = _currentDirectiveInt(source, 'transpose');
  final capo = _currentDirectiveInt(source, 'capo');

  return SongEditorParsedSong(
    title: parsedSong.title,
    artist: parsedSong.artist ?? '',
    sourceKey: parsedSong.sourceKey,
    tempoBpm: parsedSong.tempoBpm,
    tags: parsedSong.tags,
    baseTranspose: transpose,
    baseCapo: capo,
    sections: parsedSong.sections,
    diagnostics: parsedSong.diagnostics,
  );
}

int _currentDirectiveInt(String source, String directiveName) {
  for (final line in ChordproLineScanner().scan(source)) {
    if (line.kind == ChordproLineKind.lyric) {
      break;
    }

    if (line.kind == ChordproLineKind.directive &&
        line.directiveName == directiveName) {
      return int.tryParse(line.directiveValue?.trim() ?? '') ?? 0;
    }
  }

  return 0;
}
