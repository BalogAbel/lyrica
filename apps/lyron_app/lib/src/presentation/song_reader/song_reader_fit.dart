import 'package:lyron_app/src/presentation/song_reader/song_reader_metrics.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_word_groups.dart';

// Height constants shared by the section grid and the fit-scale calculator.
const double sectionGap = 20.0;
const double headerHeight = 40.0;
const double lineGap = 10.0;
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
// fraction of the taller column.  With item-level flow the dominant-section
// case can now be balanced via a mid-section split, so this guard applies to
// the flow-block split candidates rather than section-atomic ones.
const double columnBalanceMinRatio = 0.5;

// ─────────────────────────────────────────────────────────────────────────────
// Flow-block model
// ─────────────────────────────────────────────────────────────────────────────

/// Granularity of a layout block used for item-level column flow.
enum FlowBlockKind {
  /// The leading capo/tuning directive that precedes the first section.
  leadingDirective,

  /// A section header label (e.g. "Verse 1").
  sectionHeader,

  /// A single content line inside a section (lyric, comment, tab or inline
  /// directive).
  line,
}

/// A single indivisible layout unit produced by [buildFlowBlocks].
///
/// The flow-block model lets the column splitter cut anywhere between blocks
/// rather than only between whole sections.  This enables a dominant section
/// (e.g. a big Verse) to be split across both columns even when a
/// section-boundary split would be unbalanced.
class FlowBlock {
  const FlowBlock({
    required this.kind,
    required this.sectionIndex,
    this.line,
    this.isSectionStart = false,
  });

  /// Kind of this block.
  final FlowBlockKind kind;

  /// Index into the original sections list.  -1 for [FlowBlockKind.leadingDirective].
  final int sectionIndex;

  /// The underlying line projection when [kind] == [FlowBlockKind.line].
  final SongReaderSectionItemProjection? line;

  /// True for the very first block that represents a section (its header if it
  /// has one, otherwise its first line).  Used by [resolveFlowLayout] to prefer
  /// section-boundary split candidates.
  final bool isSectionStart;
}

/// Converts [sections] (and the optional leading directive) into an ordered
/// flat list of [FlowBlock]s that the column layout can split at any position.
///
/// Gap accounting (must stay consistent with [flowBlockHeight]):
///   - [FlowBlockKind.leadingDirective]: contributes `directiveLineHeight + sectionGap`.
///   - First block of every section (either its header or, for unlabeled
///     sections, its first line) carries `sectionGap` in addition to its own
///     intrinsic height.  The sum of all block heights for a section therefore
///     equals `estimateSectionHeight`, within floating-point rounding.
///   - Empty unlabeled sections (no header, no lines) produce zero blocks.
List<FlowBlock> buildFlowBlocks({
  required List<SongReaderSectionProjection> sections,
  required bool hasLeadingDirective,
}) {
  final result = <FlowBlock>[];

  if (hasLeadingDirective) {
    result.add(
      const FlowBlock(kind: FlowBlockKind.leadingDirective, sectionIndex: -1),
    );
  }

  for (var i = 0; i < sections.length; i++) {
    final section = sections[i];
    final hasHeader = !(section.label == 'Unlabeled' && section.number == null);

    if (hasHeader) {
      // The header block is the section start; it carries sectionGap.
      result.add(
        FlowBlock(
          kind: FlowBlockKind.sectionHeader,
          sectionIndex: i,
          isSectionStart: true,
        ),
      );
      // Line blocks within a labeled section are never isSectionStart.
      for (final lineItem in section.lines) {
        result.add(
          FlowBlock(
            kind: FlowBlockKind.line,
            sectionIndex: i,
            line: lineItem,
            isSectionStart: false,
          ),
        );
      }
    } else {
      // Unlabeled section: no header block.
      if (section.lines.isEmpty) continue; // nothing to emit

      // First line is the section start; it carries sectionGap.
      result.add(
        FlowBlock(
          kind: FlowBlockKind.line,
          sectionIndex: i,
          line: section.lines[0],
          isSectionStart: true,
        ),
      );
      for (var j = 1; j < section.lines.length; j++) {
        result.add(
          FlowBlock(
            kind: FlowBlockKind.line,
            sectionIndex: i,
            line: section.lines[j],
            isSectionStart: false,
          ),
        );
      }
    }
  }

  return result;
}

