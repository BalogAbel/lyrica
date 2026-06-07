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

// Layout decision constants (shared by the section grid, the fit calculator,
// and the layout resolver so all three agree).
const double denseLayoutMinWidth = 1180.0;
const double columnUsefulMaxRatio =
    0.9; // 2 cols must shave >=10% off single-col height
const double columnHeightToleranceFactor =
    1.15; // 2-col fallback if taller col overflows this
// A 2-column split is only worthwhile when the shorter column is at least this
// fraction of the taller column. Prevents one trivial section (e.g. an empty
// Intro) from leaving a near-empty column beside a dominant one.
const double columnBalanceMinRatio = 0.5;

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
        // Mirror SongLineView's collapse condition exactly: use .trim().isNotEmpty
        // (not just .isNotEmpty) so leading/trailing-whitespace-only text is
        // treated as empty, matching what the widget renders.
        final hasLyrics = item.segments.any((s) => s.text.trim().isNotEmpty);
        if (!hasLyrics && viewMode == SongReaderViewMode.lyricsOnly) {
          break; // collapsed to SizedBox.shrink() in lyricsOnly → contributes no height
        }
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

/// Returns the heights of both columns when [sections] are split into two
/// columns using the most balanced split (minimum absolute height difference).
///
/// The record `(taller, shorter)` mirrors the corrected
/// `_bestTwoColumnSplitIndex` algorithm (abs-diff, no left ≥ right constraint)
/// so that fit-to-screen uses the same split logic as the section-grid layout.
/// Returning both columns lets callers apply a balance guard in addition to the
/// existing height-gain ("useful split") guard.
({double taller, double shorter}) _estimateTwoColumnSplit({
  required List<SongReaderSectionProjection> sections,
  required SongReaderViewMode viewMode,
  required double availableWidth,
  required double fontScale,
}) {
  if (sections.isEmpty) return (taller: 0, shorter: 0);
  if (sections.length == 1) {
    final h = estimateSectionHeight(
      section: sections[0],
      viewMode: viewMode,
      maxWidth: availableWidth,
      fontScale: fontScale,
    );
    return (taller: h, shorter: 0);
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
  // shorter column = (total - |left - right|) / 2
  return (taller: (total + bestDiff) / 2, shorter: (total - bestDiff) / 2);
}

/// Result of [estimateRenderedLayout]: estimated pixel height and effective
/// column count the grid will actually render at the given font scale.
class RenderedHeightEstimate {
  const RenderedHeightEstimate({
    required this.height,
    required this.columnCount,
  });

  final double height;
  final int columnCount;
}

/// Decides whether content renders in 1 or 2 columns at [fontScale] and returns
/// the resulting estimated height. Mirrors [SongReaderSectionGrid.build] exactly:
///  - 2 columns only when [allowTwoColumns] AND >=2 sections AND single-column
///    height (incl. [leadingDirectiveHeight]) overflows [availableHeight] AND the
///    split is "useful" (taller column <= single * [columnUsefulMaxRatio]) AND the
///    split is "balanced" (shorter column >= taller * [columnBalanceMinRatio]) AND
///    the taller column fits [availableHeight] * [columnHeightToleranceFactor].
///
/// The [leadingDirectiveHeight] is added pessimistically to the taller column
/// (col 0 always receives the directive in the grid; adding it to `taller`
/// is safe when col 0 is already the taller column, and only slightly
/// over-estimates when col 1 is taller).
RenderedHeightEstimate estimateRenderedLayout({
  required List<SongReaderSectionProjection> sections,
  required SongReaderViewMode viewMode,
  required double availableWidth,
  required double availableHeight,
  required double fontScale,
  required bool allowTwoColumns,
  double leadingDirectiveHeight = 0,
}) {
  final single =
      estimateSongContentHeight(
        sections: sections,
        viewMode: viewMode,
        availableWidth: availableWidth,
        fontScale: fontScale,
      ) +
      leadingDirectiveHeight;

  if (!allowTwoColumns || sections.length < 2 || single <= availableHeight) {
    return RenderedHeightEstimate(height: single, columnCount: 1);
  }

  final split = _estimateTwoColumnSplit(
    sections: sections,
    viewMode: viewMode,
    availableWidth: availableWidth,
    fontScale: fontScale,
  );

  // Add the leading directive to the taller column (col 0 always receives the
  // directive in the grid; pessimistic but safe).
  final tallerWithDirective = split.taller + leadingDirectiveHeight;

  final usefulSplit = tallerWithDirective <= single * columnUsefulMaxRatio;

  // Balance guard: reject splits where one column is nearly empty. The check
  // uses the raw section split (not including leadingDirectiveHeight, which is
  // decorative on col 0 and would distort the balance ratio).
  final balancedSplit =
      split.taller > 0 && split.shorter >= split.taller * columnBalanceMinRatio;

  final fitsTolerance =
      tallerWithDirective <= availableHeight * columnHeightToleranceFactor;

  if (usefulSplit && balancedSplit && fitsTolerance) {
    return RenderedHeightEstimate(height: tallerWithDirective, columnCount: 2);
  }
  return RenderedHeightEstimate(height: single, columnCount: 1);
}

/// Returns the largest font scale in [[minScale], [maxScale]] whose estimated
/// content height fits within [availableHeight].
///
/// When [allowTwoColumns] is true the fit is computed via [estimateRenderedLayout],
/// which mirrors the grid's own column-decision logic (overflow check, useful-split
/// guard, tolerance guard). This guarantees that the fit scale and the rendered
/// layout always agree on column count, so a double-tap fit can never produce a
/// scale that causes the grid to flip columns and overflow.
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
  bool allowTwoColumns = false,
  double leadingDirectiveHeight = 0,
}) {
  bool fits(double scale) =>
      estimateRenderedLayout(
        sections: sections,
        viewMode: viewMode,
        availableWidth: availableWidth,
        availableHeight: availableHeight,
        fontScale: scale,
        allowTwoColumns: allowTwoColumns,
        leadingDirectiveHeight: leadingDirectiveHeight,
      ).height <=
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
