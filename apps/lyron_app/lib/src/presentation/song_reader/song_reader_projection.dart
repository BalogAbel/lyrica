import 'package:lyron_app/src/domain/song/chord_symbol.dart';
import 'package:lyron_app/src/domain/song/parsed_song.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';

typedef SongChordTransposer = String Function(String chord, int semitoneOffset);

class SongReaderProjection {
  SongReaderProjection({
    required ParsedSong song,
    required SongReaderState state,
    SongChordTransposer transposeChord = _transposeChord,
  }) : title = song.title,
       subtitle = song.subtitle,
       sourceKey = song.sourceKey,
       instrumentDisplayMode = state.instrumentDisplayMode,
       diagnostics = List.unmodifiable(song.diagnostics),
       viewMode = state.viewMode,
       transposeOffset = state.transposeOffset,
       capoOffset = state.capoOffset,
       effectiveTranspose = song.baseTranspose + state.transposeOffset,
       effectiveCapo = SongReaderProjection.effectiveCapoValue(song, state),
       isCapoDirectiveVisible =
           state.instrumentDisplayMode ==
           SongReaderInstrumentDisplayMode.guitar,
       capoDirectiveText =
           state.instrumentDisplayMode ==
                   SongReaderInstrumentDisplayMode.guitar &&
               SongReaderProjection.effectiveCapoValue(song, state) > 0
           ? 'Capo ${SongReaderProjection.effectiveCapoValue(song, state)}'
           : null,
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
                                       song,
                                       transposeChord,
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
  final SongReaderInstrumentDisplayMode instrumentDisplayMode;
  final List<ParseDiagnostic> diagnostics;
  final SongReaderViewMode viewMode;
  final int transposeOffset;
  final int capoOffset;
  final int effectiveTranspose;
  final int effectiveCapo;
  final bool isCapoDirectiveVisible;
  final String? capoDirectiveText;
  final double sharedFontScale;
  final List<SongReaderSectionProjection> sections;

  static String? _displayChord(
    String? leadingChord,
    SongReaderState state,
    ParsedSong song,
    SongChordTransposer transposeChord,
  ) {
    if (state.viewMode == SongReaderViewMode.lyricsOnly ||
        leadingChord == null) {
      return null;
    }

    try {
      final soundingChord = transposeChord(
        leadingChord,
        song.baseTranspose + state.transposeOffset,
      );
      if (state.instrumentDisplayMode ==
          SongReaderInstrumentDisplayMode.piano) {
        return soundingChord;
      }
      return transposeChord(soundingChord, -effectiveCapoValue(song, state));
    } on FormatException {
      return leadingChord;
    }
  }

  static int effectiveCapoValue(ParsedSong song, SongReaderState state) {
    final capo = song.baseCapo + state.capoOffset;
    return capo < 0 ? 0 : capo;
  }
}

String _transposeChord(String chord, int semitoneOffset) {
  return ChordSymbol.parse(chord).transpose(semitoneOffset).displayName;
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
