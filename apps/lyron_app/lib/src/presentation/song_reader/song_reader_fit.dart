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

/// `SongLineView`'s own `Padding(padding: const EdgeInsets.only(bottom: 2))`
/// (widgets/song_line_view.dart), which wraps every lyric line's `Wrap` and is
/// therefore part of the widget's measured render height -- but was never
/// added on the estimate side. Measured 2026-07-28: the "chord-only
/// instrumental bar" per-line fixture rendered at 122px against an estimate
/// of 120px, a 2px shortfall that reproduced exactly this padding (the
/// fixture has no lyric-text word-wrap in play at all, so it isolates this
/// gap from the word-wrap-count fix above). This is not a "just in case"
/// safety margin: it is this literal, already-present padding value, charged
/// once per lyric line to match what the widget actually adds.
const double lineWidgetBottomPadding = 2.0;

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
/// Estimated pixel width of a single segment: the wider of its lyric text
/// (at [lyricCharWidth] px/char) and its chord label (at [chordCharWidth]
/// px/char, when chords are shown), each scaled by [fontScale].
///
/// Mirrors the renderer (song_line_view.dart): `_SongLineSegmentView` stacks
/// the chord and lyric `Text` widgets in a `Column`, so the rendered segment
/// is as wide as the wider of the two, not the sum of lyric characters alone.
/// The two text styles have different measured per-character advances (see
/// [measureSongReaderCharWidths]), so the lyric and chord character counts
/// must be weighted by their own widths rather than a single shared
/// estimate -- using one estimate for both undercounts whichever style is
/// actually wider (a bold chord label in particular runs wider per char
/// than the lyric body text), which undercounts how many runs a chord-heavy
/// line actually wraps into.
double _segmentPixelWidth(
  SongReaderSegmentProjection segment,
  bool showChords, {
  required double lyricCharWidth,
  required double chordCharWidth,
  required double fontScale,
}) {
  final lyricWidth = segment.text.length * lyricCharWidth * fontScale;
  final chordWidth = (showChords && segment.displayChord != null)
      ? segment.displayChord!.length * chordCharWidth * fontScale
      : 0.0;
  return lyricWidth > chordWidth ? lyricWidth : chordWidth;
}

/// Number of visual lines a segment's own lyric `Text` soft-wraps into when
/// laid out at [effectiveLineWidth].
///
/// This is a DIFFERENT quantity from [_segmentPixelWidth] and must use a
/// DIFFERENT input: `_segmentPixelWidth` uses the wider of the lyric text and
/// the chord label because that decides how much horizontal room a segment
/// occupies for Wrap-packing purposes (a chord wider than its lyric still
/// pushes neighbours onto the next run). But the chord label itself never
/// wraps -- in `_SongLineSegmentView` (song_line_view.dart) it is a single
/// `Text` with no `ConstrainedBox`, drawn once above the lyric. Only the
/// lyric `Text` sits inside a `ConstrainedBox(maxWidth: maxWidth)` with
/// `softWrap: true`, so only the lyric character count may push this count
/// above 1. Using the wider (chord-inclusive) width here would wrongly
/// inflate the line count for a short lyric syllable under a long chord.
///
/// Conflating these two widths is exactly how the chord-row/lyric-wrap bugs
/// in this file keep recurring -- keep them separate.
///
/// Real text layout breaks at WORD boundaries, not at an arbitrary character
/// count, so a plain `ceil(lyricWidth / effectiveLineWidth)` division
/// undercounts: it lets a wrap point fall in the middle of a word, packing
/// more characters onto a line than real layout would allow, which pushes
/// the estimate below the rendered height -- exactly backwards for
/// `resolveFitFontScale`, which must never choose a scale whose estimated
/// height is less than what actually renders. This models the same greedy
/// left-to-right packing the run-packing loop above already uses for
/// groups: split the text on spaces, and greedily pack whole words onto a
/// line, starting a new line whenever the next word would overflow. A
/// single word wider than a whole line is placed on its own and spans
/// `ceil(wordWidth / effectiveLineWidth)` lines by itself (mirroring how a
/// single unbreakable token still gets clipped into multiple lines by
/// `Text`'s own line-breaking, since there is no word boundary inside it to
/// break at).
int _segmentIntraLines({
  required SongReaderSegmentProjection segment,
  required double effectiveLineWidth,
  required double fontScale,
  required double lyricCharWidth,
}) {
  final text = segment.text;
  if (text.isEmpty) return 1;

  final charWidth = lyricCharWidth * fontScale;
  final spaceWidth = charWidth;
  final words = text.split(' ');

  var lineCount = 0;
  var currentLineWidth = 0.0;
  var currentLineStarted = false;

  void flushLine() {
    if (currentLineStarted) {
      lineCount += 1;
    }
    currentLineWidth = 0.0;
    currentLineStarted = false;
  }

  for (final word in words) {
    final wordWidth = word.length * charWidth;

    if (wordWidth > effectiveLineWidth) {
      // A single word longer than the line occupies
      // ceil(wordWidth / effectiveLineWidth) lines on its own -- flush
      // whatever was accumulating on the current line first (it does not
      // share a line with this oversized word).
      flushLine();
      lineCount += (wordWidth / effectiveLineWidth).ceil();
      continue;
    }

    final widthIfAppended = currentLineStarted
        ? currentLineWidth + spaceWidth + wordWidth
        : wordWidth;
    if (currentLineStarted && widthIfAppended > effectiveLineWidth) {
      flushLine();
      currentLineWidth = wordWidth;
      currentLineStarted = true;
    } else {
      currentLineWidth = widthIfAppended;
      currentLineStarted = true;
    }
  }
  flushLine();

  return lineCount < 1 ? 1 : lineCount;
}

