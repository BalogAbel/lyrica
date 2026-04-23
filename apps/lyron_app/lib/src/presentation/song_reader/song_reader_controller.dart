import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';

class SongReaderController {
  SongReaderController({SongReaderState? initialState})
    : _state = initialState ?? SongReaderState();

  SongReaderState _state;

  SongReaderState get state => _state;

  void toggleViewMode() {
    _state = _state.copyWith(
      viewMode: _state.viewMode == SongReaderViewMode.chordsAndLyrics
          ? SongReaderViewMode.lyricsOnly
          : SongReaderViewMode.chordsAndLyrics,
    );
  }

  void transposeUp() {
    _state = _state.copyWith(transposeOffset: _state.transposeOffset + 1);
  }

  void transposeDown() {
    _state = _state.copyWith(transposeOffset: _state.transposeOffset - 1);
  }

  void capoUp() {
    _state = _state.copyWith(capoOffset: _state.capoOffset + 1);
  }

  void capoDown() {
    _state = _state.copyWith(capoOffset: _state.capoOffset - 1);
  }

  void setInstrumentDisplayMode(SongReaderInstrumentDisplayMode mode) {
    _state = _state.copyWith(instrumentDisplayMode: mode);
  }

  void setSharedFontScale(double scale) {
    _state = _state.copyWith(sharedFontScale: scale);
  }

  void showCompactControls() {
    _state = _state.copyWith(areCompactControlsVisible: true);
  }

  void hideCompactControls() {
    _state = _state.copyWith(areCompactControlsVisible: false);
  }

  void toggleCompactControls() {
    _state = _state.copyWith(
      areCompactControlsVisible: !_state.areCompactControlsVisible,
    );
  }

  void setControlPresentationMode(SongReaderControlPresentationMode mode) {
    _state = _state.copyWith(controlPresentationMode: mode);
  }

  void enableAutoFit() {
    _state = _state.copyWith(isAutoFitEnabled: true);
  }

  void disableAutoFit() {
    _state = _state.copyWith(isAutoFitEnabled: false);
  }

  void toggleAutoFit() {
    _state = _state.copyWith(isAutoFitEnabled: !_state.isAutoFitEnabled);
  }
}
