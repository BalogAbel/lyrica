import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/domain/song/parsed_song.dart';
import 'package:lyron_app/src/infrastructure/song_library/chordpro/chordpro_parser.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_section_view.dart';

void main() {
  testWidgets('hides section header for unlabeled sections', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SongSectionView(
            section: SongReaderSectionProjection(
              kind: SongSectionKind.other,
              label: 'Unlabeled',
              number: null,
              lines: [
                SongReaderLineProjection(
                  segments: const [
                    SongReaderSegmentProjection(
                      displayChord: 'E',
                      text: 'Line',
                    ),
                  ],
                ),
              ],
            ),
            viewMode: SongReaderViewMode.chordsAndLyrics,
            sharedFontScale: 1,
          ),
        ),
      ),
    );

    expect(find.text('Unlabeled'), findsNothing);
    expect(find.text('Line'), findsOneWidget);
    expect(find.text('E'), findsOneWidget);
  });

  testWidgets('shows section header when section has a concrete label', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SongSectionView(
            section: SongReaderSectionProjection(
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
            viewMode: SongReaderViewMode.chordsAndLyrics,
            sharedFontScale: 1,
          ),
        ),
      ),
    );

    expect(find.text('Verse 1'), findsOneWidget);
  });

  testWidgets('renders the real intro section without chord overlap', (
    tester,
  ) async {
    final parser = ChordproParser();
    final song = parser.parse(
      File('assets/songs/a_forrasnal.pro').readAsStringSync(),
    );
    final intro = song.sections.firstWhere(
      (section) => section.label == 'Intro',
    );

    await tester.binding.setSurfaceSize(const Size(440, 180));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: ColoredBox(
              color: const Color(0xFFF7F4EA),
              child: SizedBox(
                width: 400,
                child: SongSectionView(
                  section: SongReaderSectionProjection(
                    kind: intro.kind,
                    label: intro.label,
                    number: intro.number,
                    lines: intro.lines
                        .map(
                          (line) => SongReaderLineProjection(
                            segments: line.segments
                                .map(
                                  (segment) => SongReaderSegmentProjection(
                                    displayChord: segment.leadingChord,
                                    text: segment.text,
                                  ),
                                )
                                .toList(growable: false),
                          ),
                        )
                        .toList(growable: false),
                  ),
                  viewMode: SongReaderViewMode.chordsAndLyrics,
                  sharedFontScale: 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Intro'), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
    expect(find.text('F#m'), findsOneWidget);
    expect(find.text('C#m/G#'), findsNWidgets(2));

    final introChordRects = [
      tester.getRect(find.text('A')),
      tester.getRect(find.text('C#m/G#').at(0)),
      tester.getRect(find.text('F#m')),
      tester.getRect(find.text('C#m/G#').at(1)),
    ];

    for (var index = 0; index < introChordRects.length - 1; index += 1) {
      expect(
        introChordRects[index].overlaps(introChordRects[index + 1]),
        isFalse,
      );
    }
  });
}
