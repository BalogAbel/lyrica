enum SongReaderViewMode { chordsAndLyrics, lyricsOnly }

enum SongReaderControlPresentationMode { overlay, pinned }

enum SongReaderInstrumentDisplayMode { guitar, piano }

class SongReaderState {
  SongReaderState({
    this.viewMode = SongReaderViewMode.chordsAndLyrics,
    this.transposeOffset = 0,
    this.capoOffset = 0,
    this.instrumentDisplayMode = SongReaderInstrumentDisplayMode.guitar,
    double sharedFontScale = 1.0,
    this.areCompactControlsVisible = false,
    this.controlPresentationMode = SongReaderControlPresentationMode.overlay,
    this.isAutoFitEnabled = true,
  }) : sharedFontScale = _normalizeSharedFontScale(sharedFontScale);

  final SongReaderViewMode viewMode;
  final int transposeOffset;
  final int capoOffset;
  final SongReaderInstrumentDisplayMode instrumentDisplayMode;
  final double sharedFontScale;
  final bool areCompactControlsVisible;
  final SongReaderControlPresentationMode controlPresentationMode;
  final bool isAutoFitEnabled;

  SongReaderState copyWith({
    SongReaderViewMode? viewMode,
    int? transposeOffset,
    int? capoOffset,
    SongReaderInstrumentDisplayMode? instrumentDisplayMode,
    double? sharedFontScale,
    bool? areCompactControlsVisible,
    SongReaderControlPresentationMode? controlPresentationMode,
    bool? isAutoFitEnabled,
  }) {
    return SongReaderState(
      viewMode: viewMode ?? this.viewMode,
      transposeOffset: transposeOffset ?? this.transposeOffset,
      capoOffset: capoOffset ?? this.capoOffset,
      instrumentDisplayMode:
          instrumentDisplayMode ?? this.instrumentDisplayMode,
      sharedFontScale: sharedFontScale ?? this.sharedFontScale,
      areCompactControlsVisible:
          areCompactControlsVisible ?? this.areCompactControlsVisible,
      controlPresentationMode:
          controlPresentationMode ?? this.controlPresentationMode,
      isAutoFitEnabled: isAutoFitEnabled ?? this.isAutoFitEnabled,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SongReaderState &&
        other.viewMode == viewMode &&
        other.transposeOffset == transposeOffset &&
        other.capoOffset == capoOffset &&
        other.instrumentDisplayMode == instrumentDisplayMode &&
        other.sharedFontScale == sharedFontScale &&
        other.areCompactControlsVisible == areCompactControlsVisible &&
        other.controlPresentationMode == controlPresentationMode &&
        other.isAutoFitEnabled == isAutoFitEnabled;
  }

  @override
  int get hashCode => Object.hash(
    viewMode,
    transposeOffset,
    capoOffset,
    instrumentDisplayMode,
    sharedFontScale,
    areCompactControlsVisible,
    controlPresentationMode,
    isAutoFitEnabled,
  );

  static double _normalizeSharedFontScale(double value) {
    const minScale = 0.5;
    const maxScale = 2.0;
    const defaultScale = 1.0;

    if (!value.isFinite || value <= 0) {
      return defaultScale;
    }

    if (value < minScale) {
      return minScale;
    }

    if (value > maxScale) {
      return maxScale;
    }

    return value;
  }
}
