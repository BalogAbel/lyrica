import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/domain/song/parsed_song.dart';
import 'package:lyron_app/src/domain/song/song_key_layers.dart';
import 'package:lyron_app/src/infrastructure/song_library/chordpro/chordpro_parser.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_key_layers.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';

ParsedSong _buildParsedSong({String leadingChord = 'A'}) {
  return ParsedSong(
    title: 'Reader test song',
    sourceKey: 'G',
    baseTranspose: 2,
    baseCapo: 2,
    sections: [
      SongSection(
        kind: SongSectionKind.verse,
        label: 'Verse',
        lines: [
          LyricLine(
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

ResolvedSongKey _key({
  required int transpose,
  required SongKeyLayerId transposeSource,
  required int capo,
  required SongKeyLayerId capoSource,
}) => ResolvedSongKey(
  transpose: ResolvedSongKeyField(value: transpose, source: transposeSource),
  capo: ResolvedSongKeyField(value: capo, source: capoSource),
);

void main() {
  test('keeps chords visible in chords plus lyrics mode', () {
    final projection = SongReaderProjection(
      song: _buildParsedSong(),
      state: SongReaderState(),
    );

    expect(projection.viewMode, SongReaderViewMode.chordsAndLyrics);
    expect(
      projection.instrumentDisplayMode,
      SongReaderInstrumentDisplayMode.guitar,
    );
    expect(projection.effectiveTranspose, 2);
    expect(projection.effectiveCapo, 2);
    expect(
      (projection.sections.first.lines.first as SongReaderLyricLineProjection)
          .segments
          .first
          .displayChord,
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
      (projection.sections.first.lines.first as SongReaderLyricLineProjection)
          .segments
          .first
          .displayChord,
      isNull,
    );
  });

  test('transposes chords without mutating the canonical parsed song', () {
    final song = _buildParsedSong();

    final projection = SongReaderProjection(
      song: song,
      state: SongReaderState(),
      key: _key(
        transpose: 4,
        transposeSource: SongKeyLayerId.temporary,
        capo: 2,
        capoSource: SongKeyLayerId.song,
      ),
    );

    expect(
      (projection.sections.first.lines.first as SongReaderLyricLineProjection)
          .segments
          .first
          .displayChord,
      'B',
    );
    expect(
      () => projection.sections.add(
        SongReaderSectionProjection(
          kind: SongSectionKind.bridge,
          label: 'Bridge',
          number: null,
          isUnknown: false,
          lines: const [],
        ),
      ),
      throwsUnsupportedError,
    );
    final firstLine = song.sections.first.lines.first as LyricLine;
    expect(firstLine.segments.first.leadingChord, 'A');
  });

  test('preserves unsupported chord text without crashing projection', () {
    final song = _buildParsedSong(leadingChord: 'not-a-real-chord');

    late SongReaderProjection projection;

    expect(() {
      projection = SongReaderProjection(
        song: song,
        state: SongReaderState(),
        key: _key(
          transpose: 5,
          transposeSource: SongKeyLayerId.temporary,
          capo: 2,
          capoSource: SongKeyLayerId.song,
        ),
      );
    }, returnsNormally);

    expect(
      (projection.sections.first.lines.first as SongReaderLyricLineProjection)
          .segments
          .first
          .displayChord,
      'not-a-real-chord',
    );
    final projFirstLine = song.sections.first.lines.first as LyricLine;
    expect(projFirstLine.segments.first.leadingChord, 'not-a-real-chord');
  });

  test('piano mode shows sounding chords without capo subtraction', () {
    final projection = SongReaderProjection(
      song: _buildParsedSong(),
      state: SongReaderState(
        instrumentDisplayMode: SongReaderInstrumentDisplayMode.piano,
      ),
    );

    expect(
      (projection.sections.first.lines.first as SongReaderLyricLineProjection)
          .segments
          .first
          .displayChord,
      'B',
    );
    expect(projection.isCapoDirectiveVisible, false);
  });

  test('guitar mode renders the resolved key, not the song base', () {
    final projection = SongReaderProjection(
      song: _buildParsedSong(),
      state: SongReaderState(),
      key: _key(
        transpose: 1,
        transposeSource: SongKeyLayerId.temporary,
        capo: 3,
        capoSource: SongKeyLayerId.temporary,
      ),
    );

    expect(projection.effectiveTranspose, 1);
    expect(projection.effectiveCapo, 3);
    expect(
      (projection.sections.first.lines.first as SongReaderLyricLineProjection)
          .segments
          .first
          .displayChord,
      'G',
    );
    expect(projection.isCapoDirectiveVisible, true);
    expect(projection.capoDirectiveText, 'Capo 3');
  });

  test('renders transpose and capo from different layers', () {
    final song = ParsedSong(
      title: 'Layered',
      sourceKey: 'G',
      baseTranspose: 1,
      sections: [
        SongSection(
          kind: SongSectionKind.verse,
          label: 'Verse',
          lines: [
            LyricLine(
              segments: [LyricSegment(leadingChord: 'C', text: 'Hello')],
            ),
          ],
        ),
      ],
      diagnostics: const [],
    );
    final key = _key(
      transpose: 3,
      transposeSource: SongKeyLayerId.temporary,
      capo: 2,
      capoSource: SongKeyLayerId.plan,
    );

    final guitar = SongReaderProjection(
      song: song,
      state: SongReaderState(),
      key: key,
    );
    final piano = SongReaderProjection(
      song: song,
      state: SongReaderState(
        instrumentDisplayMode: SongReaderInstrumentDisplayMode.piano,
      ),
      key: key,
    );

    String? chordOf(SongReaderProjection projection) =>
        (projection.sections.first.lines.first as SongReaderLyricLineProjection)
            .segments
            .first
            .displayChord;
    // C + 3 = D#; the guitar then subtracts the capo (2): C#.
    expect(chordOf(guitar), 'C#');
    expect(chordOf(piano), 'D#');
    expect(guitar.key, key);
    expect(guitar.effectiveTranspose, 3);
    expect(guitar.effectiveCapo, 2);
    expect(guitar.capoDirectiveText, 'Capo 2');
    // G + 3 = A#; the guitar subtracts the capo: G#.
    expect(guitar.effectiveKey, 'G#');
    expect(piano.effectiveKey, 'A#');
  });

  test('without a key the projection uses the base-only resolution', () {
    final song = _buildParsedSong();

    final projection = SongReaderProjection(
      song: song,
      state: SongReaderState(),
    );

    expect(projection.key, SongReaderKeyLayers.baseOnly.resolveFor(song));
    expect(
      projection.key,
      _key(
        transpose: 2,
        transposeSource: SongKeyLayerId.song,
        capo: 2,
        capoSource: SongKeyLayerId.song,
      ),
    );
  });

  test('guitar mode floors a negative song capo at open capo', () {
    final projection = SongReaderProjection(
      song: ParsedSong(
        title: 'Negative capo',
        baseTranspose: 2,
        baseCapo: -3,
        sections: [
          SongSection(
            kind: SongSectionKind.verse,
            label: 'Verse',
            lines: [
              LyricLine(
                segments: [LyricSegment(leadingChord: 'A', text: 'Hello')],
              ),
            ],
          ),
        ],
        diagnostics: const [],
      ),
      state: SongReaderState(),
    );

    expect(projection.effectiveCapo, 0);
    expect(projection.capoDirectiveText, isNull);
    expect(
      (projection.sections.first.lines.first as SongReaderLyricLineProjection)
          .segments
          .first
          .displayChord,
      'B',
    );
  });

  test('effective key follows the displayed-chord path in guitar mode', () {
    // sourceKey G, baseTranspose 2, baseCapo 2, guitar:
    // sounding = G + 2 = A, then - capo(2) = G.
    final projection = SongReaderProjection(
      song: _buildParsedSong(),
      state: SongReaderState(),
    );

    expect(projection.effectiveKey, 'G');
  });

  test('effective key omits the capo in piano mode', () {
    // sounding = G + 2 = A; piano keeps the sounding key.
    final projection = SongReaderProjection(
      song: _buildParsedSong(),
      state: SongReaderState(
        instrumentDisplayMode: SongReaderInstrumentDisplayMode.piano,
      ),
    );

    expect(projection.effectiveKey, 'A');
  });

  test('effective key tracks the resolved transpose', () {
    final projection = SongReaderProjection(
      song: _buildParsedSong(),
      state: SongReaderState(),
      key: _key(
        transpose: 3,
        transposeSource: SongKeyLayerId.temporary,
        capo: 2,
        capoSource: SongKeyLayerId.song,
      ),
    );

    expect(projection.effectiveKey, 'G#');
  });

  test('effective key is null when the song has no source key', () {
    final projection = SongReaderProjection(
      song: ParsedSong(
        title: 'No key',
        sections: const [],
        diagnostics: const [],
      ),
      state: SongReaderState(),
    );

    expect(projection.effectiveKey, isNull);
  });

  test('applies base transpose set after a section comment (R1)', () {
    final song = ChordproParser().parse(
      '{title:T}\n{comment:<Intro>}\n{transpose: 2}\n[C]Hello\n',
    );

    final projection = SongReaderProjection(
      song: song,
      state: SongReaderState(),
    );

    expect(
      (projection.sections.first.lines.first as SongReaderLyricLineProjection)
          .segments
          .first
          .displayChord,
      'D',
    );
  });
}
