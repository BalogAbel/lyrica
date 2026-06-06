import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';

// Height constants shared by the section grid and the fit-scale calculator.
const double sectionGap = 20.0;
const double headerHeight = 40.0;
const double lineGap = 10.0;
const double linePadding = 24.0;
const double characterWidthEstimate = 10.0;
const double chordRowHeight = 20.0;
const double lyricRowHeight = 24.0;
const double directiveLineHeight = 36.0;
const double tabBlockVerticalPadding = 16.0;

/// Returns an estimated pixel height for a single [section] when rendered at
/// the given [fontScale] and [maxWidth].
double estimateSectionHeight({
  required SongReaderSectionProjection section,
  required SongReaderViewMode viewMode,
  required double maxWidth,
  required double fontScale,
}) {
  final hasHeader =
      !(section.label == 'Unlabeled' && section.number == null);
  final h = hasHeader ? headerHeight : 0.0;
  final effectiveLineWidth = (maxWidth - linePadding).clamp(120.0, 1200.0);
  final charsPerLine =
      (effectiveLineWidth / (characterWidthEstimate * fontScale))
          .floor()
          .clamp(12, 140);
  var linesHeight = 0.0;
  for (final item in section.lines) {
    switch (item) {
      case SongReaderLyricLineProjection():
        final text = item.segments.map((s) => s.text).join();
        final lyricLength = text.trimRight().length;
        final hasChord =
            viewMode == SongReaderViewMode.chordsAndLyrics &&
            item.segments.any((s) => s.displayChord != null);
        final wrapCount = lyricLength == 0
            ? 1
            : (lyricLength / charsPerLine).ceil().clamp(1, 14);
        final chordH = hasChord ? (chordRowHeight * fontScale) : 0.0;
        final lyricH = wrapCount * (lyricRowHeight * fontScale);
        linesHeight += chordH + lyricH + lineGap;
      case SongReaderCommentProjection():
        final commentLength = item.text.length;
        final commentWrapCount = commentLength == 0
            ? 1
            : (commentLength / charsPerLine).ceil().clamp(1, 14);
        linesHeight +=
            commentWrapCount * (lyricRowHeight * fontScale) + lineGap;
      case SongReaderTabProjection():
        linesHeight +=
            item.rawLines.length * (lyricRowHeight * fontScale) +
            lineGap +
            tabBlockVerticalPadding;
      case SongReaderDirectiveProjection():
        linesHeight += directiveLineHeight;
    }
  }
  return h + linesHeight + sectionGap;
}

/// Returns the estimated total pixel height of [sections] stacked in a single
/// column at the given [fontScale] and [availableWidth].
double estimateSongContentHeight({
  required List<SongReaderSectionProjection> sections,
  required SongReaderViewMode viewMode,
  required double availableWidth,
  required double fontScale,
}) {
  return sections.fold<double>(
    0.0,
    (sum, section) =>
        sum +
        estimateSectionHeight(
          section: section,
          viewMode: viewMode,
          maxWidth: availableWidth,
          fontScale: fontScale,
        ),
  );
}

/// Returns the largest font scale in [minScale, maxScale] whose estimated
/// single-column content height fits within [availableHeight].
///
/// - If maxScale already fits → returns maxScale.
/// - If minScale still doesn't fit → returns minScale.
/// - Otherwise performs ~24 iterations of binary search and returns the lower
///   bound (i.e. the largest scale that provably fits).
double resolveFitFontScale({
  required List<SongReaderSectionProjection> sections,
  required SongReaderViewMode viewMode,
  required double availableWidth,
  required double availableHeight,
  required double minScale,
  required double maxScale,
}) {
  bool fits(double scale) =>
      estimateSongContentHeight(
        sections: sections,
        viewMode: viewMode,
        availableWidth: availableWidth,
        fontScale: scale,
      ) <=
      availableHeight;

  if (fits(maxScale)) return maxScale;
  if (!fits(minScale)) return minScale;

  var lo = minScale;
  var hi = maxScale;
  for (var i = 0; i < 24; i++) {
    final mid = (lo + hi) / 2;
    if (fits(mid)) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return lo;
}
