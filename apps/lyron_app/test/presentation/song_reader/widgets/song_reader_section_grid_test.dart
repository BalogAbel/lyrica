import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

    final a = tester.getTopLeft(find.text('Section A'));
    final b = tester.getTopLeft(find.text('Section B'));
    final c = tester.getTopLeft(find.text('Section C'));

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
                availableHeight: 340,
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
    expect(find.text('Verse 1'), findsOneWidget);
    expect(find.text('E'), findsOneWidget);
    expect(find.text('Line'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('E')).dy,
      lessThan(tester.getTopLeft(find.text('Verse 1')).dy),
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
                    availableHeight: 700,
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
                  availableHeight: 900,
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
              availableHeight: 70,
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
}
