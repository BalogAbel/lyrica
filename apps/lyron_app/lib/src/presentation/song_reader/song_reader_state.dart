enum SongReaderViewMode { chordsAndLyrics, lyricsOnly }

enum SongReaderControlPresentationMode { overlay, pinned }

class SongReaderState {
  SongReaderState({
    this.viewMode = SongReaderViewMode.chordsAndLyrics,
    this.transposeOffset = 0,
    double sharedFontScale = 1.0,
    this.areCompactControlsVisible = false,
    this.controlPresentationMode = SongReaderControlPresentationMode.overlay,
    this.isAutoFitEnabled = true,
  }) : sharedFontScale = _normalizeSharedFontScale(sharedFontScale);

  final SongReaderViewMode viewMode;
  final int transposeOffset;
  final double sharedFontScale;
  final bool areCompactControlsVisible;
  final SongReaderControlPresentationMode controlPresentationMode;
  final bool isAutoFitEnabled;

  SongReaderState copyWith({
    SongReaderViewMode? viewMode,
    int? transposeOffset,
    double? sharedFontScale,
    bool? areCompactControlsVisible,
    SongReaderControlPresentationMode? controlPresentationMode,
    bool? isAutoFitEnabled,
  }) {
    return SongReaderState(
      viewMode: viewMode ?? this.viewMode,
      transposeOffset: transposeOffset ?? this.transposeOffset,
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
        other.sharedFontScale == sharedFontScale &&
        other.areCompactControlsVisible == areCompactControlsVisible &&
        other.controlPresentationMode == controlPresentationMode &&
        other.isAutoFitEnabled == isAutoFitEnabled;
  }

  @override
  int get hashCode => Object.hash(
    viewMode,
    transposeOffset,
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
