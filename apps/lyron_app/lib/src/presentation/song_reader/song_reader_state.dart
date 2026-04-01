enum SongReaderViewMode { chordsAndLyrics, lyricsOnly }

class SongReaderState {
  SongReaderState({
    this.viewMode = SongReaderViewMode.chordsAndLyrics,
    this.transposeOffset = 0,
    double sharedFontScale = 1.0,
  }) : sharedFontScale = _normalizeSharedFontScale(sharedFontScale);

  final SongReaderViewMode viewMode;
  final int transposeOffset;
  final double sharedFontScale;

  SongReaderState copyWith({
    SongReaderViewMode? viewMode,
    int? transposeOffset,
    double? sharedFontScale,
  }) {
    return SongReaderState(
      viewMode: viewMode ?? this.viewMode,
      transposeOffset: transposeOffset ?? this.transposeOffset,
      sharedFontScale: sharedFontScale ?? this.sharedFontScale,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SongReaderState &&
        other.viewMode == viewMode &&
        other.transposeOffset == transposeOffset &&
        other.sharedFontScale == sharedFontScale;
  }

  @override
  int get hashCode => Object.hash(viewMode, transposeOffset, sharedFontScale);

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
