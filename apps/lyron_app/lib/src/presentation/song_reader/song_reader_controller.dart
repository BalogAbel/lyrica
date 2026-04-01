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

  void setSharedFontScale(double scale) {
    _state = _state.copyWith(sharedFontScale: scale);
  }
}
