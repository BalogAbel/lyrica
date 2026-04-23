import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_controller.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';

void main() {
  test('defaults to chords plus lyrics mode with neutral controls', () {
    final controller = SongReaderController();

    expect(controller.state.viewMode, SongReaderViewMode.chordsAndLyrics);
    expect(controller.state.transposeOffset, 0);
    expect(controller.state.capoOffset, 0);
    expect(
      controller.state.instrumentDisplayMode,
      SongReaderInstrumentDisplayMode.guitar,
    );
    expect(controller.state.sharedFontScale, 1.0);
    expect(controller.state.areCompactControlsVisible, false);
    expect(
      controller.state.controlPresentationMode,
      SongReaderControlPresentationMode.overlay,
    );
    expect(controller.state.isAutoFitEnabled, true);
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

  test('adjusts capo up and down', () {
    final controller = SongReaderController();

    controller.capoUp();
    controller.capoUp();
    controller.capoDown();

    expect(controller.state.capoOffset, 1);
  });

  test('keeps capo at zero when decreasing below open capo', () {
    final controller = SongReaderController();

    controller.capoDown();

    expect(controller.state.capoOffset, -1);
  });

  test('switches instrument display mode', () {
    final controller = SongReaderController();

    controller.setInstrumentDisplayMode(SongReaderInstrumentDisplayMode.piano);

    expect(
      controller.state.instrumentDisplayMode,
      SongReaderInstrumentDisplayMode.piano,
    );
  });

  test('updates shared font scale', () {
    final controller = SongReaderController();

    controller.setSharedFontScale(1.25);

    expect(controller.state.sharedFontScale, 1.25);
  });

  test('normalizes invalid shared font scale through the controller', () {
    final controller = SongReaderController();

    controller.setSharedFontScale(double.nan);

    expect(controller.state.sharedFontScale, 1.0);
  });

  test('shows, hides, and toggles compact controls', () {
    final controller = SongReaderController();

    controller.showCompactControls();
    expect(controller.state.areCompactControlsVisible, true);

    controller.hideCompactControls();
    expect(controller.state.areCompactControlsVisible, false);

    controller.toggleCompactControls();
    expect(controller.state.areCompactControlsVisible, true);

    controller.toggleCompactControls();
    expect(controller.state.areCompactControlsVisible, false);
  });

  test('updates compact control presentation mode', () {
    final controller = SongReaderController();

    controller.setControlPresentationMode(
      SongReaderControlPresentationMode.pinned,
    );

    expect(
      controller.state.controlPresentationMode,
      SongReaderControlPresentationMode.pinned,
    );
  });

  test('enables and disables auto-fit', () {
    final controller = SongReaderController();

    controller.disableAutoFit();
    expect(controller.state.isAutoFitEnabled, false);

    controller.enableAutoFit();
    expect(controller.state.isAutoFitEnabled, true);
  });

  test('normalizes invalid shared font scales', () {
    expect(SongReaderState(sharedFontScale: 0).sharedFontScale, 1.0);
    expect(SongReaderState(sharedFontScale: -2).sharedFontScale, 1.0);
    expect(SongReaderState(sharedFontScale: double.nan).sharedFontScale, 1.0);
    expect(
      SongReaderState(sharedFontScale: double.infinity).sharedFontScale,
      1.0,
    );
    expect(SongReaderState(sharedFontScale: 0.25).sharedFontScale, 0.5);
    expect(SongReaderState(sharedFontScale: 4.0).sharedFontScale, 2.0);
  });

  test('preserves UI state through copyWith', () {
    final state = SongReaderState(
      instrumentDisplayMode: SongReaderInstrumentDisplayMode.piano,
      capoOffset: 2,
      areCompactControlsVisible: true,
      controlPresentationMode: SongReaderControlPresentationMode.pinned,
      isAutoFitEnabled: false,
    );

    expect(
      state.copyWith(sharedFontScale: double.nan),
      SongReaderState(
        instrumentDisplayMode: SongReaderInstrumentDisplayMode.piano,
        capoOffset: 2,
        areCompactControlsVisible: true,
        controlPresentationMode: SongReaderControlPresentationMode.pinned,
        isAutoFitEnabled: false,
      ),
    );
  });
}
