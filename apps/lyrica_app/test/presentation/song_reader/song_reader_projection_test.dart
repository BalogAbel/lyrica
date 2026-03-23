import 'package:flutter_test/flutter_test.dart';
import 'package:lyrica_app/src/domain/song/parsed_song.dart';
import 'package:lyrica_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyrica_app/src/presentation/song_reader/song_reader_state.dart';

ParsedSong _buildParsedSong({String leadingChord = 'A'}) {
  return ParsedSong(
    title: 'Reader test song',
    sections: [
      SongSection(
        kind: SongSectionKind.verse,
        label: 'Verse',
        lines: [
          SongLine(
            segments: [
              LyricSegment(leadingChord: leadingChord, text: 'Hello'),
              LyricSegment(text: ' world'),
            ],
          ),
        ],
      ),
    ],
    diagnostics: const [],
  );
}

void main() {
  test('keeps chords visible in chords plus lyrics mode', () {
    final projection = SongReaderProjection(
      song: _buildParsedSong(),
      state: SongReaderState(),
    );

    expect(projection.viewMode, SongReaderViewMode.chordsAndLyrics);
    expect(
      projection.sections.first.lines.first.segments.first.displayChord,
      'A',
    );
    expect(projection.sharedFontScale, 1.0);
  });

  test('hides chords in lyrics only mode', () {
    final projection = SongReaderProjection(
      song: _buildParsedSong(),
      state: SongReaderState(viewMode: SongReaderViewMode.lyricsOnly),
    );

    expect(projection.viewMode, SongReaderViewMode.lyricsOnly);
    expect(
      projection.sections.first.lines.first.segments.first.displayChord,
      isNull,
    );
  });

  test('transposes chords without mutating the canonical parsed song', () {
    final song = _buildParsedSong();

    final projection = SongReaderProjection(
      song: song,
      state: SongReaderState(transposeOffset: 2),
    );

    expect(
      projection.sections.first.lines.first.segments.first.displayChord,
      'B',
    );
    expect(
      () => projection.sections.add(
        SongReaderSectionProjection(
          kind: SongSectionKind.bridge,
          label: 'Bridge',
          number: null,
          lines: const [],
        ),
      ),
      throwsUnsupportedError,
    );
    expect(song.sections.first.lines.first.segments.first.leadingChord, 'A');
  });

  test('preserves unsupported chord text without crashing projection', () {
    final song = _buildParsedSong(leadingChord: 'not-a-real-chord');

    late SongReaderProjection projection;

    expect(() {
      projection = SongReaderProjection(
        song: song,
        state: SongReaderState(transposeOffset: 3),
      );
    }, returnsNormally);

    expect(
      projection.sections.first.lines.first.segments.first.displayChord,
      'not-a-real-chord',
    );
    expect(
      song.sections.first.lines.first.segments.first.leadingChord,
      'not-a-real-chord',
    );
  });
}
