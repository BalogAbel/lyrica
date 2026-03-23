import 'package:lyrica_app/src/domain/song/parsed_song.dart';
import 'package:lyrica_app/src/infrastructure/song_library/chord_transposer.dart';
import 'package:lyrica_app/src/presentation/song_reader/song_reader_state.dart';

class SongReaderProjection {
  SongReaderProjection({
    required ParsedSong song,
    required SongReaderState state,
    ChordTransposer transposer = const ChordTransposer(),
  }) : title = song.title,
       subtitle = song.subtitle,
       sourceKey = song.sourceKey,
       diagnostics = List.unmodifiable(song.diagnostics),
       viewMode = state.viewMode,
       transposeOffset = state.transposeOffset,
       sharedFontScale = state.sharedFontScale,
       sections = List.unmodifiable(
         song.sections
             .map(
               (section) => SongReaderSectionProjection(
                 kind: section.kind,
                 label: section.label,
                 number: section.number,
                 lines: List.unmodifiable(
                   section.lines
                       .map(
                         (line) => SongReaderLineProjection(
                           segments: List.unmodifiable(
                             line.segments
                                 .map(
                                   (segment) => SongReaderSegmentProjection(
                                     displayChord: _displayChord(
                                       segment.leadingChord,
                                       state,
                                       transposer,
                                     ),
                                     text: segment.text,
                                   ),
                                 )
                                 .toList(growable: false),
                           ),
                         ),
                       )
                       .toList(growable: false),
                 ),
               ),
             )
             .toList(growable: false),
       );

  final String title;
  final String? subtitle;
  final String? sourceKey;
  final List<ParseDiagnostic> diagnostics;
  final SongReaderViewMode viewMode;
  final int transposeOffset;
  final double sharedFontScale;
  final List<SongReaderSectionProjection> sections;

  static String? _displayChord(
    String? leadingChord,
    SongReaderState state,
    ChordTransposer transposer,
  ) {
    if (state.viewMode == SongReaderViewMode.lyricsOnly ||
        leadingChord == null) {
      return null;
    }

    return transposer.transpose(leadingChord, state.transposeOffset);
  }
}

class SongReaderSectionProjection {
  SongReaderSectionProjection({
    required this.kind,
    required this.label,
    required this.number,
    required List<SongReaderLineProjection> lines,
  }) : lines = List.unmodifiable(lines);

  final SongSectionKind kind;
  final String label;
  final int? number;
  final List<SongReaderLineProjection> lines;
}

class SongReaderLineProjection {
  SongReaderLineProjection({
    required List<SongReaderSegmentProjection> segments,
  }) : segments = List.unmodifiable(segments);

  final List<SongReaderSegmentProjection> segments;
}

class SongReaderSegmentProjection {
  const SongReaderSegmentProjection({
    required this.displayChord,
    required this.text,
  });

  final String? displayChord;
  final String text;
}
