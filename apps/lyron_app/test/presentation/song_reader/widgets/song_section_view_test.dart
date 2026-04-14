import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/domain/song/parsed_song.dart';
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
}
