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
  final hasHeader = !(section.label == 'Unlabeled' && section.number == null);
  final h = hasHeader ? headerHeight : 0.0;
  final effectiveLineWidth = (maxWidth - linePadding).clamp(120.0, 1200.0);
  final charsPerLine =
      (effectiveLineWidth / (characterWidthEstimate * fontScale)).floor().clamp(
        12,
        140,
      );
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

/// Returns the height of the TALLER column when [sections] are split into two
/// columns using the most balanced split (minimum absolute height difference).
///
/// This mirrors the corrected `_bestTwoColumnSplitIndex` algorithm (abs-diff,
/// no left ≥ right constraint) so that fit-to-screen uses the same logic as
/// the section-grid layout.
double _estimateTwoColumnTallerHeight({
  required List<SongReaderSectionProjection> sections,
  required SongReaderViewMode viewMode,
  required double availableWidth,
  required double fontScale,
}) {
  if (sections.isEmpty) return 0;
  if (sections.length == 1) {
    return estimateSectionHeight(
      section: sections[0],
      viewMode: viewMode,
      maxWidth: availableWidth,
      fontScale: fontScale,
    );
  }

  final tileWidth = (availableWidth - sectionGap) / 2;
  final heights = sections
      .map(
        (s) => estimateSectionHeight(
          section: s,
          viewMode: viewMode,
          maxWidth: tileWidth,
          fontScale: fontScale,
        ),
      )
      .toList(growable: false);

  final total = heights.fold<double>(0, (a, b) => a + b);

  var running = 0.0;
  var bestDiff = double.infinity;

  for (var i = 0; i < heights.length - 1; i++) {
    running += heights[i];
    final diff = (running - (total - running)).abs();
    if (diff < bestDiff) bestDiff = diff;
  }

  // taller column = (total + |left - right|) / 2
  return (total + bestDiff) / 2;
}

/// Returns the largest font scale in [minScale, maxScale] whose estimated
/// content height fits within [availableHeight].
///
/// When [columnCount] is 2 the fit is computed against the TALLER of the two
/// columns (using a balanced split), allowing a larger scale on wide layouts.
/// For any other value of [columnCount] the standard single-column height is
/// used.
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
  int columnCount = 1,
}) {
  bool fits(double scale) {
    if (columnCount == 2) {
      return _estimateTwoColumnTallerHeight(
            sections: sections,
            viewMode: viewMode,
            availableWidth: availableWidth,
            fontScale: scale,
          ) <=
          availableHeight;
    }
    return estimateSongContentHeight(
          sections: sections,
          viewMode: viewMode,
          availableWidth: availableWidth,
          fontScale: scale,
        ) <=
        availableHeight;
  }

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
