import 'package:lyron_app/src/domain/song/parsed_song.dart';
import 'package:lyron_app/src/infrastructure/song_library/chordpro/chordpro_normalizer.dart';
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
    required this.subtitle,
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
  final String? subtitle;
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
      subtitle: subtitle,
      artist: artist,
      sourceKey: sourceKey,
      tempoBpm: tempoBpm,
      tags: tags,
      baseTranspose: baseTranspose,
      baseCapo: baseCapo,
      sections: sections,
      diagnostics: diagnostics,
    );
  }
}

/// Parses the normalized source: the string the save path stores and the
/// reader parses, so editor and reader read the same base values (BD5).
SongEditorParsedSong _parseSongEditorSource(String source) {
  final parser = ChordproParser();
  final parsedSong = parser.parse(ChordproNormalizer().normalize(source));

  return SongEditorParsedSong(
    title: parsedSong.title,
    subtitle: parsedSong.subtitle,
    artist: parsedSong.artist ?? '',
    sourceKey: parsedSong.sourceKey,
    tempoBpm: parsedSong.tempoBpm,
    tags: parsedSong.tags,
    baseTranspose: parsedSong.baseTranspose,
    baseCapo: parsedSong.baseCapo,
    sections: parsedSong.sections,
    diagnostics: parsedSong.diagnostics,
  );
}
