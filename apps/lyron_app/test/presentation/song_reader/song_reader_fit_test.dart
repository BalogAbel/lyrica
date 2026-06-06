import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/domain/song/parsed_song.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_fit.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';

SongReaderSectionProjection _lyricSection({
  int lineCount = 1,
  String label = 'Verse',
  int? number = 1,
}) {
  return SongReaderSectionProjection(
    kind: SongSectionKind.verse,
    label: label,
    number: number,
    isUnknown: false,
    lines: List.generate(
      lineCount,
      (_) => SongReaderLyricLineProjection(
        segments: [
          const SongReaderSegmentProjection(
            displayChord: 'C',
            text: 'Hello world',
          ),
        ],
      ),
    ),
  );
}

void main() {
  const viewMode = SongReaderViewMode.chordsAndLyrics;
  const availableWidth = 400.0;
  const fontScale = 1.0;

  group('estimateSongContentHeight', () {
    test('grows with more content (more sections)', () {
      final oneSection = [_lyricSection(lineCount: 3)];
      final twoSections = [
        _lyricSection(lineCount: 3),
        _lyricSection(lineCount: 3, label: 'Chorus', number: 1),
      ];

      final h1 = estimateSongContentHeight(
        sections: oneSection,
        viewMode: viewMode,
        availableWidth: availableWidth,
        fontScale: fontScale,
      );
      final h2 = estimateSongContentHeight(
        sections: twoSections,
        viewMode: viewMode,
        availableWidth: availableWidth,
        fontScale: fontScale,
      );

      expect(h2, greaterThan(h1));
    });

    test('grows with more lines per section', () {
      final fewLines = [_lyricSection(lineCount: 2)];
      final manyLines = [_lyricSection(lineCount: 10)];

      final hFew = estimateSongContentHeight(
        sections: fewLines,
        viewMode: viewMode,
        availableWidth: availableWidth,
        fontScale: fontScale,
      );
      final hMany = estimateSongContentHeight(
        sections: manyLines,
        viewMode: viewMode,
        availableWidth: availableWidth,
        fontScale: fontScale,
      );

      expect(hMany, greaterThan(hFew));
    });

    test('grows with fontScale', () {
      final sections = [_lyricSection(lineCount: 3)];

      final hSmall = estimateSongContentHeight(
        sections: sections,
        viewMode: viewMode,
        availableWidth: availableWidth,
        fontScale: 0.5,
      );
      final hLarge = estimateSongContentHeight(
        sections: sections,
        viewMode: viewMode,
        availableWidth: availableWidth,
        fontScale: 2.0,
      );

      expect(hLarge, greaterThan(hSmall));
    });

    test('returns 0 for empty sections list', () {
      final h = estimateSongContentHeight(
        sections: const [],
        viewMode: viewMode,
        availableWidth: availableWidth,
        fontScale: fontScale,
      );
      expect(h, equals(0.0));
    });
  });

  group('resolveFitFontScale', () {
    const min = SongReaderState.minSharedFontScale;
    const max = SongReaderState.maxSharedFontScale;

    test('returned scale fits content within availableHeight (+0.5 tolerance)',
        () {
      final sections = [
        _lyricSection(lineCount: 5),
        _lyricSection(lineCount: 5, label: 'Chorus', number: 1),
      ];
      const availableHeight = 600.0;

      final scale = resolveFitFontScale(
        sections: sections,
        viewMode: viewMode,
        availableWidth: availableWidth,
        availableHeight: availableHeight,
        minScale: min,
        maxScale: max,
      );

      expect(scale, greaterThanOrEqualTo(min));
      expect(scale, lessThanOrEqualTo(max));

      final h = estimateSongContentHeight(
        sections: sections,
        viewMode: viewMode,
        availableWidth: availableWidth,
        fontScale: scale,
      );
      expect(h, lessThanOrEqualTo(availableHeight + 0.5));
    });

    test('short song with huge availableHeight returns maxScale', () {
      final sections = [_lyricSection(lineCount: 1)];

      final scale = resolveFitFontScale(
        sections: sections,
        viewMode: viewMode,
        availableWidth: availableWidth,
        availableHeight: 100000.0,
        minScale: min,
        maxScale: max,
      );

      expect(scale, equals(max));
    });

    test('huge song with tiny availableHeight returns minScale', () {
      final sections = List.generate(
        500,
        (i) => _lyricSection(lineCount: 1, label: 'Verse', number: i),
      );

      final scale = resolveFitFontScale(
        sections: sections,
        viewMode: viewMode,
        availableWidth: availableWidth,
        availableHeight: 1.0,
        minScale: min,
        maxScale: max,
      );

      expect(scale, equals(min));
    });

    test('scale is within [minScale, maxScale]', () {
      final sections = [
        _lyricSection(lineCount: 8),
        _lyricSection(lineCount: 8, label: 'Chorus', number: 1),
        _lyricSection(lineCount: 8, label: 'Bridge', number: 1),
      ];

      final scale = resolveFitFontScale(
        sections: sections,
        viewMode: viewMode,
        availableWidth: availableWidth,
        availableHeight: 800.0,
        minScale: min,
        maxScale: max,
      );

      expect(scale, greaterThanOrEqualTo(min));
      expect(scale, lessThanOrEqualTo(max));
    });

    test('works with lyricsOnly viewMode', () {
      final sections = [_lyricSection(lineCount: 5)];
      const availableHeight = 500.0;

      final scale = resolveFitFontScale(
        sections: sections,
        viewMode: SongReaderViewMode.lyricsOnly,
        availableWidth: availableWidth,
        availableHeight: availableHeight,
        minScale: min,
        maxScale: max,
      );

      expect(scale, greaterThanOrEqualTo(min));
      expect(scale, lessThanOrEqualTo(max));

      final h = estimateSongContentHeight(
        sections: sections,
        viewMode: SongReaderViewMode.lyricsOnly,
        availableWidth: availableWidth,
        fontScale: scale,
      );
      expect(h, lessThanOrEqualTo(availableHeight + 0.5));
    });
  });

  group('estimateSectionHeight', () {
    test('unlabeled section has no header height contribution', () {
      final labeled = SongReaderSectionProjection(
        kind: SongSectionKind.verse,
        label: 'Verse',
        number: 1,
        isUnknown: false,
        lines: [
          SongReaderLyricLineProjection(
            segments: [
              const SongReaderSegmentProjection(displayChord: null, text: 'Hi'),
            ],
          ),
        ],
      );
      final unlabeled = SongReaderSectionProjection(
        kind: SongSectionKind.verse,
        label: 'Unlabeled',
        number: null,
        isUnknown: false,
        lines: [
          SongReaderLyricLineProjection(
            segments: [
              const SongReaderSegmentProjection(displayChord: null, text: 'Hi'),
            ],
          ),
        ],
      );

      final hLabeled = estimateSectionHeight(
        section: labeled,
        viewMode: viewMode,
        maxWidth: availableWidth,
        fontScale: fontScale,
      );
      final hUnlabeled = estimateSectionHeight(
        section: unlabeled,
        viewMode: viewMode,
        maxWidth: availableWidth,
        fontScale: fontScale,
      );

      expect(hLabeled, greaterThan(hUnlabeled));
    });

    test('tab block contributes rawLines count to height', () {
      final withTab = SongReaderSectionProjection(
        kind: SongSectionKind.verse,
        label: 'Unlabeled',
        number: null,
        isUnknown: false,
        lines: [
          SongReaderTabProjection(rawLines: ['e|--0--', 'B|--1--', 'G|--2--']),
        ],
      );
      final withOneLine = SongReaderSectionProjection(
        kind: SongSectionKind.verse,
        label: 'Unlabeled',
        number: null,
        isUnknown: false,
        lines: [
          SongReaderTabProjection(rawLines: ['e|--0--']),
        ],
      );

      final hTab = estimateSectionHeight(
        section: withTab,
        viewMode: viewMode,
        maxWidth: availableWidth,
        fontScale: fontScale,
      );
      final hOneLine = estimateSectionHeight(
        section: withOneLine,
        viewMode: viewMode,
        maxWidth: availableWidth,
        fontScale: fontScale,
      );

      expect(hTab, greaterThan(hOneLine));
    });
  });
}
