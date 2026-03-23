import 'package:flutter_test/flutter_test.dart';
import 'package:lyrica_app/src/presentation/song_reader/song_reader_controller.dart';
import 'package:lyrica_app/src/presentation/song_reader/song_reader_state.dart';

void main() {
  test('defaults to chords plus lyrics mode with neutral controls', () {
    final controller = SongReaderController();

    expect(controller.state.viewMode, SongReaderViewMode.chordsAndLyrics);
    expect(controller.state.transposeOffset, 0);
    expect(controller.state.sharedFontScale, 1.0);
  });

  test('toggles to lyrics only and back', () {
    final controller = SongReaderController();

    controller.toggleViewMode();

    expect(controller.state.viewMode, SongReaderViewMode.lyricsOnly);

    controller.toggleViewMode();

    expect(controller.state.viewMode, SongReaderViewMode.chordsAndLyrics);
  });

  test('adjusts transpose up and down', () {
    final controller = SongReaderController();

    controller.transposeUp();
    controller.transposeUp();
    controller.transposeDown();

    expect(controller.state.transposeOffset, 1);
  });

  test('updates shared font scale', () {
    final controller = SongReaderController();

    controller.setSharedFontScale(1.25);

    expect(controller.state.sharedFontScale, 1.25);
  });
}
