import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/domain/song/parsed_song.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_control_bar.dart';

ParsedSong _song({int baseCapo = 2}) {
  return ParsedSong(
    title: 'Song',
    sourceKey: 'G',
    baseTranspose: 2,
    baseCapo: baseCapo,
    sections: const [],
    diagnostics: const [],
  );
}

Widget _host(SongReaderControlBar bar) =>
    MaterialApp(home: Scaffold(body: bar));

void main() {
  testWidgets('renders transpose, capo and font controls in guitar mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        SongReaderControlBar(
          projection: SongReaderProjection(
            song: _song(),
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
    );

    expect(find.byKey(const Key('song-reader-transpose-down')), findsOneWidget);
    expect(
      find.byKey(const Key('song-reader-transpose-value')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('song-reader-transpose-up')), findsOneWidget);
    expect(find.byKey(const Key('song-reader-capo-down')), findsOneWidget);
    expect(find.byKey(const Key('song-reader-capo-value')), findsOneWidget);
    expect(find.byKey(const Key('song-reader-capo-up')), findsOneWidget);
    expect(find.byKey(const Key('song-reader-font-decrease')), findsOneWidget);
    expect(find.byKey(const Key('song-reader-font-increase')), findsOneWidget);
  });

  testWidgets('hides the capo group in piano mode', (tester) async {
    await tester.pumpWidget(
      _host(
        SongReaderControlBar(
          projection: SongReaderProjection(
            song: _song(),
            state: SongReaderState(
              instrumentDisplayMode: SongReaderInstrumentDisplayMode.piano,
            ),
          ),
          onTransposeDown: () {},
          onTransposeUp: () {},
          onDecreaseFontScale: () {},
          onIncreaseFontScale: () {},
        ),
      ),
    );

    expect(find.byKey(const Key('song-reader-capo-down')), findsNothing);
    expect(find.byKey(const Key('song-reader-transpose-up')), findsOneWidget);
  });

  testWidgets('disables capo-down when onCapoDown is null', (tester) async {
    await tester.pumpWidget(
      _host(
        SongReaderControlBar(
          projection: SongReaderProjection(
            song: _song(baseCapo: 0),
            state: SongReaderState(),
          ),
          onTransposeDown: () {},
          onTransposeUp: () {},
          onCapoDown: null,
          onCapoUp: () {},
          onDecreaseFontScale: () {},
          onIncreaseFontScale: () {},
        ),
      ),
    );

    final button = tester.widget<IconButton>(
      find.byKey(const Key('song-reader-capo-down')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('invokes callbacks on tap', (tester) async {
    var transposeUp = 0;
    var fontUp = 0;
    await tester.pumpWidget(
      _host(
        SongReaderControlBar(
          projection: SongReaderProjection(
            song: _song(),
            state: SongReaderState(),
          ),
          onTransposeDown: () {},
          onTransposeUp: () => transposeUp += 1,
          onCapoDown: () {},
          onCapoUp: () {},
          onDecreaseFontScale: () {},
          onIncreaseFontScale: () => fontUp += 1,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('song-reader-transpose-up')));
    await tester.tap(find.byKey(const Key('song-reader-font-increase')));
    expect(transposeUp, 1);
    expect(fontUp, 1);
  });
}
