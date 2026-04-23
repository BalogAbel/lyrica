import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/domain/song/parsed_song.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_compact_overlay.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_expanded_context_panel.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_expanded_tools_panel.dart';

void main() {
  testWidgets('renders the reader actions when visible', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SongReaderCompactOverlay(
            isVisible: true,
            projection: SongReaderProjection(
              song: _buildSong(),
              state: SongReaderState(),
            ),
            hasRecoverableWarnings: true,
            warningCount: 2,
            onToggleViewMode: () {},
            onTransposeDown: () {},
            onTransposeUp: () {},
            onCapoDown: () {},
            onCapoUp: () {},
            onDecreaseFontScale: () {},
            onIncreaseFontScale: () {},
          ),
        ),
      ),
    );

    expect(find.text('Lyrics only'), findsOneWidget);
    expect(find.text('Transpose: +2'), findsOneWidget);
    expect(find.byKey(const Key('song-reader-transpose-down')), findsOneWidget);
    expect(find.byKey(const Key('song-reader-transpose-up')), findsOneWidget);
    expect(find.text('Capo: 2'), findsOneWidget);
    expect(find.byKey(const Key('song-reader-capo-down')), findsOneWidget);
    expect(find.byKey(const Key('song-reader-capo-up')), findsOneWidget);
    expect(find.text('A-'), findsOneWidget);
    expect(find.text('A+'), findsOneWidget);
    expect(find.text('Reader Song'), findsNothing);
  });

  testWidgets('shows capo zero as disabled but visible', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SongReaderCompactOverlay(
            isVisible: true,
            projection: SongReaderProjection(
              song: _buildSong(baseCapo: 0),
              state: SongReaderState(),
            ),
            hasRecoverableWarnings: false,
            warningCount: 0,
            onToggleViewMode: () {},
            onTransposeDown: () {},
            onTransposeUp: () {},
            onCapoDown: null,
            onCapoUp: () {},
            onDecreaseFontScale: () {},
            onIncreaseFontScale: () {},
          ),
        ),
      ),
    );

    expect(find.text('Capo: 0'), findsOneWidget);
    expect(find.byKey(const Key('song-reader-capo-down')), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('song-reader-capo-down')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('does not render actions when hidden', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SongReaderCompactOverlay(
            isVisible: false,
            projection: SongReaderProjection(
              song: _buildSong(),
              state: SongReaderState(),
            ),
            hasRecoverableWarnings: false,
            warningCount: 0,
            onToggleViewMode: () {},
            onTransposeDown: () {},
            onTransposeUp: () {},
            onCapoDown: () {},
            onCapoUp: () {},
            onDecreaseFontScale: () {},
            onIncreaseFontScale: () {},
          ),
        ),
      ),
    );

    expect(find.text('Lyrics only'), findsNothing);
    expect(find.byKey(const Key('song-reader-transpose-up')), findsNothing);
  });

  testWidgets('expanded panels render without the whole screen', (
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
                  hasRecoverableWarnings: false,
                  warningCount: 0,
                  onToggleViewMode: () {},
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
    expect(find.text('Lyrics only'), findsOneWidget);
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
          SongLine(
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
