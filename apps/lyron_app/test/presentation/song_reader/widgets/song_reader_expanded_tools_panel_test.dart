import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/app/app_theme.dart';
import 'package:lyron_app/src/domain/song/parsed_song.dart';
import 'package:lyron_app/src/domain/song/song_key_layers.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_key_actions.dart';
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

  group('key actions', () {
    const resetKey = Key('song-reader-key-reset');
    const saveKey = Key('song-reader-key-save-to-plan');

    Widget host(
      SongReaderKeyActions keyActions, {
      SongReaderInstrumentDisplayMode mode =
          SongReaderInstrumentDisplayMode.guitar,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SongReaderExpandedToolsPanel(
              projection: SongReaderProjection(
                song: _buildSong(),
                state: SongReaderState(instrumentDisplayMode: mode),
              ),
              onTransposeDown: () {},
              onTransposeUp: () {},
              onCapoDown: () {},
              onCapoUp: () {},
              onDecreaseFontScale: () {},
              onIncreaseFontScale: () {},
              keyActions: keyActions,
            ),
          ),
        ),
      );
    }

    double centerY(WidgetTester tester, Finder finder) =>
        tester.getCenter(finder).dy;

    testWidgets('without actions Reset is there and disabled, Save to plan '
        'is not there', (tester) async {
      await tester.pumpWidget(host(SongReaderKeyActions.none));

      expect(find.byKey(resetKey), findsOneWidget);
      expect(tester.widget<TextButton>(find.byKey(resetKey)).onPressed, isNull);
      expect(find.text(AppStrings.songReaderResetKeyAction), findsOneWidget);
      expect(find.byKey(saveKey), findsNothing);
      expect(find.text(AppStrings.songReaderSaveToPlanAction), findsNothing);
    });

    testWidgets('the button row is under the capo section and above Scale', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(const SongReaderKeyActions(isSaveToPlanAvailable: true)),
      );

      expect(find.byKey(saveKey), findsOneWidget);
      expect(find.text(AppStrings.songReaderSaveToPlanAction), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byKey(saveKey)).onPressed,
        isNull,
      );
      final scale = find.text(AppStrings.songReaderScaleSectionLabel);
      for (final key in [resetKey, saveKey]) {
        expect(
          centerY(tester, find.byKey(const Key('song-reader-capo-up'))),
          lessThan(centerY(tester, find.byKey(key))),
        );
        expect(
          centerY(tester, find.byKey(key)),
          lessThan(centerY(tester, scale)),
        );
      }
    });

    testWidgets('without the capo section the row follows transpose', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const SongReaderKeyActions(isSaveToPlanAvailable: true),
          mode: SongReaderInstrumentDisplayMode.piano,
        ),
      );

      expect(
        centerY(tester, find.byKey(const Key('song-reader-transpose-up'))),
        lessThan(centerY(tester, find.byKey(resetKey))),
      );
      expect(
        centerY(tester, find.byKey(saveKey)),
        lessThan(
          centerY(tester, find.text(AppStrings.songReaderScaleSectionLabel)),
        ),
      );
    });

    testWidgets('the callbacks run on tap', (tester) async {
      var resets = 0;
      var saves = 0;
      await tester.pumpWidget(
        host(
          SongReaderKeyActions(
            isSaveToPlanAvailable: true,
            onReset: () => resets += 1,
            onSaveToPlan: () => saves += 1,
          ),
        ),
      );

      await tester.tap(find.byKey(resetKey));
      await tester.tap(find.byKey(saveKey));

      expect(resets, 1);
      expect(saves, 1);
    });
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