// ─────────────────────────────────────────────────────────────────────────────
// Per-block height (shared between estimateSectionHeight and flowBlockHeight)
// ─────────────────────────────────────────────────────────────────────────────

/// Computes the estimated height of [item] when rendered at [columnWidth] and
/// [fontScale] in [viewMode].
///
/// This is the single canonical per-line height formula shared by both
/// [estimateSectionHeight] (which iterates sections) and [flowBlockHeight]
/// (which operates on individual blocks).  Keeping them in sync here prevents
/// height-estimate drift between the fit calculator and the renderer.
double _lineItemHeight({
  required SongReaderSectionItemProjection item,
  required SongReaderViewMode viewMode,
  required double columnWidth,
  required double fontScale,
}) {
  final effectiveLineWidth = columnWidth.clamp(120.0, 1200.0);
  final charsPerLine =
      (effectiveLineWidth / (characterWidthEstimate * fontScale)).floor().clamp(
        12,
        140,
      );

  switch (item) {
    case SongReaderLyricLineProjection():
      final hasLyrics = item.segments.any((s) => s.text.trim().isNotEmpty);
      if (!hasLyrics && viewMode == SongReaderViewMode.lyricsOnly) {
        return 0.0; // collapsed in lyricsOnly
      }
      final showChords = viewMode == SongReaderViewMode.chordsAndLyrics;

      // Mirror the renderer's grouping condition (song_line_view.dart):
      // word groups only apply when the line has lyric segments. A
      // chord-only line is measured one segment at a time, exactly as it
      // is rendered.
      final groups = hasLyrics
          ? groupSegmentsIntoWords(
              item.segments,
            ).map((group) => group.segments).toList(growable: false)
          : [
              for (final segment in item.segments) [segment],
            ];

      // Greedily pack groups into runs of effectiveLineWidth, mirroring the
      // renderer's outer Wrap. A group wider than a whole run occupies
      // ceil(groupWidth / effectiveLineWidth) runs on its own -- this
      // mirrors the renderer's inner ConstrainedBox+Wrap fallback, which
      // forces the same runSpacing between its own wrapped rows. Only the
      // first of those runs is credited with the group's chord, since the
      // renderer draws the chord once above the (possibly internally
      // wrapped) lyric text.
      final runHasChord = <bool>[];
      var currentRunWidth = 0.0;
      var currentRunHasChord = false;
      var currentRunStarted = false;

      void flushRun() {
        if (currentRunStarted) {
          runHasChord.add(currentRunHasChord);
        }
        currentRunWidth = 0.0;
        currentRunHasChord = false;
        currentRunStarted = false;
      }

      for (final group in groups) {
        final groupWidth =
            group.fold<double>(0.0, (sum, s) => sum + s.text.length) *
            characterWidthEstimate *
            fontScale;
        final groupHasChord = group.any((s) => s.displayChord != null);

        if (groupWidth > effectiveLineWidth) {
          flushRun();
          final runsNeeded = (groupWidth / effectiveLineWidth).ceil();
          runHasChord.add(groupHasChord);
          for (var i = 1; i < runsNeeded; i++) {
            runHasChord.add(false);
          }
          continue;
        }

        if (currentRunStarted &&
            currentRunWidth + groupWidth > effectiveLineWidth) {
          flushRun();
        }
        currentRunStarted = true;
        currentRunWidth += groupWidth;
        currentRunHasChord = currentRunHasChord || groupHasChord;
      }
      flushRun();

      if (runHasChord.isEmpty) {
        runHasChord.add(false);
      }

      final runsHeight = runHasChord.fold<double>(0.0, (sum, hasChord) {
        final lyricH = lyricRowHeight * fontScale;
        final chordH = (hasChord && showChords)
            ? (chordRowHeight * fontScale + chordToLyricGap)
            : 0.0;
        return sum + lyricH + chordH;
      });

      return runsHeight + (runHasChord.length - 1) * lineRunSpacing + lineGap;
    case SongReaderCommentProjection():
      final commentLength = item.text.length;
      final commentWrapCount = commentLength == 0
          ? 1
          : (commentLength / charsPerLine).ceil().clamp(1, 14);
      return commentWrapCount * (lyricRowHeight * fontScale) + lineGap;
    case SongReaderTabProjection():
      return item.rawLines.length * (lyricRowHeight * fontScale) +
          lineGap +
          tabBlockVerticalPadding;
    case SongReaderDirectiveProjection():
      return directiveLineHeight;
  }
}

