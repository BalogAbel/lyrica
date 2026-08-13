import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/app/reader_theme.dart';
import 'package:lyron_app/src/domain/song/parsed_song.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_section_grid.dart';

void main() {
  testWidgets('two-column layout uses column-major section order', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            child: SongReaderSectionGrid(
              sections: [
                SongReaderSectionProjection(
                  kind: SongSectionKind.verse,
                  label: 'Section A',
                  number: null,
                  isUnknown: false,
                  lines: [],
                ),
                SongReaderSectionProjection(
                  kind: SongSectionKind.verse,
                  label: 'Section B',
                  number: null,
                  isUnknown: false,
                  lines: [],
                ),
                SongReaderSectionProjection(
                  kind: SongSectionKind.verse,
                  label: 'Section C',
                  number: null,
                  isUnknown: false,
                  lines: [],
                ),
                SongReaderSectionProjection(
                  kind: SongSectionKind.verse,
                  label: 'Section D',
                  number: null,
                  isUnknown: false,
                  lines: [],
                ),
              ],
              viewMode: SongReaderViewMode.chordsAndLyrics,
              sharedFontScale: 1,
              columnCount: 2,
              availableHeight: 120,
            ),
          ),
        ),
      ),
    );

    final a = tester.getTopLeft(find.text('SECTION A'));
    final b = tester.getTopLeft(find.text('SECTION B'));
    final c = tester.getTopLeft(find.text('SECTION C'));

    expect((b.dx - a.dx).abs(), lessThan(1));
    expect(b.dy, greaterThan(a.dy));
    expect(c.dx, greaterThan(a.dx));
  });

  testWidgets(
    'falls back to one column when one-column content fits viewport',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1000,
              child: SongReaderSectionGrid(
                sections: [
                  SongReaderSectionProjection(
                    kind: SongSectionKind.verse,
                    label: 'Section A',
                    number: null,
                    isUnknown: false,
                    lines: [],
                  ),
                  SongReaderSectionProjection(
                    kind: SongSectionKind.verse,
                    label: 'Section B',
                    number: null,
                    isUnknown: false,
                    lines: [],
                  ),
                ],
                viewMode: SongReaderViewMode.chordsAndLyrics,
                sharedFontScale: 1,
                columnCount: 2,
                availableHeight: 2000,
              ),
            ),
          ),
        ),
      );

      expect(
        find.byKey(const Key('song-reader-section-grid-columns-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('song-reader-section-grid-columns-2')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'uses two columns when wrapped lyrics overflow single-column height',
    (tester) async {
      SongReaderSectionProjection section(String label) {
        return SongReaderSectionProjection(
          kind: SongSectionKind.verse,
          label: label,
          number: null,
          isUnknown: false,
          lines: [
            for (var index = 0; index < 3; index += 1)
              SongReaderLyricLineProjection(
                segments: const [
                  SongReaderSegmentProjection(
                    displayChord: 'E',
                    text:
                        'This is a very long lyric line that should wrap multiple times in narrow width.',
                  ),
                ],
              ),
          ],
        );
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 760,
              child: SongReaderSectionGrid(
                sections: [section('A'), section('B')],
                viewMode: SongReaderViewMode.chordsAndLyrics,
                sharedFontScale: 1,
                columnCount: 2,
                // The estimator charges a chord row + gap per wrapped run
                // (not once per line) and adds the renderer's run spacing
                // between runs, so the taller column estimates higher than a
                // per-line model would. Re-tuned 2026-08-10 from 420 when
                // word-boundary splitting made a wrapped lyric line taller
                // for real: a line is now one box PER WORD in the outer
                // Wrap, so the renderer's 10px lineRunSpacing applies
                // between the line's own wrapped rows, where before a
                // single-segment line was one Text that wrapped internally
                // at plain text leading. Measured at this fixture's 380px
                // column: 114px -> 144px rendered per line. This value keeps
                // single-column overflowing (so the 2-column path is tried)
                // while staying above the 2-column tolerance threshold for
                // this fixture's now-taller content.
                availableHeight: 540,
              ),
            ),
          ),
        ),
      );

      expect(
        find.byKey(const Key('song-reader-section-grid-columns-2')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'falls back to one column when two-column split would still exceed height',
    (tester) async {
      SongReaderSectionProjection section(String label) {
        return SongReaderSectionProjection(
          kind: SongSectionKind.verse,
          label: label,
          number: null,
          isUnknown: false,
          lines: [
            for (var index = 0; index < 4; index += 1)
              SongReaderLyricLineProjection(
                segments: const [
                  SongReaderSegmentProjection(
                    displayChord: 'E',
                    text:
                        'Very long wrapped lyric line that keeps taking vertical space even in split layout.',
                  ),
                ],
              ),
          ],
        );
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: 760,
                child: SongReaderSectionGrid(
                  sections: [section('A'), section('B')],
                  viewMode: SongReaderViewMode.chordsAndLyrics,
                  sharedFontScale: 1,
                  columnCount: 2,
                  availableHeight: 120,
                ),
              ),
            ),
          ),
        ),
      );

      expect(
        find.byKey(const Key('song-reader-section-grid-columns-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('song-reader-section-grid-columns-2')),
        findsNothing,
      );
    },
  );

  testWidgets('keeps unlabeled prelude as a separate block before verse', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            child: SongReaderSectionGrid(
              sections: [
                SongReaderSectionProjection(
                  kind: SongSectionKind.other,
                  label: 'Unlabeled',
                  number: null,
                  isUnknown: false,
                  lines: [
                    SongReaderLyricLineProjection(
                      segments: const [
                        SongReaderSegmentProjection(
                          displayChord: 'E',
                          text: '',
                        ),
                      ],
                    ),
                  ],
                ),
                SongReaderSectionProjection(
                  kind: SongSectionKind.verse,
                  label: 'Verse',
                  number: 1,
                  isUnknown: false,
                  lines: [
                    SongReaderLyricLineProjection(
                      segments: const [
                        SongReaderSegmentProjection(
                          displayChord: null,
                          text: 'Line',
                        ),
                      ],
                    ),
                  ],
                ),
              ],
              viewMode: SongReaderViewMode.chordsAndLyrics,
              sharedFontScale: 1,
              columnCount: 1,
              availableHeight: 1200,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Unlabeled'), findsNothing);
    expect(find.text('VERSE 1'), findsOneWidget);
    expect(find.text('Verse 1'), findsNothing);
    expect(find.text('E'), findsOneWidget);
    expect(find.text('Line'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('E')).dy,
      lessThan(tester.getTopLeft(find.text('VERSE 1')).dy),
    );
  });

  // The split algorithm uses abs-diff minimisation so both sides are considered.
  // For [A=1, B=1, C=1, D=3, E=3] (total≈9) the most balanced partition is
  // split=3 → [A,B,C] | [D,E]  (diff=3 each way — same as split=4 but found
  // first, so the tie is broken in favour of the earlier / left-leaning split).
  testWidgets('two-column split finds the most balanced partition', (
    tester,
  ) async {
    SongReaderSectionProjection section(String label, int lineCount) {
      return SongReaderSectionProjection(
        kind: SongSectionKind.verse,
        label: label,
        number: null,
        isUnknown: false,
        lines: [
          for (var index = 0; index < lineCount; index += 1)
            SongReaderLyricLineProjection(
              segments: [
                SongReaderSegmentProjection(
                  displayChord: null,
                  text: '$label line $index',
                ),
              ],
            ),
        ],
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            child: SongReaderSectionGrid(
              sections: [
                section('A', 1),
                section('B', 1),
                section('C', 1),
                section('D', 3),
                section('E', 3),
              ],
              viewMode: SongReaderViewMode.chordsAndLyrics,
              sharedFontScale: 1,
              columnCount: 2,
              availableHeight: 420,
            ),
          ),
        ),
      ),
    );

    final aX = tester.getTopLeft(find.text('A')).dx;
    final bX = tester.getTopLeft(find.text('B')).dx;
    final cX = tester.getTopLeft(find.text('C')).dx;
    final dX = tester.getTopLeft(find.text('D')).dx;
    final eX = tester.getTopLeft(find.text('E')).dx;

    // [A, B, C] land in the left column — same x-origin.
    expect((bX - aX).abs(), lessThan(1));
    expect((cX - aX).abs(), lessThan(1));
    // [D, E] land in the right column — larger x than A.
    expect(dX, greaterThan(aX));
    expect((eX - dX).abs(), lessThan(1));
  });

  // ── dominant-section guard ──────────────────────────────────────────────────

  group('dominant section guard', () {
    /// Section with [lineCount] SHORT lyric lines (≤6 chars) and a chord so
    /// they contribute chord+lyric height but do NOT wrap even at half-width.
    /// Short text ensures the dominant-section test isolates the new guard
    /// rather than the existing overflow-tolerance guard.
    SongReaderSectionProjection dominantSection(String label, int lineCount) {
      return SongReaderSectionProjection(
        kind: SongSectionKind.verse,
        label: label,
        number: lineCount == 0 ? null : 1,
        isUnknown: false,
        lines: [
          for (var i = 0; i < lineCount; i++)
            SongReaderLyricLineProjection(
              segments: [
                SongReaderSegmentProjection(
                  displayChord: 'E',
                  // Deliberately short so text never wraps even at half-width
                  // (~36 chars/line at 390px). This lets the tallestColumn
                  // ≈ singleColumnHeight, making the split "useless" rather
                  // than just "overflowing".
                  text: 'Line $i',
                ),
              ],
            ),
        ],
      );
    }

    testWidgets(
      'dominant Verse with empty Intro now splits into TWO columns via mid-section flow',
      (tester) async {
        // Intro (0 lines, header only) + Verse (12 short lines).
        // Old section-atomic guard: forced 1 column (lopsided boundary split).
        // New item-level flow: Verse lines distributed across both columns
        // → balanced split → 2 columns.
        //
        // Re-tuned 2026-08-12: this fixture's single-column height was
        // measured against SongReaderMetrics.legacy's larger row heights and
        // gaps. The 600px type-scale breakpoint's resolved (regular) metrics
        // are considerably tighter (e.g. sectionGap 14 vs. legacy 20,
        // lineGap 6 vs. 10, lineRunSpacing 2 vs. 10), so this content's real
        // single-column height shrank well below the old 700 threshold and
        // no longer overflows it -- the split this test exists to exercise
        // never triggered. Probed empirically: single column fits at
        // availableHeight>=~670-680, splits into two below that. 620 sits
        // comfortably below the new threshold with margin.
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: SizedBox(
                  width: 1280,
                  child: SongReaderSectionGrid(
                    sections: [
                      dominantSection('Intro', 0),
                      dominantSection('Verse', 12),
                    ],
                    viewMode: SongReaderViewMode.chordsAndLyrics,
                    sharedFontScale: 1,
                    columnCount: 2,
                    availableHeight: 620,
                  ),
                ),
              ),
            ),
          ),
        );

        expect(
          find.byKey(const Key('song-reader-section-grid-columns-2')),
          findsOneWidget,
          reason:
              'Mid-section flow splits Verse across both columns → 2 columns',
        );
        expect(
          find.byKey(const Key('song-reader-section-grid-columns-1')),
          findsNothing,
        );
      },
    );

    testWidgets('many balanced sections still use two columns', (tester) async {
      // 6 equal 2-line sections (short text, no wrap):
      //   singleColumnHeight ≈ 6 × 168 = 1008px > 900 → multi-col triggers
      //   tallestColumn (3 sections) ≈ 504px
      //   availableHeight=900 → 504 <= 1035 (tolerance OK) and 504 <= 907 (useful OK)
      //   → columns-2.
      //
      // Re-tuned 2026-08-12: same story as the dominant-section fixture
      // above -- the resolved (regular) 600px-breakpoint metrics are
      // considerably tighter than SongReaderMetrics.legacy, so this
      // fixture's real single-column height (probed empirically:
      // single-column fits at availableHeight>=~850) dropped below the old
      // 900 threshold. 800 sits below the new threshold with margin.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: 1280,
                child: SongReaderSectionGrid(
                  sections: [
                    for (var i = 0; i < 6; i++) dominantSection('Verse', 2),
                  ],
                  viewMode: SongReaderViewMode.chordsAndLyrics,
                  sharedFontScale: 1,
                  columnCount: 2,
                  availableHeight: 800,
                ),
              ),
            ),
          ),
        ),
      );

      expect(
        find.byKey(const Key('song-reader-section-grid-columns-2')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('song-reader-section-grid-columns-1')),
        findsNothing,
      );
    });
  });

  // ── existing tests below ────────────────────────────────────────────────────

  testWidgets('counts the injected capo directive in column height', (
    tester,
  ) async {
    // Re-tuned 2026-08-12: this fixture's total content (a leading directive
    // plus two empty section headers) is smaller and more evenly balanced
    // between the directive block and the two-header block under the
    // resolved (regular) 600px-breakpoint metrics than under
    // SongReaderMetrics.legacy (directive 36+sectionGap vs. legacy's larger
    // sectionGap/headerHeight made the two-column split too lopsided to pass
    // the tolerance/balance guards in resolveFlowLayout; the tighter regular
    // metrics narrow that gap enough that the split now passes at the old
    // availableHeight=70, flipping the result from columns-1 to columns-2).
    // Probed empirically: the flip is between availableHeight=60 (still
    // columns-1) and 70 (columns-2). 50 sits below that threshold with
    // margin, restoring the fallback-to-one-column path this test exists to
    // exercise while still charging the capo directive's own height toward
    // the decision.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 760,
            child: SongReaderSectionGrid(
              leadingDirectiveText: 'Capo 2',
              sections: [
                SongReaderSectionProjection(
                  kind: SongSectionKind.verse,
                  label: 'Verse',
                  number: 1,
                  isUnknown: false,
                  lines: const [],
                ),
                SongReaderSectionProjection(
                  kind: SongSectionKind.chorus,
                  label: 'Chorus',
                  number: 1,
                  isUnknown: false,
                  lines: const [],
                ),
              ],
              viewMode: SongReaderViewMode.chordsAndLyrics,
              sharedFontScale: 1,
              columnCount: 2,
              availableHeight: 50,
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const Key('song-reader-section-grid-columns-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('song-reader-section-grid-columns-2')),
      findsNothing,
    );
  });

  testWidgets('section grid spaces blocks with the reader metrics', (
    tester,
  ) async {
    // Pins the renderer's gaps to the SAME numbers the estimator charges.
    // Before this test the grid hardcoded 12 after a header and 10 after a
    // line, while the estimator carried them inside headerHeight/lineGap:
    // two definitions of one number, which is exactly how estimator drift
    // starts.
    //
    // Re-tuned 2026-08-12: this used to compare against
    // SongReaderMetrics.legacy directly, which happened to equal the
    // resolved metrics before the 600px type-scale breakpoint existed. Now
    // that ReaderTheme.of(context) resolves a breakpoint-dependent metrics
    // set (the default test viewport is >=600px wide, so this renders with
    // the "regular" set: sectionLabelToLineGap=4, lineGap=6 -- both smaller
    // than legacy's 12/10), comparing against the legacy constant is exactly
    // the same "two definitions of one number" drift this test exists to
    // catch. Read the SAME resolved metrics the widget rendered with instead.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SongReaderSectionGrid(
            sections: [
              SongReaderSectionProjection(
                kind: SongSectionKind.verse,
                label: 'Verse',
                number: 1,
                isUnknown: false,
                lines: [
                  SongReaderLyricLineProjection(
                    segments: const [
                      SongReaderSegmentProjection(
                        displayChord: 'C',
                        text: 'hello world',
                      ),
                    ],
                  ),
                ],
              ),
            ],
            viewMode: SongReaderViewMode.chordsAndLyrics,
            sharedFontScale: 1,
            columnCount: 1,
            availableHeight: 800,
          ),
        ),
      ),
    );

    final gaps = tester
        .widgetList<SizedBox>(find.byType(SizedBox))
        .map((box) => box.height)
        .whereType<double>()
        .toSet();

    final metrics = ReaderTheme.of(
      tester.element(find.byType(SongReaderSectionGrid)),
    ).metrics;
    expect(gaps, contains(metrics.sectionLabelToLineGap));
    expect(gaps, contains(metrics.lineGap));
  });
}
