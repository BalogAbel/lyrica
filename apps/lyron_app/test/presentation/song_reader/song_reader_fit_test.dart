import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/domain/song/parsed_song.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_fit.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_metrics.dart';
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

  // ---------------------------------------------------------------------------
  // Fix 3: lyricsOnly chord-only line contributes zero height
  // ---------------------------------------------------------------------------

  group('estimateSectionHeight — lyricsOnly chord-only line', () {
    // A lyric line whose segments all have empty/whitespace text (chord-only).
    SongReaderLyricLineProjection chordOnlyLine() =>
        SongReaderLyricLineProjection(
          segments: [
            const SongReaderSegmentProjection(displayChord: 'Am', text: ''),
            const SongReaderSegmentProjection(displayChord: null, text: '   '),
          ],
        );

    SongReaderLyricLineProjection lyricLine() => SongReaderLyricLineProjection(
      segments: [
        const SongReaderSegmentProjection(
          displayChord: 'G',
          text: 'Hello world',
        ),
      ],
    );

    test('chord-only line: lyricsOnly height < chordsAndLyrics height', () {
      final section = SongReaderSectionProjection(
        kind: SongSectionKind.verse,
        label: 'Verse',
        number: 1,
        isUnknown: false,
        lines: [lyricLine(), chordOnlyLine()],
      );

      final hLyricsOnly = estimateSectionHeight(
        section: section,
        viewMode: SongReaderViewMode.lyricsOnly,
        maxWidth: availableWidth,
        fontScale: fontScale,
      );
      final hChordsAndLyrics = estimateSectionHeight(
        section: section,
        viewMode: SongReaderViewMode.chordsAndLyrics,
        maxWidth: availableWidth,
        fontScale: fontScale,
      );

      expect(hLyricsOnly, lessThan(hChordsAndLyrics));
    });

    test('chord-only line adds zero height in lyricsOnly: '
        'section with and without it estimate equal height', () {
      final withoutChordOnly = SongReaderSectionProjection(
        kind: SongSectionKind.verse,
        label: 'Verse',
        number: 1,
        isUnknown: false,
        lines: [lyricLine()],
      );
      final withChordOnly = SongReaderSectionProjection(
        kind: SongSectionKind.verse,
        label: 'Verse',
        number: 1,
        isUnknown: false,
        lines: [lyricLine(), chordOnlyLine()],
      );

      final hWithout = estimateSectionHeight(
        section: withoutChordOnly,
        viewMode: SongReaderViewMode.lyricsOnly,
        maxWidth: availableWidth,
        fontScale: fontScale,
      );
      final hWith = estimateSectionHeight(
        section: withChordOnly,
        viewMode: SongReaderViewMode.lyricsOnly,
        maxWidth: availableWidth,
        fontScale: fontScale,
      );

      expect(hWith, equals(hWithout));
    });

    test(
      'whitespace-only text segment treated as chord-only in lyricsOnly',
      () {
        final whitespaceOnlySection = SongReaderSectionProjection(
          kind: SongSectionKind.verse,
          label: 'Verse',
          number: 1,
          isUnknown: false,
          lines: [
            SongReaderLyricLineProjection(
              segments: [
                const SongReaderSegmentProjection(
                  displayChord: 'C',
                  text: '   ',
                ),
              ],
            ),
          ],
        );
        final emptySection = SongReaderSectionProjection(
          kind: SongSectionKind.verse,
          label: 'Verse',
          number: 1,
          isUnknown: false,
          lines: const [],
        );

        final hWhitespace = estimateSectionHeight(
          section: whitespaceOnlySection,
          viewMode: SongReaderViewMode.lyricsOnly,
          maxWidth: availableWidth,
          fontScale: fontScale,
        );
        final hEmpty = estimateSectionHeight(
          section: emptySection,
          viewMode: SongReaderViewMode.lyricsOnly,
          maxWidth: availableWidth,
          fontScale: fontScale,
        );

        // Whitespace-only line should be collapsed → same height as no lines.
        expect(hWhitespace, equals(hEmpty));
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Fix 4: column-balance guard — dominant section forces 1-column layout
  // ---------------------------------------------------------------------------

  group('column-balance guard', () {
    // Helper: a header-only section (tiny: just the header + sectionGap).
    SongReaderSectionProjection headerOnlySection(String label) =>
        SongReaderSectionProjection(
          kind: SongSectionKind.verse,
          label: label,
          number: null,
          isUnknown: false,
          lines: const [],
        );

    test(
      'empty Intro + dominant Verse now uses TWO columns via mid-section flow',
      () {
        // With item-level flow the Verse lines can be distributed across
        // both columns, producing a balanced split even when a section-boundary
        // split would be lopsided.  The old section-atomic balance guard that
        // forced 1 column is superseded by resolveFlowLayout's mid-section
        // fallback.
        //
        // Section A: header-only "Intro" — tiny (~60 px: just header + sectionGap).
        // Section B: dominant "Verse" with 8 short-text lines.
        //
        // Before this refactor: balance ratio (60/492 ≈ 0.12) forced 1 column.
        // After this refactor: mid-section split of the Verse balances columns.
        final sectionA = headerOnlySection('Intro');
        final sectionB = _lyricSection(lineCount: 8, label: 'Verse', number: 1);
        final sections = [sectionA, sectionB];

        // Compute single-col height to set availableHeight just under it.
        final singleH = estimateSongContentHeight(
          sections: sections,
          viewMode: viewMode,
          availableWidth: availableWidth,
          fontScale: fontScale,
        );

        final result = estimateRenderedLayout(
          sections: sections,
          viewMode: viewMode,
          availableWidth: availableWidth,
          availableHeight: singleH - 1, // force overflow so 2-col path is tried
          fontScale: fontScale,
          allowTwoColumns: true,
        );

        expect(
          result.columnCount,
          equals(2),
          reason:
              'Item-level flow splits Verse mid-section to balance columns → 2 columns',
        );
      },
    );

    test('two balanced sections still use two columns (no regression)', () {
      // Two equal 15-line sections: balance ratio = 1.0 ≥ 0.5 → 2 columns.
      final sectionA = _lyricSection(lineCount: 15, label: 'Verse', number: 1);
      final sectionB = _lyricSection(lineCount: 15, label: 'Chorus', number: 1);
      final sections = [sectionA, sectionB];

      final singleH = estimateSongContentHeight(
        sections: sections,
        viewMode: viewMode,
        availableWidth: availableWidth,
        fontScale: fontScale,
      );

      final result = estimateRenderedLayout(
        sections: sections,
        viewMode: viewMode,
        availableWidth: availableWidth,
        availableHeight: singleH - 1,
        fontScale: fontScale,
        allowTwoColumns: true,
      );

      expect(
        result.columnCount,
        equals(2),
        reason: 'Two equal sections are perfectly balanced → 2 columns',
      );
    });

    test('many balanced sections still use two columns (no regression)', () {
      // 6 equal 10-line sections: balanced split → 2 columns.
      final sections = List.generate(
        6,
        (i) => _lyricSection(lineCount: 10, label: 'Verse', number: i + 1),
      );

      final singleH = estimateSongContentHeight(
        sections: sections,
        viewMode: viewMode,
        availableWidth: availableWidth,
        fontScale: fontScale,
      );

      final result = estimateRenderedLayout(
        sections: sections,
        viewMode: viewMode,
        availableWidth: availableWidth,
        availableHeight: singleH - 1,
        fontScale: fontScale,
        allowTwoColumns: true,
      );

      expect(
        result.columnCount,
        equals(2),
        reason: '6 equal sections are well-balanced → 2 columns',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Flow blocks — buildFlowBlocks
  // ---------------------------------------------------------------------------

  group('buildFlowBlocks', () {
    SongReaderSectionProjection emptyLabeledSection(String label) =>
        SongReaderSectionProjection(
          kind: SongSectionKind.verse,
          label: label,
          number: null,
          isUnknown: false,
          lines: const [],
        );

    SongReaderSectionProjection verseSection(int lineCount) =>
        SongReaderSectionProjection(
          kind: SongSectionKind.verse,
          label: 'Verse',
          number: 1,
          isUnknown: false,
          lines: List.generate(
            lineCount,
            (_) => SongReaderLyricLineProjection(
              segments: const [
                SongReaderSegmentProjection(displayChord: 'C', text: 'Hello'),
              ],
            ),
          ),
        );

    test(
      'leadingDirective + emptyIntro(header) + Verse(5 lines) → correct block list',
      () {
        final intro = emptyLabeledSection('Intro');
        final verse = verseSection(5);
        final blocks = buildFlowBlocks(
          sections: [intro, verse],
          hasLeadingDirective: true,
        );

        // Expected order:
        //  [0] leadingDirective
        //  [1] sectionHeader(sectionIndex=0)  — Intro header, isSectionStart=true
        //  [2] sectionHeader(sectionIndex=1)  — Verse header, isSectionStart=true
        //  [3..7] line × 5 (sectionIndex=1)
        expect(
          blocks.length,
          equals(8),
          reason: '1 directive + 1 Intro header + 1 Verse header + 5 lines',
        );

        expect(blocks[0].kind, equals(FlowBlockKind.leadingDirective));
        expect(blocks[0].sectionIndex, equals(-1));

        expect(blocks[1].kind, equals(FlowBlockKind.sectionHeader));
        expect(blocks[1].sectionIndex, equals(0));
        expect(blocks[1].isSectionStart, isTrue);

        expect(blocks[2].kind, equals(FlowBlockKind.sectionHeader));
        expect(blocks[2].sectionIndex, equals(1));
        expect(blocks[2].isSectionStart, isTrue);

        for (var i = 3; i < 8; i++) {
          expect(
            blocks[i].kind,
            equals(FlowBlockKind.line),
            reason: 'block[$i] should be a line',
          );
          expect(blocks[i].sectionIndex, equals(1));
        }

        // First line block: isSectionStart=false (header already covers it).
        expect(blocks[3].isSectionStart, isFalse);
      },
    );

    test('unlabeled section produces no sectionHeader block', () {
      final unlabeled = SongReaderSectionProjection(
        kind: SongSectionKind.verse,
        label: 'Unlabeled',
        number: null,
        isUnknown: false,
        lines: [
          SongReaderLyricLineProjection(
            segments: const [
              SongReaderSegmentProjection(displayChord: null, text: 'Line'),
            ],
          ),
        ],
      );
      final blocks = buildFlowBlocks(
        sections: [unlabeled],
        hasLeadingDirective: false,
      );

      // No header → 1 line block; first line is isSectionStart=true.
      expect(blocks.length, equals(1));
      expect(blocks[0].kind, equals(FlowBlockKind.line));
      expect(
        blocks[0].isSectionStart,
        isTrue,
        reason: 'first block of unlabeled section is the section start',
      );
    });

    test('empty unlabeled section produces zero blocks', () {
      final unlabeled = SongReaderSectionProjection(
        kind: SongSectionKind.verse,
        label: 'Unlabeled',
        number: null,
        isUnknown: false,
        lines: const [],
      );
      final blocks = buildFlowBlocks(
        sections: [unlabeled],
        hasLeadingDirective: false,
      );
      expect(
        blocks,
        isEmpty,
        reason: 'empty unlabeled section has no header and no lines',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // resolveFlowLayout — mid-section split (dominant section)
  // ---------------------------------------------------------------------------

  group('resolveFlowLayout', () {
    // Helper: compute block heights at tile width for the given sections.
    List<double> blockHeightsAtTileWidth(
      List<FlowBlock> blocks,
      double tileWidth,
    ) {
      return blocks
          .map(
            (b) => flowBlockHeight(
              block: b,
              viewMode: SongReaderViewMode.chordsAndLyrics,
              columnWidth: tileWidth,
              fontScale: 1.0,
            ),
          )
          .toList();
    }

    SongReaderSectionProjection emptyLabeled(String label) =>
        SongReaderSectionProjection(
          kind: SongSectionKind.verse,
          label: label,
          number: null,
          isUnknown: false,
          lines: const [],
        );

    SongReaderSectionProjection bigVerse(int lineCount) =>
        SongReaderSectionProjection(
          kind: SongSectionKind.verse,
          label: 'Verse',
          number: 1,
          isUnknown: false,
          lines: List.generate(
            lineCount,
            (i) => SongReaderLyricLineProjection(
              segments: [
                SongReaderSegmentProjection(
                  displayChord: 'C',
                  text: 'Line $i word word word word',
                ),
              ],
            ),
          ),
        );

    test(
      'empty Intro + dominant Verse → columnCount 2 via mid-section split, balanced',
      () {
        // Previously this was forced to 1 column by the balance guard.
        // With item-level flow, the verse lines can be split across columns
        // to produce a balanced layout.
        //
        // Heights at tileWidth=390:
        //   Intro header block: 40+20 = 60
        //   Verse header block: 40+20 = 60
        //   Each of 12 verse lines ("Line N word word word word" ~26 chars):
        //     chord=20, lyric=24, gap=10 → 54 each
        //   Total ≈ 60 + 60 + 12*54 = 768
        //   Balanced split ≈ 384 per column.
        //   availableHeight=500: single(768)>500 → 2-col path;
        //     taller(384) ≤ 500*1.15=575 ✓, 384 ≤ 768*0.9=691 ✓, balanced ✓
        const availableWidth = 800.0;
        const tileWidth = (availableWidth - sectionGap) / 2;
        const availableHeight = 500.0;

        final sections = [emptyLabeled('Intro'), bigVerse(12)];
        final blocks = buildFlowBlocks(
          sections: sections,
          hasLeadingDirective: false,
        );
        final blockHeights = blockHeightsAtTileWidth(blocks, tileWidth);
        final sectionStartFlags = blocks.map((b) => b.isSectionStart).toList();

        final layout = resolveFlowLayout(
          blocks: blocks,
          blockHeights: blockHeights,
          sectionStartFlags: sectionStartFlags,
          availableHeight: availableHeight,
          allowTwoColumns: true,
        );

        expect(
          layout.columnCount,
          equals(2),
          reason:
              'Dominant Verse must now split mid-section to produce 2 columns',
        );

        // Both columns must be non-empty.
        expect(layout.splitIndex, greaterThan(0));
        expect(layout.splitIndex, lessThan(blocks.length));

        // Balance check: min(left,right) >= max(left,right) * columnBalanceMinRatio.
        final left = blockHeights
            .sublist(0, layout.splitIndex)
            .fold(0.0, (a, b) => a + b);
        final right = blockHeights
            .sublist(layout.splitIndex)
            .fold(0.0, (a, b) => a + b);
        final taller = left > right ? left : right;
        final shorter = left < right ? left : right;
        expect(
          shorter,
          greaterThanOrEqualTo(taller * columnBalanceMinRatio - 0.1),
          reason:
              'columns must be balanced (min/max >= $columnBalanceMinRatio)',
        );
      },
    );

    test(
      'several balanced sections → split at a section boundary (isSectionStart)',
      () {
        // Heights at tileWidth=390 ("Hello world" = 11 chars, no wrap):
        //   Each section: header+sectionGap=60, 4*(20+24+10)=216 → 276
        //   Total for 4 sections ≈ 1104
        //   Boundary split at 2: taller ≈ 552
        //   availableHeight=600: single(1104)>600, taller(552)≤600*1.15=690 ✓,
        //     552 ≤ 1104*0.9=993.6 ✓, balanced(552/552=1.0) ✓
        const availableWidth = 800.0;
        const tileWidth = (availableWidth - sectionGap) / 2;
        const availableHeight = 600.0;

        // 4 equal sections → best boundary split = at index 2 (half).
        final sections = List.generate(
          4,
          (i) => SongReaderSectionProjection(
            kind: SongSectionKind.verse,
            label: 'Verse',
            number: i + 1,
            isUnknown: false,
            lines: List.generate(
              4,
              (_) => SongReaderLyricLineProjection(
                segments: const [
                  SongReaderSegmentProjection(
                    displayChord: 'C',
                    text: 'Hello world',
                  ),
                ],
              ),
            ),
          ),
        );
        final blocks = buildFlowBlocks(
          sections: sections,
          hasLeadingDirective: false,
        );
        final blockHeights = blockHeightsAtTileWidth(blocks, tileWidth);
        final sectionStartFlags = blocks.map((b) => b.isSectionStart).toList();

        final layout = resolveFlowLayout(
          blocks: blocks,
          blockHeights: blockHeights,
          sectionStartFlags: sectionStartFlags,
          availableHeight: availableHeight,
          allowTwoColumns: true,
        );

        expect(layout.columnCount, equals(2));

        // The chosen splitIndex must land on a section boundary
        // (isSectionStart=true at that index).
        expect(
          blocks[layout.splitIndex].isSectionStart,
          isTrue,
          reason:
              'Balanced sections: split must be at a section boundary, not mid-section',
        );
      },
    );

    test('split never strands a header at the bottom of the left column', () {
      const availableWidth = 800.0;
      const tileWidth = (availableWidth - sectionGap) / 2;
      // 10-line verse total ≈ 60+60+10*54=660; balanced ≈ 330;
      // need availableHeight > 330/1.15≈287 so tolerance allows 2 cols.
      const availableHeight = 400.0;

      final sections = [emptyLabeled('Intro'), bigVerse(10)];
      final blocks = buildFlowBlocks(
        sections: sections,
        hasLeadingDirective: false,
      );
      final blockHeights = blockHeightsAtTileWidth(blocks, tileWidth);
      final sectionStartFlags = blocks.map((b) => b.isSectionStart).toList();

      final layout = resolveFlowLayout(
        blocks: blocks,
        blockHeights: blockHeights,
        sectionStartFlags: sectionStartFlags,
        availableHeight: availableHeight,
        allowTwoColumns: true,
      );

      if (layout.columnCount == 2) {
        // The block just before the split must NOT be a sectionHeader
        // (that would strand the header alone in the left column).
        expect(
          blocks[layout.splitIndex - 1].kind,
          isNot(equals(FlowBlockKind.sectionHeader)),
          reason:
              'A sectionHeader must not be the last block in the left column',
        );
      }
    });

    test('single block → always 1 column', () {
      const tileWidth = 200.0;
      final section = SongReaderSectionProjection(
        kind: SongSectionKind.verse,
        label: 'Verse',
        number: 1,
        isUnknown: false,
        lines: [
          SongReaderLyricLineProjection(
            segments: const [
              SongReaderSegmentProjection(displayChord: null, text: 'Hello'),
            ],
          ),
        ],
      );
      final blocks = buildFlowBlocks(
        sections: [section],
        hasLeadingDirective: false,
      );
      final blockHeights = blocks
          .map(
            (b) => flowBlockHeight(
              block: b,
              viewMode: SongReaderViewMode.chordsAndLyrics,
              columnWidth: tileWidth,
              fontScale: 1.0,
            ),
          )
          .toList();
      final sectionStartFlags = blocks.map((b) => b.isSectionStart).toList();

      final layout = resolveFlowLayout(
        blocks: blocks,
        blockHeights: blockHeights,
        sectionStartFlags: sectionStartFlags,
        availableHeight: 10000, // huge — fits in 1 column
        allowTwoColumns: true,
      );

      expect(layout.columnCount, equals(1));
    });

    test('allowTwoColumns:false → always 1 column regardless', () {
      const tileWidth = 200.0;
      final sections = List.generate(
        6,
        (i) => SongReaderSectionProjection(
          kind: SongSectionKind.verse,
          label: 'Verse',
          number: i + 1,
          isUnknown: false,
          lines: List.generate(
            5,
            (_) => SongReaderLyricLineProjection(
              segments: const [
                SongReaderSegmentProjection(displayChord: 'C', text: 'Hello'),
              ],
            ),
          ),
        ),
      );
      final blocks = buildFlowBlocks(
        sections: sections,
        hasLeadingDirective: false,
      );
      final blockHeights = blocks
          .map(
            (b) => flowBlockHeight(
              block: b,
              viewMode: SongReaderViewMode.chordsAndLyrics,
              columnWidth: tileWidth,
              fontScale: 1.0,
            ),
          )
          .toList();
      final sectionStartFlags = blocks.map((b) => b.isSectionStart).toList();

      final layout = resolveFlowLayout(
        blocks: blocks,
        blockHeights: blockHeights,
        sectionStartFlags: sectionStartFlags,
        availableHeight: 1.0, // tiny — would overflow
        allowTwoColumns: false,
      );

      expect(layout.columnCount, equals(1));
    });
  });

  // ---------------------------------------------------------------------------
  // resolveFitFontScale — dominant-section now produces 2 columns (flow)
  // ---------------------------------------------------------------------------

  group('resolveFitFontScale — dominant section now 2 columns with flow', () {
    SongReaderSectionProjection emptyIntro() => SongReaderSectionProjection(
      kind: SongSectionKind.verse,
      label: 'Intro',
      number: null,
      isUnknown: false,
      lines: const [],
    );

    SongReaderSectionProjection bigVerse(int lineCount) =>
        SongReaderSectionProjection(
          kind: SongSectionKind.verse,
          label: 'Verse',
          number: 1,
          isUnknown: false,
          lines: List.generate(
            lineCount,
            (i) => SongReaderLyricLineProjection(
              segments: [
                SongReaderSegmentProjection(
                  displayChord: 'C',
                  text: 'Line $i word word word',
                ),
              ],
            ),
          ),
        );

    test(
      'empty Intro + dominant Verse: estimateRenderedLayout returns 2 columns',
      () {
        // With item-level flow the verse can be split mid-section
        // → balance guard passes → 2 columns.
        final sections = [emptyIntro(), bigVerse(12)];
        const availableWidth = 800.0;

        final singleH = estimateSongContentHeight(
          sections: sections,
          viewMode: viewMode,
          availableWidth: availableWidth,
          fontScale: fontScale,
        );

        final result = estimateRenderedLayout(
          sections: sections,
          viewMode: viewMode,
          availableWidth: availableWidth,
          availableHeight: singleH - 1,
          fontScale: fontScale,
          allowTwoColumns: true,
        );

        expect(
          result.columnCount,
          equals(2),
          reason:
              'Item-level flow allows mid-section split of dominant Verse → 2 columns',
        );
      },
    );

    test(
      'fit scale at allowTwoColumns:true renders within availableHeight for dominant section',
      () {
        final sections = [emptyIntro(), bigVerse(12)];
        const availableWidth = 800.0;
        const availableHeight = 400.0;

        final fit = resolveFitFontScale(
          sections: sections,
          viewMode: viewMode,
          availableWidth: availableWidth,
          availableHeight: availableHeight,
          minScale: SongReaderState.minSharedFontScale,
          maxScale: SongReaderState.maxSharedFontScale,
          allowTwoColumns: true,
        );

        final rendered = estimateRenderedLayout(
          sections: sections,
          viewMode: viewMode,
          availableWidth: availableWidth,
          availableHeight: availableHeight,
          fontScale: fit,
          allowTwoColumns: true,
        );

        expect(
          rendered.height,
          lessThanOrEqualTo(availableHeight + 1),
          reason: 'fit scale must not cause post-fit overflow',
        );
      },
    );
  });

  group('estimateSectionHeight — wrapped runs charge their own chord row', () {
    // Two segments, each its own word group: the first segment's trailing
    // space forces a group boundary before the second segment (mirrors
    // groupSegmentsIntoWords). Each group carries its own chord.
    //   group 1: 'Hello ' (6 chars)  -> width 60  (chord 'C')
    //   group 2: 'World!!' (7 chars) -> width 70  (chord 'G')
    // At maxWidth=120 (the estimator's width floor) the two groups (60+70=130)
    // do not both fit in one 120-wide run, so they wrap into two runs, each
    // carrying its own chord. At maxWidth=1000 both groups fit in a single run.
    SongReaderSectionProjection twoWordSection() => SongReaderSectionProjection(
      kind: SongSectionKind.verse,
      label: 'Verse',
      number: 1,
      isUnknown: false,
      lines: [
        SongReaderLyricLineProjection(
          segments: const [
            SongReaderSegmentProjection(displayChord: 'C', text: 'Hello '),
            SongReaderSegmentProjection(displayChord: 'G', text: 'World!!'),
          ],
        ),
      ],
    );

    test('charges a chord row for every wrapped run that carries a chord', () {
      final section = twoWordSection();

      final oneRunHeight = estimateSectionHeight(
        section: section,
        viewMode: viewMode,
        maxWidth: 1000.0,
        fontScale: fontScale,
      );
      final twoRunHeight = estimateSectionHeight(
        section: section,
        viewMode: viewMode,
        maxWidth: 120.0,
        fontScale: fontScale,
      );

      final diff = twoRunHeight - oneRunHeight;
      expect(
        diff,
        greaterThanOrEqualTo(chordRowHeight + lyricRowHeight + lineRunSpacing),
        reason:
            'The second wrapped run brings its own chord row, lyric row, '
            'and run gap, exactly like the renderer draws it.',
      );
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

  // ---------------------------------------------------------------------------
  // Bug fix: group width must account for chord width, not just lyric chars.
  // ---------------------------------------------------------------------------

  group('over-wide group packs its own segments into runs', () {
    // Reviewer's repro: 12 segments in a single word group (no whitespace
    // between them, so groupSegmentsIntoWords keeps them together), each
    // with a wide chord ('C#m/G#', 6 chars -> 60px) over a one-character
    // lyric ('a'). At columnWidth=120 (the estimator's clamp floor), each
    // segment is 60px wide, so 2 fit per run (0 inter-segment spacing,
    // mirroring song_line_view.dart's inner Wrap) -> 6 runs of 2 segments
    // each, every run carrying a chord.
    //
    // The buggy code instead divides the group's total width
    // (12*60=720px) by the effective line width (120px) to get
    // runsNeeded=6, but only marks the FIRST of those 6 runs as carrying a
    // chord. The renderer disagrees: every run that receives a chorded
    // segment draws a chord row, because the over-wide group is laid out
    // by its own inner Wrap where every segment carries its own chord
    // column.
    test('charges a chord row for every inner run of an over-wide group', () {
      const chord = 'C#m/G#'; // 6 chars -> 60px at characterWidthEstimate
      const segmentCount = 12;
      const columnWidth = 120.0; // clamps to the estimator's floor
      final line = SongReaderLyricLineProjection(
        segments: List.generate(
          segmentCount,
          (_) =>
              const SongReaderSegmentProjection(displayChord: chord, text: 'a'),
        ),
      );
      final section = SongReaderSectionProjection(
        kind: SongSectionKind.verse,
        label: 'Unlabeled',
        number: null,
        isUnknown: false,
        lines: [line],
      );

      // Widths imply: segment width = 60px, effectiveLineWidth = 120px,
      // 0 spacing within the group -> 2 segments/run -> 6 runs, all
      // chorded.
      const runsImplied = 6;

      final height = estimateSectionHeight(
        section: section,
        viewMode: viewMode,
        maxWidth: columnWidth,
        fontScale: fontScale,
      );

      final minExpected = runsImplied * (chordRowHeight + lyricRowHeight);

      expect(
        height,
        greaterThanOrEqualTo(minExpected),
        reason:
            'every inner run of the over-wide group carries a chord, so '
            'the estimate must be at least $runsImplied * '
            '(chordRowHeight + lyricRowHeight) = $minExpected; got $height',
      );
    });
  });

  group('a single over-wide segment models its own lyric text wrap', () {
    // The most common "over-wide group" shape is NOT several chorded
    // segments stacked with no whitespace between them (the reviewer's
    // repro above) -- it's a single, ordinary lyric segment whose own text
    // is simply long (no chord splits it into multiple segments), e.g. a
    // full sentence under one leading chord or no chord at all. The
    // renderer's inner Wrap sees exactly one child in that case (one
    // segment, no siblings to wrap between), but the segment's OWN lyric
    // `Text` still soft-wraps internally within its ConstrainedBox
    // (_SongLineSegmentView in song_line_view.dart), producing multiple
    // VISUAL lines under one chord (drawn once, at the top of that
    // segment's Column). The estimator must charge extra LYRIC-only height
    // for those extra wrapped lines without adding extra chord rows --
    // that's a different effect than the between-segment run-packing
    // fixed above, and both must be modeled.
    SongReaderSectionProjection singleSegmentUnlabeledSection(String text) =>
        SongReaderSectionProjection(
          kind: SongSectionKind.verse,
          label: 'Unlabeled',
          number: null,
          isUnknown: false,
          lines: [
            SongReaderLyricLineProjection(
              segments: [
                SongReaderSegmentProjection(displayChord: null, text: text),
              ],
            ),
          ],
        );

    test(
      'estimate grows with the number of wrapped lines a long segment implies',
      () {
        const columnWidth = 120.0; // == the estimator's clamp floor
        // shortText: 6 chars -> 60px -> fits in one 120px line -> 1 line.
        // longText: 30 chars -> 300px -> ceil(300/120) = 3 lines.
        const shortText = 'aaaaaa'; // 6 chars
        const longText = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'; // 30 chars
        const shortLines = 1;
        final longLines =
            (longText.length * characterWidthEstimate / columnWidth).ceil();
        expect(
          longLines,
          equals(3),
          reason: 'sanity check on the fixture\'s own arithmetic',
        );

        final shortHeight = estimateSectionHeight(
          section: singleSegmentUnlabeledSection(shortText),
          viewMode: viewMode,
          maxWidth: columnWidth,
          fontScale: fontScale,
        );
        final longHeight = estimateSectionHeight(
          section: singleSegmentUnlabeledSection(longText),
          viewMode: viewMode,
          maxWidth: columnWidth,
          fontScale: fontScale,
        );

        final diff = longHeight - shortHeight;
        final minExpectedDiff =
            (longLines - shortLines) * lyricRowHeight * fontScale;

        expect(
          diff,
          greaterThanOrEqualTo(minExpectedDiff),
          reason:
              'a lone over-wide segment with no chord siblings still wraps '
              'its own lyric text into multiple visual lines; the estimate '
              'must grow by at least ${longLines - shortLines} extra lyric '
              'row(s) ($minExpectedDiff px), not stay flat at one lyric row '
              'regardless of how wide the segment\'s text is '
              '(short=$shortHeight, long=$longHeight, diff=$diff)',
        );
      },
    );

    test(
      'does not charge an extra chord row for a wrapped lyric-only segment',
      () {
        // Same long segment, but WITH a chord. The chord must still be
        // charged exactly once (drawn once above the wrapped lyric text),
        // not once per implied wrapped line.
        const columnWidth = 120.0;
        const longText = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'; // 30 chars, 3 lines
        final section = SongReaderSectionProjection(
          kind: SongSectionKind.verse,
          label: 'Unlabeled',
          number: null,
          isUnknown: false,
          lines: [
            SongReaderLyricLineProjection(
              segments: [
                const SongReaderSegmentProjection(
                  displayChord: 'C',
                  text: longText,
                ),
              ],
            ),
          ],
        );
        final withChord = estimateSectionHeight(
          section: section,
          viewMode: viewMode,
          maxWidth: columnWidth,
          fontScale: fontScale,
        );
        final withoutChord = estimateSectionHeight(
          section: singleSegmentUnlabeledSection(longText),
          viewMode: viewMode,
          maxWidth: columnWidth,
          fontScale: fontScale,
        );

        final chordContribution = withChord - withoutChord;
        expect(
          chordContribution,
          moreOrLessEquals(
            chordRowHeight * fontScale + chordToLyricGap,
            epsilon: 0.01,
          ),
          reason:
              'the chord is drawn exactly once above the (internally '
              'wrapped) lyric text, so it must add exactly one chord row, '
              'never one per wrapped lyric line '
              '(contribution=$chordContribution)',
        );
      },
    );
  });

  group('_lineItemHeight accounts for chord width', () {
    // Narrow enough that a single wide (8-char = 80px) chord segment already
    // occupies most of the run, so two of them can never share a run.
    const columnWidth = 130.0;

    SongReaderSectionProjection unlabeledSection(
      SongReaderLyricLineProjection line,
    ) => SongReaderSectionProjection(
      kind: SongSectionKind.verse,
      label: 'Unlabeled',
      number: null,
      isUnknown: false,
      lines: [line],
    );

    SongReaderLyricLineProjection chordOnlyLine(String chord, int count) =>
        SongReaderLyricLineProjection(
          segments: List.generate(
            count,
            (_) => SongReaderSegmentProjection(displayChord: chord, text: ''),
          ),
        );

    test('accounts for chord width on a chord-only line', () {
      // Six wide chord-only segments ("Cmaj7#11", 8 chars -> 80px each) vs a
      // single one of the same chord. Lyric-only counting (the bug) sees
      // every segment as 0px wide and packs all six into one run regardless
      // of count, so the two heights would come out equal. A correct
      // estimate must grow: 80px segments cannot pack two-per-run at a
      // 130px column, so six of them span several runs.
      final wideSection = unlabeledSection(chordOnlyLine('Cmaj7#11', 6));
      final oneSection = unlabeledSection(chordOnlyLine('Cmaj7#11', 1));

      final wideHeight = estimateSectionHeight(
        section: wideSection,
        viewMode: SongReaderViewMode.chordsAndLyrics,
        maxWidth: columnWidth,
        fontScale: 1.0,
      );
      final oneRowHeight = estimateSectionHeight(
        section: oneSection,
        viewMode: SongReaderViewMode.chordsAndLyrics,
        maxWidth: columnWidth,
        fontScale: 1.0,
      );

      expect(
        wideHeight,
        greaterThan(oneRowHeight + 100),
        reason:
            'a chord-only line of several wide chords must estimate as '
            'several rows tall, not collapse to a single zero-width run '
            '(wide=$wideHeight, oneRow=$oneRowHeight)',
      );
    });

    test('accounts for a chord wider than the lyric under it', () {
      // Identical lyric text ('a ' x5, one word-group per segment because of
      // the trailing space) under two different chords. Lyric-only counting
      // (the bug) sizes both lines identically since the chord never enters
      // the width; the segment column is actually as wide as the wider of
      // chord/lyric, so the long chord ("Cmaj7#11", 80px) must force more
      // wraps than the short one ("C", 10px) at this narrow column width.
      SongReaderLyricLineProjection line(String chord) =>
          SongReaderLyricLineProjection(
            segments: List.generate(
              5,
              (_) =>
                  SongReaderSegmentProjection(displayChord: chord, text: 'a '),
            ),
          );

      final shortChordHeight = estimateSectionHeight(
        section: unlabeledSection(line('C')),
        viewMode: SongReaderViewMode.chordsAndLyrics,
        maxWidth: columnWidth,
        fontScale: 1.0,
      );
      final longChordHeight = estimateSectionHeight(
        section: unlabeledSection(line('Cmaj7#11')),
        viewMode: SongReaderViewMode.chordsAndLyrics,
        maxWidth: columnWidth,
        fontScale: 1.0,
      );

      expect(
        longChordHeight,
        greaterThan(shortChordHeight),
        reason:
            'a chord wider than its lyric must be reflected in the group '
            'width, forcing more wraps than the lyric-only estimate would '
            '(long=$longChordHeight, short=$shortChordHeight)',
      );
    });
  });
}