/// Estimated pixel height of a [FlowBlock] when rendered at the given
/// [columnWidth], [fontScale], and [viewMode].
///
/// Gap accounting mirrors [buildFlowBlocks] documentation:
///   - [FlowBlockKind.leadingDirective]  → `directiveLineHeight + sectionGap`
///   - [FlowBlockKind.sectionHeader]     → `headerHeight + sectionGap`
///     (sectionGap is the gap that follows the section's last line but is
///     charged here, at the first block, so the sum per section equals
///     `estimateSectionHeight`)
///   - [FlowBlockKind.line] with `isSectionStart=true` → line height + sectionGap
///     (only for unlabeled sections whose first line is the section start)
///   - [FlowBlockKind.line] with `isSectionStart=false` → line height only
double flowBlockHeight({
  required FlowBlock block,
  required SongReaderViewMode viewMode,
  required double columnWidth,
  required double fontScale,
}) {
  switch (block.kind) {
    case FlowBlockKind.leadingDirective:
      return directiveLineHeight + sectionGap;
    case FlowBlockKind.sectionHeader:
      // sectionGap is charged here (see gap-accounting note above).
      return headerHeight + sectionGap;
    case FlowBlockKind.line:
      final lineH = _lineItemHeight(
        item: block.line!,
        viewMode: viewMode,
        columnWidth: columnWidth,
        fontScale: fontScale,
      );
      // For unlabeled sections the first line carries the sectionGap.
      return block.isSectionStart ? lineH + sectionGap : lineH;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Flow layout resolver
// ─────────────────────────────────────────────────────────────────────────────

/// Result of [resolveFlowLayout]: the chosen column count, the block index
/// where the right column begins, and the estimated taller-column height.
class FlowLayout {
  const FlowLayout({
    required this.columnCount,
    required this.splitIndex,
    required this.height,
  });

  final int columnCount;

  /// Index into the block list; blocks[0:splitIndex] go in the left column,
  /// blocks[splitIndex:] go in the right column.  Equals blocks.length when
  /// [columnCount] == 1.
  final int splitIndex;

  /// Estimated height of the taller column (or single column).
  final double height;
}

/// Decides whether to render in 1 or 2 columns given pre-computed block heights.
///
/// Strategy (PREFER section boundaries, fall back to mid-section):
/// 1. If `!allowTwoColumns` or fewer than 2 blocks or total fits in
///    `availableHeight` → 1 column.
/// 2. Try SECTION-BOUNDARY candidates (indices where `blocks[i].isSectionStart`
///    is true).  Find the split with the smallest |left − right|, reject
///    any `i` where `blocks[i-1].kind == FlowBlockKind.sectionHeader` (stranded
///    header).  If the best is balanced, useful, and fits tolerance → use it.
/// 3. Otherwise try ALL valid candidates (mid-section allowed, same orphan
///    guard).  If the best passes all three guards → 2 columns.
/// 4. Else → 1 column.
FlowLayout resolveFlowLayout({
  required List<FlowBlock> blocks,
  required List<double> blockHeights,
  required List<bool> sectionStartFlags,
  required double availableHeight,
  required bool allowTwoColumns,
}) {
  final total = blockHeights.fold<double>(0.0, (a, b) => a + b);

  if (!allowTwoColumns || blocks.length < 2 || total <= availableHeight) {
    return FlowLayout(columnCount: 1, splitIndex: blocks.length, height: total);
  }

  // ── helper: evaluate a candidate split index ──────────────────────────────

  // Precompute prefix sums for O(1) left-column queries.
  final prefix = List<double>.filled(blocks.length + 1, 0.0);
  for (var k = 0; k < blocks.length; k++) {
    prefix[k + 1] = prefix[k] + blockHeights[k];
  }

  bool isValidCandidate(int i) {
    // Left column must be non-empty, right column must be non-empty.
    if (i <= 0 || i >= blocks.length) return false;
    // Do not strand a sectionHeader without its content at the bottom of the
    // left column.  Only block the split when the header's own lines would
    // start in the right column (blocks[i] is the first line of the same
    // section as blocks[i-1]).  An empty section whose header is the final
    // block of a section is fine — nothing gets stranded.
    if (blocks[i - 1].kind == FlowBlockKind.sectionHeader &&
        blocks[i].sectionIndex == blocks[i - 1].sectionIndex) {
      return false;
    }
    return true;
  }

  bool isBalancedAndUseful(int i) {
    final left = prefix[i];
    final right = total - left;
    final taller = left > right ? left : right;
    final shorter = left < right ? left : right;
    final usefulSplit = taller <= total * columnUsefulMaxRatio;
    final balancedSplit =
        taller > 0 && shorter >= taller * columnBalanceMinRatio;
    final fitsTolerance =
        taller <= availableHeight * columnHeightToleranceFactor;
    return usefulSplit && balancedSplit && fitsTolerance;
  }

  ({int index, double diff}) findBest(Iterable<int> candidates) {
    var bestIndex = -1;
    var bestDiff = double.infinity;
    for (final i in candidates) {
      if (!isValidCandidate(i)) continue;
      final diff = (prefix[i] - (total - prefix[i])).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        bestIndex = i;
      }
    }
    return (index: bestIndex, diff: bestDiff);
  }

  // ── pass 1: section-boundary candidates ──────────────────────────────────
  final sectionBoundaryCandidates = List.generate(
    blocks.length,
    (i) => i,
  ).where((i) => i > 0 && sectionStartFlags[i]);

  final best1 = findBest(sectionBoundaryCandidates);
  if (best1.index >= 0 && isBalancedAndUseful(best1.index)) {
    final left = prefix[best1.index];
    final right = total - left;
    final taller = left > right ? left : right;
    return FlowLayout(columnCount: 2, splitIndex: best1.index, height: taller);
  }

  // ── pass 2: all-candidate fallback (mid-section allowed) ─────────────────
  final allCandidates = List.generate(blocks.length - 1, (i) => i + 1);
  final best2 = findBest(allCandidates);
  if (best2.index >= 0 && isBalancedAndUseful(best2.index)) {
    final left = prefix[best2.index];
    final right = total - left;
    final taller = left > right ? left : right;
    return FlowLayout(columnCount: 2, splitIndex: best2.index, height: taller);
  }

  return FlowLayout(columnCount: 1, splitIndex: blocks.length, height: total);
}

// ─────────────────────────────────────────────────────────────────────────────
// Section-height helpers (preserved for compatibility)
// ─────────────────────────────────────────────────────────────────────────────

/// Returns an estimated pixel height for a single [section] when rendered at
/// the given [fontScale] and [maxWidth].
///
/// Delegates per-line height to [_lineItemHeight] so the calculation is
/// identical to [flowBlockHeight]'s line branch.
double estimateSectionHeight({
  required SongReaderSectionProjection section,
  required SongReaderViewMode viewMode,
  required double maxWidth,
  required double fontScale,
}) {
  final hasHeader = !(section.label == 'Unlabeled' && section.number == null);
  final h = hasHeader ? headerHeight : 0.0;
  var linesHeight = 0.0;
  for (final item in section.lines) {
    linesHeight += _lineItemHeight(
      item: item,
      viewMode: viewMode,
      columnWidth: maxWidth,
      fontScale: fontScale,
    );
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

// ─────────────────────────────────────────────────────────────────────────────
// Rendered-layout estimate (flow-block aware)
// ─────────────────────────────────────────────────────────────────────────────

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

/// Builds flow blocks and computes their heights at [tileWidth], then runs
/// [resolveFlowLayout].  Returns the [FlowLayout] used by both
/// [estimateRenderedLayout] and [SongReaderSectionGrid] to ensure they always
/// agree on column count and split index.
///
/// Pass `hasLeadingDirective: true` when a leading directive is present; the
/// directive's height is included in the block heights.
FlowLayout resolveFlowLayoutForSections({
  required List<SongReaderSectionProjection> sections,
  required SongReaderViewMode viewMode,
  required double tileWidth,
  required double availableHeight,
  required double fontScale,
  required bool allowTwoColumns,
  required bool hasLeadingDirective,
}) {
  final blocks = buildFlowBlocks(
    sections: sections,
    hasLeadingDirective: hasLeadingDirective,
  );
  final blockHeights = blocks
      .map(
        (b) => flowBlockHeight(
          block: b,
          viewMode: viewMode,
          columnWidth: tileWidth,
          fontScale: fontScale,
        ),
      )
      .toList(growable: false);
  final sectionStartFlags = blocks
      .map((b) => b.isSectionStart)
      .toList(growable: false);

  return resolveFlowLayout(
    blocks: blocks,
    blockHeights: blockHeights,
    sectionStartFlags: sectionStartFlags,
    availableHeight: availableHeight,
    allowTwoColumns: allowTwoColumns,
  );
}

/// Decides whether content renders in 1 or 2 columns at [fontScale] and returns
/// the resulting estimated height.
///
/// Uses [resolveFlowLayout] via [resolveFlowLayoutForSections] so that the
/// fit calculator and the grid always agree on column count and split index.
///
/// Column widths:
///   - Single-column total is computed at [availableWidth] (full width).
///   - The 2-column split search uses tile width = (availableWidth − sectionGap)/2.
///   - The returned height when columnCount==2 is the taller column at tile width.
///
/// The [leadingDirectiveHeight] is included in the block list (as a
/// [FlowBlockKind.leadingDirective] block) when non-zero, so its contribution
/// is distributed correctly between the two passes.
RenderedHeightEstimate estimateRenderedLayout({
  required List<SongReaderSectionProjection> sections,
  required SongReaderViewMode viewMode,
  required double availableWidth,
  required double availableHeight,
  required double fontScale,
  required bool allowTwoColumns,
  double leadingDirectiveHeight = 0,
}) {
  // Single-column total: blocks at full width.
  final hasLeadingDirective = leadingDirectiveHeight > 0;
  final singleBlocks = buildFlowBlocks(
    sections: sections,
    hasLeadingDirective: hasLeadingDirective,
  );
  final single = singleBlocks
      .map(
        (b) => flowBlockHeight(
          block: b,
          viewMode: viewMode,
          columnWidth: availableWidth,
          fontScale: fontScale,
        ),
      )
      .fold<double>(0.0, (a, b) => a + b);

  if (!allowTwoColumns ||
      singleBlocks.length < 2 ||
      single <= availableHeight) {
    return RenderedHeightEstimate(height: single, columnCount: 1);
  }

  // Two-column candidate: blocks at tile width.
  final tileWidth = (availableWidth - sectionGap) / 2;
  final layout = resolveFlowLayoutForSections(
    sections: sections,
    viewMode: viewMode,
    tileWidth: tileWidth,
    availableHeight: availableHeight,
    fontScale: fontScale,
    allowTwoColumns: true,
    hasLeadingDirective: hasLeadingDirective,
  );

  if (layout.columnCount == 2) {
    return RenderedHeightEstimate(height: layout.height, columnCount: 2);
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