double _lineItemHeight({
  required SongReaderSectionItemProjection item,
  required SongReaderViewMode viewMode,
  required double columnWidth,
  required double fontScale,
  double lyricCharWidth = characterWidthEstimate,
  double chordCharWidth = characterWidthEstimate,
}) {
  final effectiveLineWidth = columnWidth.clamp(120.0, 1200.0);
  final charsPerLine = (effectiveLineWidth / (lyricCharWidth * fontScale))
      .floor()
      .clamp(12, 140);

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

      // A group's width is the sum of its segments' widths (the wider of
      // each segment's lyric text and its chord label -- see
      // _segmentPixelWidth), not lyric characters alone. This mirrors the
      // renderer, where a chord-only segment still occupies its chord's
      // width and a chord wider than its lyric sets the segment's width.
      //
      // Greedily pack groups into runs of effectiveLineWidth, mirroring the
      // renderer's outer Wrap. A group wider than a whole run is instead
      // packed segment-by-segment into its own runs (see the branch below),
      // mirroring the renderer's inner ConstrainedBox+Wrap fallback
      // (song_line_view.dart), which lays out that group's segments in
      // their own Wrap with spacing: 0 and gives every run that receives a
      // chorded segment its own chord row.
      //
      // A chord-only line skips word grouping (each segment is its own
      // "group", see `groups` above) and the renderer's outer Wrap uses
      // chordOnlySpacing between its children instead of the 0-spacing used
      // for word groups; interGroupSpacing mirrors that gap between groups
      // packed into the same run.
      final interGroupSpacing = hasLyrics ? 0.0 : chordOnlySpacing;

      // Per run: whether it carries a chord, whether it carries any lyric
      // text (see below), and how many lyric lines its TALLEST segment's
      // own Text wraps into (Wrap sizes a run to its tallest child -- see
      // _segmentIntraLines). Runs built by the normal group-packing loop
      // below always record 1 intra-line: a group only reaches that loop
      // when it is NOT over-wide, which means every one of its segments
      // individually fits within effectiveLineWidth too (their widths sum
      // to at most effectiveLineWidth), so none of them can need more than
      // one lyric line. Only the over-wide branch further down can produce
      // a run whose tallest segment needs >1.
      //
      // runHasLyric mirrors _SongLineSegmentView's `showLyric` condition
      // exactly (song_line_view.dart): `segment.text.isNotEmpty`, NOT a
      // trimmed check. A run whose every segment has empty text renders no
      // lyric `Text` at all -- the segment's Column has only its chord
      // child -- so that run must cost a chord row only, never a lyric
      // row. This is what makes a chord-only instrumental bar (every
      // segment's text == '') estimate as chord rows alone instead of
      // (wrongly) charging a full lyric row for every one of its runs too.
      bool segmentHasLyric(SongReaderSegmentProjection s) => s.text.isNotEmpty;

      final runHasChord = <bool>[];
      final runHasLyric = <bool>[];
      final runIntraLines = <int>[];
      var currentRunWidth = 0.0;
      var currentRunHasChord = false;
      var currentRunHasLyric = false;
      var currentRunStarted = false;

      void flushRun() {
        if (currentRunStarted) {
          runHasChord.add(currentRunHasChord);
          runHasLyric.add(currentRunHasLyric);
          runIntraLines.add(1);
        }
        currentRunWidth = 0.0;
        currentRunHasChord = false;
        currentRunHasLyric = false;
        currentRunStarted = false;
      }

      for (final group in groups) {
        final groupWidth = group.fold<double>(
          0.0,
          (sum, s) =>
              sum +
              _segmentPixelWidth(
                s,
                showChords,
                lyricCharWidth: lyricCharWidth,
                chordCharWidth: chordCharWidth,
                fontScale: fontScale,
              ),
        );
        final groupHasChord = group.any((s) => s.displayChord != null);
        final groupHasLyric = group.any(segmentHasLyric);

        if (groupWidth > effectiveLineWidth) {
          // This group alone won't fit in one run. It starts on a fresh run
          // (flushRun below closes whatever run was already in progress),
          // then its own segments are packed the way the renderer's inner
          // Wrap packs them: greedily, with 0 spacing between segments in
          // the same group (song_line_view.dart's inner Wrap uses
          // spacing: 0). Each resulting run remembers whether it received a
          // chorded segment, since every such run draws its own chord row.
          flushRun();

          var segRunWidth = 0.0;
          var segRunHasChord = false;
          var segRunHasLyric = false;
          var segRunIntraLines = 1;
          var segRunStarted = false;

          void flushSegRun() {
            if (segRunStarted) {
              runHasChord.add(segRunHasChord);
              runHasLyric.add(segRunHasLyric);
              // A run's height is the max of its segments' heights (Wrap
              // sizes a run to its tallest child), so the run's intra-line
              // count is the max over its segments, not a sum: a segment
              // whose own text wraps to N lines makes that ONE segment
              // taller, it does not add N separate rows to the run.
              runIntraLines.add(segRunIntraLines);
            }
            segRunWidth = 0.0;
            segRunHasChord = false;
            segRunHasLyric = false;
            segRunIntraLines = 1;
            segRunStarted = false;
          }

          for (final segment in group) {
            final segWidth = _segmentPixelWidth(
              segment,
              showChords,
              lyricCharWidth: lyricCharWidth,
              chordCharWidth: chordCharWidth,
              fontScale: fontScale,
            );
            final segHasChord = segment.displayChord != null;
            final segIntraLines = _segmentIntraLines(
              segment: segment,
              effectiveLineWidth: effectiveLineWidth,
              fontScale: fontScale,
              lyricCharWidth: lyricCharWidth,
            );

            // A segment wider than a whole run still occupies its own run
            // (it is never split further): the check below only closes an
            // already-started run, so a lone oversized segment is placed
            // into a fresh run regardless of its own width, and the next
            // segment then forces a new run in turn.
            if (segRunStarted && segRunWidth + segWidth > effectiveLineWidth) {
              flushSegRun();
            }
            if (segRunStarted) {
              segRunWidth += segWidth; // 0 spacing within the group
            } else {
              segRunStarted = true;
              segRunWidth = segWidth;
            }
            segRunHasChord = segRunHasChord || segHasChord;
            segRunHasLyric = segRunHasLyric || segmentHasLyric(segment);
            segRunIntraLines = segRunIntraLines > segIntraLines
                ? segRunIntraLines
                : segIntraLines;
          }
          flushSegRun();
          continue;
        }

        if (currentRunStarted &&
            currentRunWidth + interGroupSpacing + groupWidth >
                effectiveLineWidth) {
          flushRun();
        }
        if (currentRunStarted) {
          currentRunWidth += interGroupSpacing + groupWidth;
        } else {
          currentRunStarted = true;
          currentRunWidth = groupWidth;
        }
        currentRunHasChord = currentRunHasChord || groupHasChord;
        currentRunHasLyric = currentRunHasLyric || groupHasLyric;
      }
      flushRun();

      if (runHasChord.isEmpty) {
        // No groups at all (an empty segment list) -- still charge a blank
        // line's worth of height, matching the pre-existing "blank
        // separator line" convention (a Wrap with no children still takes
        // the space allotted by lineGap below; the extra lyric row here
        // preserves prior behavior for this edge case).
        runHasChord.add(false);
        runHasLyric.add(true);
        runIntraLines.add(1);
      }

      var runsHeight = 0.0;
      for (var i = 0; i < runHasChord.length; i++) {
        final lyricH = runHasLyric[i]
            ? runIntraLines[i] * lyricRowHeight * fontScale
            : 0.0;
        final chordH = (runHasChord[i] && showChords)
            ? (chordRowHeight * fontScale +
                  (runHasLyric[i] ? chordToLyricGap : 0.0))
            : 0.0;
        runsHeight += lyricH + chordH;
      }

      return runsHeight +
          (runHasChord.length - 1) * lineRunSpacing +
          lineGap +
          lineWidgetBottomPadding;
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
  double lyricCharWidth = characterWidthEstimate,
  double chordCharWidth = characterWidthEstimate,
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
        lyricCharWidth: lyricCharWidth,
        chordCharWidth: chordCharWidth,
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
  double lyricCharWidth = characterWidthEstimate,
  double chordCharWidth = characterWidthEstimate,
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
      lyricCharWidth: lyricCharWidth,
      chordCharWidth: chordCharWidth,
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
  double lyricCharWidth = characterWidthEstimate,
  double chordCharWidth = characterWidthEstimate,
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
          lyricCharWidth: lyricCharWidth,
          chordCharWidth: chordCharWidth,
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
  double lyricCharWidth = characterWidthEstimate,
  double chordCharWidth = characterWidthEstimate,
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
          lyricCharWidth: lyricCharWidth,
          chordCharWidth: chordCharWidth,
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
  double lyricCharWidth = characterWidthEstimate,
  double chordCharWidth = characterWidthEstimate,
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
          lyricCharWidth: lyricCharWidth,
          chordCharWidth: chordCharWidth,
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
    lyricCharWidth: lyricCharWidth,
    chordCharWidth: chordCharWidth,
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
  double lyricCharWidth = characterWidthEstimate,
  double chordCharWidth = characterWidthEstimate,
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
        lyricCharWidth: lyricCharWidth,
        chordCharWidth: chordCharWidth,
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
