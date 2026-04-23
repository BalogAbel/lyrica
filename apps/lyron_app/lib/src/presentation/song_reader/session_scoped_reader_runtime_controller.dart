import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/presentation/song_reader/session_scoped_reader_runtime_state.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';

class SessionScopedReaderRuntimeController extends ChangeNotifier {
  SessionScopedReaderRuntimeState _state = SessionScopedReaderRuntimeState();

  SessionScopedReaderRuntimeState get state => _state;

  void _updateReaderState(
    SongReaderState Function(SongReaderState state) update,
  ) {
    _state = _state.copyWith(readerState: update(_state.readerState));
    notifyListeners();
  }

  void startSession({
    required String planId,
    required String sessionId,
    required String songId,
  }) {
    final isSameSession =
        _state.planId == planId && _state.sessionId == sessionId;

    _state = SessionScopedReaderRuntimeState(
      planId: planId,
      sessionId: sessionId,
      songId: songId,
      readerState: isSameSession ? _state.readerState : SongReaderState(),
    );
    notifyListeners();
  }

  void toggleViewMode() {
    _updateReaderState(
      (state) => state.copyWith(
        viewMode: state.viewMode == SongReaderViewMode.chordsAndLyrics
            ? SongReaderViewMode.lyricsOnly
            : SongReaderViewMode.chordsAndLyrics,
      ),
    );
  }

  void transposeUp() {
    _updateReaderState(
      (state) => state.copyWith(transposeOffset: state.transposeOffset + 1),
    );
  }

  void transposeDown() {
    _updateReaderState(
      (state) => state.copyWith(transposeOffset: state.transposeOffset - 1),
    );
  }

  void capoUp() {
    _updateReaderState(
      (state) => state.copyWith(capoOffset: state.capoOffset + 1),
    );
  }

  void capoDown() {
    _updateReaderState(
      (state) => state.copyWith(capoOffset: state.capoOffset - 1),
    );
  }

  void setInstrumentDisplayMode(SongReaderInstrumentDisplayMode mode) {
    _updateReaderState((state) => state.copyWith(instrumentDisplayMode: mode));
  }

  void setSharedFontScale(double scale) {
    _updateReaderState((state) => state.copyWith(sharedFontScale: scale));
  }

  void showCompactControls() {
    _updateReaderState(
      (state) => state.copyWith(areCompactControlsVisible: true),
    );
  }

  void hideCompactControls() {
    _updateReaderState(
      (state) => state.copyWith(areCompactControlsVisible: false),
    );
  }

  void toggleCompactControls() {
    _updateReaderState(
      (state) => state.copyWith(
        areCompactControlsVisible: !state.areCompactControlsVisible,
      ),
    );
  }

  void setControlPresentationMode(SongReaderControlPresentationMode mode) {
    _updateReaderState(
      (state) => state.copyWith(controlPresentationMode: mode),
    );
  }

  void enableAutoFit() {
    _updateReaderState((state) => state.copyWith(isAutoFitEnabled: true));
  }

  void disableAutoFit() {
    _updateReaderState((state) => state.copyWith(isAutoFitEnabled: false));
  }

  void toggleAutoFit() {
    _updateReaderState(
      (state) => state.copyWith(isAutoFitEnabled: !state.isAutoFitEnabled),
    );
  }
}

final sessionScopedReaderRuntimeControllerProvider =
    ChangeNotifierProvider.family<SessionScopedReaderRuntimeController, String>(
      (ref, sessionKey) {
        return SessionScopedReaderRuntimeController();
      },
    );
