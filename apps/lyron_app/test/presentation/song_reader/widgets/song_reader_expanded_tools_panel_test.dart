import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/domain/song/parsed_song.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_expanded_context_panel.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_expanded_tools_panel.dart';

void main() {
  testWidgets('expanded panels render transpose/capo/font controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              const Expanded(
                child: SongReaderExpandedContextPanel(
                  previousTitle: 'Before',
                  nextTitle: 'After',
                ),
              ),
              Expanded(
                child: SongReaderExpandedToolsPanel(
                  projection: SongReaderProjection(
                    song: _buildSong(),
                    state: SongReaderState(),
                  ),
                  onTransposeDown: () {},
                  onTransposeUp: () {},
                  onCapoDown: () {},
                  onCapoUp: () {},
                  onDecreaseFontScale: () {},
                  onIncreaseFontScale: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Before'), findsOneWidget);
    expect(find.text('After'), findsOneWidget);
    expect(find.byKey(const Key('song-reader-transpose-up')), findsOneWidget);
  });
}

ParsedSong _buildSong({int baseCapo = 2}) {
  return ParsedSong(
    title: 'Reader Song',
    sourceKey: 'G',
    baseTranspose: 2,
    baseCapo: baseCapo,
    sections: [
      SongSection(
        kind: SongSectionKind.verse,
        label: 'Verse',
        lines: [
          LyricLine(
            segments: const [
              LyricSegment(leadingChord: 'G', text: 'Hello world'),
            ],
          ),
        ],
      ),
    ],
    diagnostics: const [],
  );
}
