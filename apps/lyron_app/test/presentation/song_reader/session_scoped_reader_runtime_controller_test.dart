import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/presentation/song_reader/session_scoped_reader_runtime_controller.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';

void main() {
  test('starts with the current default reader settings', () {
    final controller = SessionScopedReaderRuntimeController();

    controller.startSession(
      planId: 'plan-1',
      sessionId: 'session-1',
      songId: 'song-1',
    );

    expect(controller.state.readerState, SongReaderState());
    expect(controller.state.planId, 'plan-1');
    expect(controller.state.sessionId, 'session-1');
    expect(controller.state.songId, 'song-1');
  });

  test('updates shared reader state parity controls', () {
    final controller = SessionScopedReaderRuntimeController();
    controller.startSession(
      planId: 'plan-1',
      sessionId: 'session-1',
      songId: 'song-1',
    );

    controller.toggleViewMode();
    controller.transposeUp();
    controller.capoUp();
    controller.setInstrumentDisplayMode(SongReaderInstrumentDisplayMode.piano);
    controller.setSharedFontScale(1.25);
    controller.showCompactControls();
    controller.setControlPresentationMode(
      SongReaderControlPresentationMode.pinned,
    );
    controller.disableAutoFit();

    expect(
      controller.state.readerState.viewMode,
      SongReaderViewMode.lyricsOnly,
    );
    expect(controller.state.readerState.transposeOffset, 1);
    expect(controller.state.readerState.capoOffset, 1);
    expect(
      controller.state.readerState.instrumentDisplayMode,
      SongReaderInstrumentDisplayMode.piano,
    );
    expect(controller.state.readerState.sharedFontScale, 1.25);
    expect(controller.state.readerState.areCompactControlsVisible, true);
    expect(
      controller.state.readerState.controlPresentationMode,
      SongReaderControlPresentationMode.pinned,
    );
    expect(controller.state.readerState.isAutoFitEnabled, false);
  });

  test('keeps scoped capo at zero when decreasing below open capo', () {
    final controller = SessionScopedReaderRuntimeController();
    controller.startSession(
      planId: 'plan-1',
      sessionId: 'session-1',
      songId: 'song-1',
    );

    controller.capoDown();

    expect(controller.state.readerState.capoOffset, -1);
  });

  test('toggles compact controls without disturbing other reader state', () {
    final controller = SessionScopedReaderRuntimeController();
    controller.startSession(
      planId: 'plan-1',
      sessionId: 'session-1',
      songId: 'song-1',
    );

    controller.toggleCompactControls();
    expect(controller.state.readerState.areCompactControlsVisible, true);

    controller.toggleCompactControls();
    expect(controller.state.readerState.areCompactControlsVisible, false);
    expect(controller.state.readerState, SongReaderState());
  });

  test('preserves settings when selected song changes in the same session', () {
    final controller = SessionScopedReaderRuntimeController();
    controller.startSession(
      planId: 'plan-1',
      sessionId: 'session-1',
      songId: 'song-1',
    );
    controller.toggleViewMode();
    controller.transposeUp();
    controller.capoUp();
    controller.setSharedFontScale(1.25);
    controller.showCompactControls();
    controller.disableAutoFit();

    controller.startSession(
      planId: 'plan-1',
      sessionId: 'session-1',
      songId: 'song-2',
    );

    expect(controller.state.songId, 'song-2');
    expect(
      controller.state.readerState.viewMode,
      SongReaderViewMode.lyricsOnly,
    );
    expect(controller.state.readerState.transposeOffset, 1);
    expect(controller.state.readerState.capoOffset, 1);
    expect(controller.state.readerState.sharedFontScale, 1.25);
    expect(controller.state.readerState.areCompactControlsVisible, true);
    expect(controller.state.readerState.isAutoFitEnabled, false);
  });

  test('resets when a different scoped reader session starts', () {
    final controller = SessionScopedReaderRuntimeController();
    controller.startSession(
      planId: 'plan-1',
      sessionId: 'session-1',
      songId: 'song-1',
    );
    controller.toggleViewMode();
    controller.transposeUp();
    controller.setSharedFontScale(1.25);

    controller.startSession(
      planId: 'plan-2',
      sessionId: 'session-9',
      songId: 'song-99',
    );

    expect(controller.state.planId, 'plan-2');
    expect(controller.state.sessionId, 'session-9');
    expect(controller.state.songId, 'song-99');
    expect(controller.state.readerState, SongReaderState());
  });
}
