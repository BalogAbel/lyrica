import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyrica_app/src/presentation/song_reader/session_scoped_reader_runtime_state.dart';
import 'package:lyrica_app/src/presentation/song_reader/song_reader_state.dart';

class SessionScopedReaderRuntimeController extends ChangeNotifier {
  SessionScopedReaderRuntimeState _state = SessionScopedReaderRuntimeState();

  SessionScopedReaderRuntimeState get state => _state;

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
    _state = _state.copyWith(
      readerState: _state.readerState.copyWith(
        viewMode:
            _state.readerState.viewMode == SongReaderViewMode.chordsAndLyrics
            ? SongReaderViewMode.lyricsOnly
            : SongReaderViewMode.chordsAndLyrics,
      ),
    );
    notifyListeners();
  }

  void transposeUp() {
    _state = _state.copyWith(
      readerState: _state.readerState.copyWith(
        transposeOffset: _state.readerState.transposeOffset + 1,
      ),
    );
    notifyListeners();
  }

  void transposeDown() {
    _state = _state.copyWith(
      readerState: _state.readerState.copyWith(
        transposeOffset: _state.readerState.transposeOffset - 1,
      ),
    );
    notifyListeners();
  }

  void setSharedFontScale(double scale) {
    _state = _state.copyWith(
      readerState: _state.readerState.copyWith(sharedFontScale: scale),
    );
    notifyListeners();
  }
}

final sessionScopedReaderRuntimeControllerProvider =
    ChangeNotifierProvider.family<SessionScopedReaderRuntimeController, String>(
      (ref, sessionKey) {
        return SessionScopedReaderRuntimeController();
      },
    );
