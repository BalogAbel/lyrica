enum SongReaderViewMode { chordsAndLyrics, lyricsOnly }

class SongReaderState {
  const SongReaderState({
    this.viewMode = SongReaderViewMode.chordsAndLyrics,
    this.transposeOffset = 0,
    this.sharedFontScale = 1.0,
  });

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
}
