import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/presentation/song_reader/session_scoped_reader_runtime_controller.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';

const _layer = SongReaderTemporaryLayer(
  ownerId: 'item-1@0',
  transpose: 1,
  capo: 1,
);

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
    controller.setTemporaryLayer(_layer);
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
    expect(controller.state.readerState.temporaryLayer, _layer);
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

  test('sets and clears the temporary key layer', () {
    final controller = SessionScopedReaderRuntimeController();
    controller.startSession(
      planId: 'plan-1',
      sessionId: 'session-1',
      songId: 'song-1',
    );

    controller.setTemporaryLayer(_layer);
    expect(controller.state.readerState.temporaryLayer, _layer);

    controller.setTemporaryLayer(null);
    expect(controller.state.readerState.temporaryLayer, isNull);
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

  test('preserves settings but drops the temporary key when the selected '
      'song changes in the same session', () {
    final controller = SessionScopedReaderRuntimeController();
    controller.startSession(
      planId: 'plan-1',
      sessionId: 'session-1',
      songId: 'song-1',
    );
    controller.toggleViewMode();
    controller.setInstrumentDisplayMode(SongReaderInstrumentDisplayMode.piano);
    controller.setTemporaryLayer(_layer);
    controller.setSharedFontScale(1.4);
    controller.showCompactControls();
    controller.disableAutoFit();
    final before = controller.state.readerState;

    controller.startSession(
      planId: 'plan-1',
      sessionId: 'session-1',
      songId: 'song-2',
    );

    expect(controller.state.songId, 'song-2');
    expect(controller.state.readerState.temporaryLayer, isNull);
    expect(controller.state.readerState, before.withTemporaryLayer(null));
    expect(
      controller.state.readerState.viewMode,
      SongReaderViewMode.lyricsOnly,
    );
    expect(
      controller.state.readerState.instrumentDisplayMode,
      SongReaderInstrumentDisplayMode.piano,
    );
    expect(controller.state.readerState.sharedFontScale, 1.4);
    expect(controller.state.readerState.areCompactControlsVisible, true);
    expect(controller.state.readerState.isAutoFitEnabled, false);
  });

  test('drops the temporary key when the same song starts again', () {
    final controller = SessionScopedReaderRuntimeController();
    controller.startSession(
      planId: 'plan-1',
      sessionId: 'session-1',
      songId: 'song-1',
    );
    controller.setTemporaryLayer(_layer);
    controller.setSharedFontScale(1.25);

    controller.startSession(
      planId: 'plan-1',
      sessionId: 'session-1',
      songId: 'song-1',
    );

    expect(controller.state.readerState.temporaryLayer, isNull);
    expect(controller.state.readerState.sharedFontScale, 1.25);
  });

  test('resets when a different scoped reader session starts', () {
    final controller = SessionScopedReaderRuntimeController();
    controller.startSession(
      planId: 'plan-1',
      sessionId: 'session-1',
      songId: 'song-1',
    );
    controller.toggleViewMode();
    controller.setTemporaryLayer(_layer);
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
