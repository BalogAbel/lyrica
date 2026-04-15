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
                  lines: [],
                ),
                SongReaderSectionProjection(
                  kind: SongSectionKind.verse,
                  label: 'Section B',
                  number: null,
                  lines: [],
                ),
                SongReaderSectionProjection(
                  kind: SongSectionKind.verse,
                  label: 'Section C',
                  number: null,
                  lines: [],
                ),
                SongReaderSectionProjection(
                  kind: SongSectionKind.verse,
                  label: 'Section D',
                  number: null,
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
                    lines: [],
                  ),
                  SongReaderSectionProjection(
                    kind: SongSectionKind.verse,
                    label: 'Section B',
                    number: null,
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
          lines: [
            for (var index = 0; index < 3; index += 1)
              SongReaderLineProjection(
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
          lines: [
            for (var index = 0; index < 4; index += 1)
              SongReaderLineProjection(
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
                  lines: [
                    SongReaderLineProjection(
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
                  lines: [
                    SongReaderLineProjection(
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

  testWidgets('two-column split keeps heavier side on the first column', (
    tester,
  ) async {
    SongReaderSectionProjection section(String label, int lineCount) {
      return SongReaderSectionProjection(
        kind: SongSectionKind.verse,
        label: label,
        number: null,
        lines: [
          for (var index = 0; index < lineCount; index += 1)
            SongReaderLineProjection(
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

    expect((bX - aX).abs(), lessThan(1));
    expect((cX - aX).abs(), lessThan(1));
    expect((dX - aX).abs(), lessThan(1));
    expect(eX, greaterThan(aX));
  });
}
