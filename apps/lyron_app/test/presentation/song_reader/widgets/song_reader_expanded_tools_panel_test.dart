import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/app/app_theme.dart';
import 'package:lyron_app/src/domain/song/parsed_song.dart';
import 'package:lyron_app/src/domain/song/song_key_layers.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_expanded_context_panel.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_expanded_tools_panel.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

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

  group('key source badges', () {
    Widget host({
      required SongKeyLayerId transposeSource,
      required SongKeyLayerId capoSource,
      ThemeData? theme,
    }) {
      return MaterialApp(
        theme: theme,
        home: Scaffold(
          body: SongReaderExpandedToolsPanel(
            projection: SongReaderProjection(
              song: _buildSong(),
              state: SongReaderState(),
              key: ResolvedSongKey(
                transpose: ResolvedSongKeyField(
                  value: 2,
                  source: transposeSource,
                ),
                capo: ResolvedSongKeyField(value: 2, source: capoSource),
              ),
            ),
            onTransposeDown: () {},
            onTransposeUp: () {},
            onCapoDown: () {},
            onCapoUp: () {},
            onDecreaseFontScale: () {},
            onIncreaseFontScale: () {},
          ),
        ),
      );
    }

    testWidgets('each badge is in the row of its section label, after it', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          transposeSource: SongKeyLayerId.temporary,
          capoSource: SongKeyLayerId.plan,
        ),
      );

      final pairs = {
        AppStrings.songReaderTransposeSectionLabel: (
          'song-reader-transpose-source',
          'Temporary',
        ),
        AppStrings.songReaderCapoSectionLabel: (
          'song-reader-capo-source',
          'Plan',
        ),
      };
      for (final MapEntry(key: label, value: (badgeKey, word))
          in pairs.entries) {
        final badge = find.byKey(Key(badgeKey));
        expect(tester.widget<Text>(badge).data, word);
        expect(
          tester.getCenter(badge).dy,
          tester.getCenter(find.text(label)).dy,
          reason: '$label badge shares the label row',
        );
        expect(
          tester.getCenter(badge).dx,
          greaterThan(tester.getCenter(find.text(label)).dx),
          reason: '$label badge follows the label',
        );
      }
    });

    testWidgets('the badge and the value chip take the source colors', (
      tester,
    ) async {
      final theme = buildLightTheme();
      await tester.pumpWidget(
        host(
          transposeSource: SongKeyLayerId.temporary,
          capoSource: SongKeyLayerId.plan,
          theme: theme,
        ),
      );

      Color? fillBehind(Finder inner) =>
          (tester
                      .widget<DecoratedBox>(
                        find
                            .ancestor(
                              of: inner,
                              matching: find.byType(DecoratedBox),
                            )
                            .first,
                      )
                      .decoration
                  as BoxDecoration)
              .color;
      Color? chipFill(String key) =>
          (tester
                      .widget<DecoratedBox>(
                        find.descendant(
                          of: find.byKey(Key(key)),
                          matching: find.byType(DecoratedBox),
                        ),
                      )
                      .decoration
                  as BoxDecoration)
              .color;

      expect(
        fillBehind(find.byKey(const Key('song-reader-transpose-source'))),
        theme.colorScheme.tertiaryContainer,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('song-reader-transpose-source')))
            .style
            ?.color,
        theme.colorScheme.onTertiaryContainer,
      );
      expect(
        fillBehind(find.byKey(const Key('song-reader-capo-source'))),
        theme.colorScheme.primaryContainer,
      );
      expect(
        chipFill('song-reader-transpose-value'),
        theme.colorScheme.tertiaryContainer,
      );
      expect(
        chipFill('song-reader-capo-value'),
        theme.colorScheme.primaryContainer,
      );
    });
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
