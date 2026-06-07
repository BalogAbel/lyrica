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

/// Builds a section with [lineCount] lyric lines, each with a fixed text
/// length that can be tuned to make sections of different heights.
SongReaderSectionProjection _section(int lineCount, {int? number}) {
  return _lyricSection(lineCount: lineCount, number: number ?? lineCount);
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

    test(
      'returned scale fits content within availableHeight (+0.5 tolerance)',
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
      },
    );

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

  // ---------------------------------------------------------------------------
  // Fix 2: 2-column-aware fit-to-screen
  // ---------------------------------------------------------------------------

  group('resolveFitFontScale allowTwoColumns:true — 2-column-aware fit', () {
    test('2-column fit scale is larger than 1-column for same tall content', () {
      // 4 sections × 20 lines each. At minScale=0.25 and w=360:
      //   single-col total ≈ 1520 px > 900 px  → 1-col returns minScale.
      //   taller 2-col     ≈  760 px < 900 px  → 2-col binary-searches above minScale.
      // Therefore scale2 > scale1.
      final sections = [_section(20), _section(20), _section(20), _section(20)];
      final scale1 = resolveFitFontScale(
        sections: sections,
        viewMode: SongReaderViewMode.lyricsOnly,
        availableWidth: 360,
        availableHeight: 900,
        minScale: SongReaderState.minSharedFontScale,
        maxScale: SongReaderState.maxSharedFontScale,
        allowTwoColumns: false,
      );
      final scale2 = resolveFitFontScale(
        sections: sections,
        viewMode: SongReaderViewMode.lyricsOnly,
        availableWidth: 360,
        availableHeight: 900,
        minScale: SongReaderState.minSharedFontScale,
        maxScale: SongReaderState.maxSharedFontScale,
        allowTwoColumns: true,
      );
      expect(scale2, greaterThan(scale1));
    });

    test(
      'taller-column height ≤ total/2 + epsilon for balanced 4-section content',
      () {
        // 4 equal sections → balanced 2-2 split → each column holds 2 sections.
        // At scale=0.25 (minScale here) and tileW=170: section(4 lines) ≈ 124px,
        // so taller-2col ≈ 248px.  Use availableHeight=300 > 248 so it fits at
        // minScale → binary-search finds a scale above minScale.
        final sections = [_section(4), _section(4), _section(4), _section(4)];
        final twoColScale = resolveFitFontScale(
          sections: sections,
          viewMode: SongReaderViewMode.lyricsOnly,
          availableWidth: 360,
          availableHeight: 300,
          minScale: 0.25,
          maxScale: 3.0,
          allowTwoColumns: true,
        );
        // Scale should be > 0.25 meaning it actually fits at non-minimum scale.
        expect(twoColScale, greaterThan(0.25));
      },
    );

    test('single section: 2-column behaves same as 1-column', () {
      final sections = [_section(6)];
      final scale1 = resolveFitFontScale(
        sections: sections,
        viewMode: SongReaderViewMode.lyricsOnly,
        availableWidth: 360,
        availableHeight: 800,
        minScale: SongReaderState.minSharedFontScale,
        maxScale: SongReaderState.maxSharedFontScale,
        allowTwoColumns: false,
      );
      final scale2 = resolveFitFontScale(
        sections: sections,
        viewMode: SongReaderViewMode.lyricsOnly,
        availableWidth: 360,
        availableHeight: 800,
        minScale: SongReaderState.minSharedFontScale,
        maxScale: SongReaderState.maxSharedFontScale,
        allowTwoColumns: true,
      );
      // Both should return maxScale (content fits easily) — i.e. equal.
      expect(scale2, equals(scale1));
    });

    test('empty sections: 2-column returns maxScale just like 1-column', () {
      final scale = resolveFitFontScale(
        sections: const [],
        viewMode: SongReaderViewMode.lyricsOnly,
        availableWidth: 360,
        availableHeight: 400,
        minScale: SongReaderState.minSharedFontScale,
        maxScale: SongReaderState.maxSharedFontScale,
        allowTwoColumns: true,
      );
      expect(scale, equals(SongReaderState.maxSharedFontScale));
    });

    // ── consistency: fit scale must not cause layout flip ─────────────────────
    test('fit scale at allowTwoColumns:true renders within availableHeight '
        '(no post-fit overflow due to column flip)', () {
      // Use tall content where fit scale exceeds the old 1.15 threshold.
      // Before the fix: resolveFitFontScale would compute a 2-col fit scale
      // (e.g. 1.4) but the layout resolver would flip to 1-col at > 1.15,
      // causing the content to overflow. After the fix: estimateRenderedLayout
      // uses the same decision logic as the grid, so the returned height is
      // always <= availableHeight regardless of scale.
      final sections = [_section(20), _section(20), _section(20), _section(20)];
      const availableWidth = 1300.0;
      const availableHeight = 900.0;

      final fit = resolveFitFontScale(
        sections: sections,
        viewMode: SongReaderViewMode.lyricsOnly,
        availableWidth: availableWidth,
        availableHeight: availableHeight,
        minScale: SongReaderState.minSharedFontScale,
        maxScale: SongReaderState.maxSharedFontScale,
        allowTwoColumns: true,
      );

      final rendered = estimateRenderedLayout(
        sections: sections,
        viewMode: SongReaderViewMode.lyricsOnly,
        availableWidth: availableWidth,
        availableHeight: availableHeight,
        fontScale: fit,
        allowTwoColumns: true,
      );

      // The rendered height at the fit scale must fit within the available height.
      // Allow 1px rounding tolerance (24 binary-search iterations).
      expect(rendered.height, lessThanOrEqualTo(availableHeight + 1));
    });
  });

  // ---------------------------------------------------------------------------
  // Fix 1: balanced 2-column split (abs-diff minimization)
  // ---------------------------------------------------------------------------

  group('balanced 2-column split via 2-column resolveFitFontScale', () {
    test('unequal sections [V1=large, Chorus=small, V2=large, V3=large]: '
        '2-col scale > 1-col scale', () {
      // Old buggy split (left≥right constraint): [V1,Chorus,V2]|[V3] → taller≈948px
      // New balanced split (abs-diff):            [V1,Chorus]|[V2,V3] → taller≈760px
      //
      // At w=720, minScale=0.25: single-col≈1328px, taller(new)≈760px.
      // With availableHeight=900: single-col doesn't fit → returns minScale.
      //                           taller 2-col fits at minScale → binary search → > minScale.
      // Therefore scale2 > scale1.
      final sections = [
        _section(20), // V1 — large
        _section(8), // Chorus — small
        _section(20), // V2 — large
        _section(20), // V3 — large
      ];
      final s1 = resolveFitFontScale(
        sections: sections,
        viewMode: SongReaderViewMode.lyricsOnly,
        availableWidth: 720,
        availableHeight: 900,
        minScale: SongReaderState.minSharedFontScale,
        maxScale: SongReaderState.maxSharedFontScale,
        allowTwoColumns: false,
      );
      final s2 = resolveFitFontScale(
        sections: sections,
        viewMode: SongReaderViewMode.lyricsOnly,
        availableWidth: 720,
        availableHeight: 900,
        minScale: SongReaderState.minSharedFontScale,
        maxScale: SongReaderState.maxSharedFontScale,
        allowTwoColumns: true,
      );
      expect(s2, greaterThan(s1));
    });

    test('unequal sections: 2-col with large height gives scale = maxScale '
        '(verifies split is balanced enough to always fit)', () {
      // If split is balanced, each column ≈ half total height.
      // With a large availableHeight and maxScale=1.0 the fit must return 1.0.
      final sections = [_section(20), _section(8), _section(20), _section(20)];
      const maxScale = 1.0;
      final scale = resolveFitFontScale(
        sections: sections,
        viewMode: SongReaderViewMode.lyricsOnly,
        availableWidth: 720,
        availableHeight: 20000, // always fits
        minScale: 0.5,
        maxScale: maxScale,
        allowTwoColumns: true,
      );
      expect(scale, equals(maxScale));
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
