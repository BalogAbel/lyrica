import 'package:flutter_test/flutter_test.dart';
import 'package:lyrica_app/src/domain/song/parsed_song.dart';
import 'package:lyrica_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyrica_app/src/presentation/song_reader/song_reader_state.dart';

ParsedSong _buildParsedSong() {
  return ParsedSong(
    title: 'Reader test song',
    sections: [
      SongSection(
        kind: SongSectionKind.verse,
        label: 'Verse',
        lines: [
          SongLine(
            segments: [
              LyricSegment(leadingChord: 'A', text: 'Hello'),
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
      state: const SongReaderState(),
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
      state: const SongReaderState(viewMode: SongReaderViewMode.lyricsOnly),
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
      state: const SongReaderState(transposeOffset: 2),
    );

    expect(
      projection.sections.first.lines.first.segments.first.displayChord,
      'B',
    );
    expect(song.sections.first.lines.first.segments.first.leadingChord, 'A');
  });
}
