import 'package:flutter/widgets.dart' show TextScaler;
import 'package:lyron_app/src/presentation/song_reader/song_reader_metrics.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_word_groups.dart';

/// Bundles the ambient [TextScaler] and the base (fontScale == 1.0, no
/// ambient scaling) point sizes of every text style this file's estimator
/// models, so every height/width formula below can compute the REAL
/// effective size multiplier at the actual rendered size instead of
/// flattening the scaler to a single ratio.
///
/// [TextScaler.scale] is not linear in general (Android 14+ "non-linear font
/// scaling" boosts small text more than large text, so the same scaler
/// yields a different ratio at 12px than at 22px). The old design measured
/// one ratio -- `textScaler.scale(1.0)`, evaluated at a 1px probe size --
/// and multiplied every quantity (row heights at wildly different base
/// sizes, character widths) by that single number. That is only correct for
/// a LINEAR scaler, where the ratio is the same at every size; under a
/// non-linear one it silently reproduces the exact "estimate below render"
/// failure resolveFitFontScale exists to prevent (see
/// [SongReaderCharWidths.lyricCharWidth] docs in song_reader_char_metrics.dart
/// for the char-width side of this).
///
/// [factorFor] instead evaluates the scaler at the CANDIDATE size
/// (`baseFontSize * fontScale`) for whichever style is being estimated, so
/// each style gets its own correct multiplier no matter how non-linear the
/// scaler is.
class SongReaderFitTextScale {
  const SongReaderFitTextScale({
    required this.textScaler,
    required this.lyricBaseFontSize,
    required this.chordBaseFontSize,
    required this.headerBaseFontSize,
    required this.inlineDirectiveBaseFontSize,
  });

  /// No ambient scaling, default Material 3 base sizes (`bodyLarge`,
  /// `labelLarge`, `titleLarge`, `labelMedium`). This is the default for
  /// every function in this file, so pure unit tests that never construct a
  /// [SongReaderFitTextScale] keep compiling and keep their original
  /// meaning: `TextScaler.noScaling` makes [factorFor] degenerate to plain
  /// `fontScale`, exactly the pre-non-linear-scaler behavior.
  static const identity = SongReaderFitTextScale(
    textScaler: TextScaler.noScaling,
    lyricBaseFontSize: 16.0,
    chordBaseFontSize: 14.0,
    headerBaseFontSize: 22.0,
    inlineDirectiveBaseFontSize: 12.0,
  );

  /// The ambient `MediaQuery.textScalerOf(context)` scaler in effect when
  /// this bundle was built.
  final TextScaler textScaler;

  /// `theme.textTheme.bodyLarge?.fontSize`, the lyric style's base size
  /// (song_line_view.dart's `lyricStyle`).
  final double lyricBaseFontSize;

  /// `theme.textTheme.labelLarge?.fontSize`, the chord style's base size
  /// (song_line_view.dart's `chordStyle`) -- also the leading capo/tuning
  /// directive's base size (song_reader_section_grid.dart's `_DirectiveLine`
  /// uses `labelLarge` too, just a different weight/color).
  final double chordBaseFontSize;

  /// `theme.textTheme.titleLarge?.fontSize`, the section header's base size
  /// (song_reader_section_grid.dart's `_buildHeaderWidget`).
  final double headerBaseFontSize;

  /// `theme.textTheme.labelMedium?.fontSize`, the INLINE directive line's
  /// base size (widgets/directive_line_view.dart's `DirectiveLineView`,
  /// rendered for a directive that appears inside a section rather than the
  /// leading capo/tuning line).
  final double inlineDirectiveBaseFontSize;

  /// Effective size multiplier for a style whose base (fontScale == 1.0, no
  /// ambient scaling) point size is [baseFontSize], when the in-app font
  /// control is at [fontScale]. Replaces the old `fontScale *
  /// ambientTextScaleRatio` flattening: [TextScaler.scale] is evaluated at
  /// the REAL rendered size (`baseFontSize * fontScale`), not at a fixed
  /// 1px probe, so a non-linear scaler is honored at every style's actual
  /// size instead of being collapsed to its ratio near zero.
  ///
  /// Pass `fontScale: 1.0` for styles the renderer never scales by the
  /// in-app font control (the section header and the leading directive
  /// line neither apply `sharedFontScale` to their `TextStyle` -- see
  /// song_reader_section_grid.dart) so the factor reflects only the ambient
  /// scaler, matching what actually renders.
  double factorFor(double baseFontSize, double fontScale) {
    if (baseFontSize <= 0) return fontScale;
    return textScaler.scale(baseFontSize * fontScale) / baseFontSize;
  }
}

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
    this.blockText,
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

  /// The real displayed text for [FlowBlockKind.sectionHeader] (the
  /// section's label, exactly as `_buildHeaderWidget`
  /// (song_reader_section_grid.dart) renders it) or
  /// [FlowBlockKind.leadingDirective] (the leading capo/tuning string,
  /// exactly as `_DirectiveLine` renders it) -- null for every other kind,
  /// and null when a caller constructs a [FlowBlock] directly without going
  /// through [buildFlowBlocks] (in which case [flowBlockHeight] falls back
  /// to treating the block as exactly one line, matching this file's
  /// pre-word-wrap behavior so existing direct-construction tests are
  /// unaffected). [flowBlockHeight] uses this to model these two kinds'
  /// real word-wrap growth instead of assuming a flat one-line constant.
  final String? blockText;
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
///
/// [leadingDirectiveText] is optional and purely additive: pass the real
/// leading-directive string (e.g. a song's capo/tuning line) so
/// [flowBlockHeight] can model its real word-wrap growth; omit it (or pass
/// `hasLeadingDirective: true` with no text, as every pre-existing caller
/// does) to keep the old flat-height behavior for that block.
List<FlowBlock> buildFlowBlocks({
  required List<SongReaderSectionProjection> sections,
  required bool hasLeadingDirective,
  String? leadingDirectiveText,
}) {
  final result = <FlowBlock>[];

  if (hasLeadingDirective) {
    result.add(
      FlowBlock(
        kind: FlowBlockKind.leadingDirective,
        sectionIndex: -1,
        blockText: leadingDirectiveText,
      ),
    );
  }

  for (var i = 0; i < sections.length; i++) {
    final section = sections[i];
    final hasHeader = !(section.label == 'Unlabeled' && section.number == null);

    if (hasHeader) {
      // Mirrors song_reader_section_grid.dart's `_sectionLabel`.
      final headerLabel = section.number == null
          ? section.label
          : '${section.label} ${section.number}';
      // The header block is the section start; it carries sectionGap.
      result.add(
        FlowBlock(
          kind: FlowBlockKind.sectionHeader,
          sectionIndex: i,
          isSectionStart: true,
          blockText: headerLabel,
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
  required double lyricFactor,
  required double chordFactor,
}) {
  final lyricWidth = segment.text.length * lyricCharWidth * lyricFactor;
  final chordWidth = (showChords && segment.displayChord != null)
      ? segment.displayChord!.length * chordCharWidth * chordFactor
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
  required double lyricFactor,
  required double lyricCharWidth,
}) {
  final text = segment.text;
  if (text.isEmpty) return 1;
  return _wordWrapLineCount(
    text: text,
    effectiveLineWidth: effectiveLineWidth,
    charWidth: lyricCharWidth * lyricFactor,
  );
}

/// Number of visual lines greedy word-boundary wrapping breaks [text] into
/// at [effectiveLineWidth], given a flat per-character advance of
/// [charWidth]. Shared by every kind of text this file estimates that DOES
/// break at word boundaries in the real render: the lyric segment
/// ([_segmentIntraLines]), a comment line, and a directive line (both the
/// inline and the leading capo/tuning variant) -- see each call site's own
/// comment for why THAT kind uses this word-boundary model rather than the
/// even-division model `_segmentRowHeight` uses for a chord label (which
/// has no reliable word boundaries in the general case).
///
/// Splits on spaces and greedily packs whole words onto a line, starting a
/// new line whenever the next word would overflow. A single word wider
/// than a whole line is placed on its own and spans
/// `ceil(wordWidth / effectiveLineWidth)` lines by itself (mirroring how a
/// single unbreakable token still gets clipped into multiple lines by
/// `Text`'s own line-breaking, since there is no word boundary inside it to
/// break at). A plain `ceil(textWidth / effectiveLineWidth)` division would
/// undercount: it lets a wrap point fall in the middle of a word, packing
/// more characters onto a line than real layout would allow, which pushes
/// the estimate below the rendered height -- exactly backwards for
/// `resolveFitFontScale`, which must never choose a scale whose estimated
/// height is less than what actually renders.
int _wordWrapLineCount({
  required String text,
  required double effectiveLineWidth,
  required double charWidth,
}) {
  if (text.isEmpty) return 1;

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

/// Estimated pixel height a single [segment] occupies within its run, at
/// [effectiveLineWidth] and the given per-style factors: `chordRows *
/// chordRowHeight (+ the chord-to-lyric gap when it has both) + lyricLines
/// * lyricRowHeight`.
///
/// Mirrors `_SongLineSegmentView` (song_line_view.dart): its `Column` (chord
/// `Text`, optional gap, lyric `Text`) is a direct or indirect child of a
/// `Wrap`, and `RenderWrap` constrains EVERY child's main-axis size to its
/// own `constraints.maxWidth` regardless of whether that child wraps its
/// own content in an explicit `ConstrainedBox` (see
/// `RenderWrap._computeRuns` in the Flutter SDK: `BoxConstraints(maxWidth:
/// constraints.maxWidth)` is applied uniformly to every child). So the
/// chord `Text` -- despite having no `ConstrainedBox` of its own in
/// `_SongLineSegmentView` -- still gets squeezed to at most
/// [effectiveLineWidth] by the `Wrap` itself, and wraps internally onto a
/// second (or further) line when the label is wider than that, growing the
/// segment taller. This was found to be reachable in practice: a ten-plus
/// character extended/slash chord (e.g. "Cmaj7#11") at a 14px base size,
/// under a non-linear scaler near its peak boost and a raised in-app
/// `sharedFontScale`, comfortably exceeds a 375px phone's content width.
///
/// Unlike [_segmentIntraLines] (the lyric text's own wrap count), the chord
/// label is modelled with a plain `ceil(chordWidth / effectiveLineWidth)`
/// division rather than a word-boundary-aware greedy pack: a chord label is
/// a single token with no spaces to break on in the general case (extended/
/// slash chords like "Cmaj7#11" or "Bbsus4/D" have no word boundaries a
/// line-breaking algorithm would reliably use the way lyric text's spaces
/// provide them), so an even division is the right model here, mirroring
/// exactly how [_segmentIntraLines] already treats a single lyric word wider
/// than a whole line (`ceil(wordWidth / effectiveLineWidth)`).
double _segmentRowHeight({
  required SongReaderSegmentProjection segment,
  required bool showChords,
  required double effectiveLineWidth,
  required double lyricCharWidth,
  required double chordCharWidth,
  required double lyricFactor,
  required double chordFactor,
}) {
  final hasChord = showChords && segment.displayChord != null;
  final hasLyric = segment.text.isNotEmpty;

  final lyricLines = hasLyric
      ? _segmentIntraLines(
          segment: segment,
          effectiveLineWidth: effectiveLineWidth,
          lyricFactor: lyricFactor,
          lyricCharWidth: lyricCharWidth,
        )
      : 0;

  var chordRows = 0;
  if (hasChord) {
    final chordWidth =
        segment.displayChord!.length * chordCharWidth * chordFactor;
    chordRows = effectiveLineWidth > 0
        ? (chordWidth / effectiveLineWidth).ceil()
        : 1;
    if (chordRows < 1) chordRows = 1;
  }

  final chordH = chordRows * chordRowHeight * chordFactor;
  final lyricH = lyricLines * lyricRowHeight * lyricFactor;
  final gap = (hasChord && hasLyric) ? chordToLyricGap : 0.0;
  return chordH + gap + lyricH;
}

double _lineItemHeight({
  required SongReaderSectionItemProjection item,
  required SongReaderViewMode viewMode,
  required double columnWidth,
  required double fontScale,
  double lyricCharWidth = characterWidthEstimate,
  double chordCharWidth = characterWidthEstimate,
  SongReaderFitTextScale textScale = SongReaderFitTextScale.identity,
}) {
  final effectiveLineWidth = columnWidth.clamp(120.0, 1200.0);
  // Both lyricCharWidth and chordCharWidth are measured RAW (no ambient
  // scaler baked in, see measureSongReaderCharWidths) at each style's own
  // base size, so every quantity derived from them needs the REAL effective
  // factor at that style's base size and the candidate fontScale -- not a
  // single flattened ambient ratio applied uniformly (see
  // SongReaderFitTextScale doc for why that breaks under a non-linear
  // scaler). lyricFactor and chordFactor differ whenever the scaler is
  // non-linear, since the lyric and chord styles have different base sizes.
  final lyricFactor = textScale.factorFor(
    textScale.lyricBaseFontSize,
    fontScale,
  );
  final chordFactor = textScale.factorFor(
    textScale.chordBaseFontSize,
    fontScale,
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

      // Per run: the pixel height contributed by its TALLEST segment (Wrap
      // sizes a run to its tallest child), via _segmentRowHeight -- which
      // combines that ONE segment's own chord-row count, lyric-wrap count,
      // and the gap between them, rather than separately maxing "chord rows
      // across the run" and "lyric lines across the run" and summing those
      // maxes (max(a)+max(b) can exceed max(a+b) when the tallest-chord
      // segment and the tallest-lyric segment in a run are different
      // segments, over-stating the run's real height). Tracking one
      // per-segment total and maxing THAT over the run matches what Wrap
      // actually measures: the size of its single tallest child.
      var runHeights = <double>[];
      var currentRunWidth = 0.0;
      var currentRunMaxHeight = 0.0;
      var currentRunStarted = false;

      void flushRun() {
        if (currentRunStarted) {
          runHeights.add(currentRunMaxHeight);
        }
        currentRunWidth = 0.0;
        currentRunMaxHeight = 0.0;
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
                lyricFactor: lyricFactor,
                chordFactor: chordFactor,
              ),
        );

        if (groupWidth > effectiveLineWidth) {
          // This group alone won't fit in one run. It starts on a fresh run
          // (flushRun below closes whatever run was already in progress),
          // then its own segments are packed the way the renderer's inner
          // Wrap packs them: greedily, with 0 spacing between segments in
          // the same group (song_line_view.dart's inner Wrap uses
          // spacing: 0).
          flushRun();

          var segRunWidth = 0.0;
          var segRunMaxHeight = 0.0;
          var segRunStarted = false;

          void flushSegRun() {
            if (segRunStarted) {
              runHeights.add(segRunMaxHeight);
            }
            segRunWidth = 0.0;
            segRunMaxHeight = 0.0;
            segRunStarted = false;
          }

          for (final segment in group) {
            final segWidth = _segmentPixelWidth(
              segment,
              showChords,
              lyricCharWidth: lyricCharWidth,
              chordCharWidth: chordCharWidth,
              lyricFactor: lyricFactor,
              chordFactor: chordFactor,
            );
            final segHeight = _segmentRowHeight(
              segment: segment,
              showChords: showChords,
              effectiveLineWidth: effectiveLineWidth,
              lyricCharWidth: lyricCharWidth,
              chordCharWidth: chordCharWidth,
              lyricFactor: lyricFactor,
              chordFactor: chordFactor,
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
            segRunMaxHeight = segRunMaxHeight > segHeight
                ? segRunMaxHeight
                : segHeight;
          }
          flushSegRun();
          continue;
        }

        // The group is NOT over-wide, so (since widths are non-negative and
        // sum to at most effectiveLineWidth) every one of its segments'
        // own widths -- lyric width AND chord width alike -- is
        // individually <= effectiveLineWidth too, meaning _segmentRowHeight
        // below can never compute more than 1 chord row or 1 lyric line
        // for any of them here. Calling the same helper uniformly (rather
        // than assuming "always 1" and skipping the call, as an earlier
        // version of this function did) keeps this branch and the
        // over-wide branch above trivially consistent without a second,
        // parallel "assume 1" formula to keep in sync.
        final groupHeight = group.fold<double>(0.0, (max, s) {
          final h = _segmentRowHeight(
            segment: s,
            showChords: showChords,
            effectiveLineWidth: effectiveLineWidth,
            lyricCharWidth: lyricCharWidth,
            chordCharWidth: chordCharWidth,
            lyricFactor: lyricFactor,
            chordFactor: chordFactor,
          );
          return max > h ? max : h;
        });

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
        currentRunMaxHeight = currentRunMaxHeight > groupHeight
            ? currentRunMaxHeight
            : groupHeight;
      }
      flushRun();

      if (runHeights.isEmpty) {
        // No groups at all (an empty segment list) -- still charge a blank
        // line's worth of height, matching the pre-existing "blank
        // separator line" convention (a Wrap with no children still takes
        // the space allotted by lineGap below; the extra lyric row here
        // preserves prior behavior for this edge case).
        runHeights = [lyricRowHeight * lyricFactor];
      }

      final runsHeight = runHeights.fold<double>(0.0, (a, b) => a + b);

      return runsHeight +
          (runHeights.length - 1) * lineRunSpacing +
          lineGap +
          lineWidgetBottomPadding;
    case SongReaderCommentProjection():
      // CommentLineView (widgets/comment_line_view.dart) renders at
      // `theme.textTheme.bodyMedium` (14px, italic), scaled by
      // `sharedFontScale` the same way the lyric style is -- it sits
      // directly in the section grid's Column (no ConstrainedBox of its
      // own, but the Column gives it the full available width, exactly
      // like a lyric segment's own Text), so it wraps at WORD boundaries
      // in the real render. A plain character-count division (the old
      // formula here) undercounts wraps the same way the lyric
      // char-count division used to, for the same reason: it lets a
      // wrap point fall mid-word.
      //
      // No bodyMedium char width is separately measured; lyricCharWidth
      // (bodyLarge, 16px) is reused here as a deliberately conservative
      // proxy: 16px characters are WIDER than the real 14px comment
      // text, so this can only ever fit FEWER real characters per
      // estimated line than the comment text truly allows -- over-
      // counting wrapped lines, never under-counting. The per-wrapped-
      // line height charge (`lyricRowHeight`) is the SAME pre-existing
      // reuse of the lyric row constant this file has always used for
      // comment lines; only the WRAP COUNT changes here, from a flat
      // division to real word-boundary wrapping.
      final commentWrapCount = _wordWrapLineCount(
        text: item.text,
        effectiveLineWidth: effectiveLineWidth,
        charWidth: lyricCharWidth * lyricFactor,
      );
      return commentWrapCount * (lyricRowHeight * lyricFactor) + lineGap;
    case SongReaderTabProjection():
      // TabBlockView (widgets/tab_block_view.dart) draws its raw lines
      // inside a `SingleChildScrollView(scrollDirection: Axis.horizontal)`:
      // a tab line SCROLLS rather than wraps, no matter how long it is or
      // how narrow the column is (proven by
      // song_reader_block_estimate_consistency_test.dart's "several LONG
      // tab lines at a narrow width" case), so one estimated row per raw
      // line -- with no word-wrap or even-division growth possible -- is
      // already exact, not an approximation to tighten.
      return item.rawLines.length * (lyricRowHeight * lyricFactor) +
          lineGap +
          tabBlockVerticalPadding;
    case SongReaderDirectiveProjection():
      // DirectiveLineView (widgets/directive_line_view.dart) renders this
      // INLINE directive at `theme.textTheme.labelMedium`, with no
      // `sharedFontScale` applied to its `TextStyle` -- so, like the
      // section header below, the factor uses a FIXED fontScale of 1.0:
      // only the ambient scaler affects this style's rendered size. Its
      // Text sits directly in the grid's Column (full available width),
      // so it wraps at WORD boundaries like comment/lyric text, not the
      // chord label's even-division model.
      //
      // No labelMedium char width is separately measured; chordCharWidth
      // (labelLarge, 14px, `w700`) is reused as a deliberately
      // conservative proxy for the same reason comment reuses
      // lyricCharWidth above: labelMedium is smaller (12px) and
      // lighter-weight than labelLarge+w700, so chordCharWidth can only
      // ever fit FEWER real characters per line than the real render
      // allows, over-counting wrapped lines rather than under-counting.
      final inlineDirectiveFactor = textScale.factorFor(
        textScale.inlineDirectiveBaseFontSize,
        1.0,
      );
      final chordFactorAt1 = textScale.factorFor(
        textScale.chordBaseFontSize,
        1.0,
      );
      // Mirrors DirectiveLineView's exact display string -- the curly
      // braces and separator are real rendered characters too, not just
      // the raw name/value.
      final directiveLabel = item.value != null
          ? '{${item.name}: ${item.value}}'
          : '{${item.name}}';
      final inlineDirectiveLines = _wordWrapLineCount(
        text: directiveLabel,
        effectiveLineWidth: effectiveLineWidth,
        charWidth: chordCharWidth * chordFactorAt1,
      );
      return inlineDirectiveLines * directiveLineHeight * inlineDirectiveFactor;
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
  double headerCharWidth = characterWidthEstimate,
  SongReaderFitTextScale textScale = SongReaderFitTextScale.identity,
}) {
  final effectiveLineWidth = columnWidth.clamp(120.0, 1200.0);

  switch (block.kind) {
    case FlowBlockKind.leadingDirective:
      // _DirectiveLine (song_reader_section_grid.dart) renders the leading
      // capo/tuning directive at `theme.textTheme.labelLarge` -- the same
      // base size as the chord style, just a different weight/color -- and
      // applies no `sharedFontScale` to its `TextStyle`, so (like the
      // section header below) the factor is fixed at fontScale 1.0: only
      // the ambient scaler affects this style's rendered size. Its Text
      // sits directly in the grid's Column (full available width), so it
      // wraps at WORD boundaries, not the chord label's even-division
      // model -- same reasoning as the inline directive
      // (_lineItemHeight's SongReaderDirectiveProjection case), including
      // reusing chordCharWidth as a deliberately conservative width proxy
      // (labelLarge+w700 is bolder than this style's actual w600, so it
      // can only ever fit fewer real characters per line, over-counting
      // wrapped lines rather than under-counting).
      //
      // `block.blockText` is null when a caller constructs this FlowBlock
      // directly rather than via buildFlowBlocks (every pre-existing test
      // that predates word-wrap modelling here does exactly that) --
      // _wordWrapLineCount(text: '', ...) degrades to exactly 1 line in
      // that case, reproducing the old flat-constant formula exactly, so
      // those callers are unaffected.
      final leadingDirectiveFactor = textScale.factorFor(
        textScale.chordBaseFontSize,
        1.0,
      );
      final leadingDirectiveLines = _wordWrapLineCount(
        text: block.blockText ?? '',
        effectiveLineWidth: effectiveLineWidth,
        charWidth: chordCharWidth * leadingDirectiveFactor,
      );
      return leadingDirectiveLines *
              directiveLineHeight *
              leadingDirectiveFactor +
          sectionGap;
    case FlowBlockKind.sectionHeader:
      // _buildHeaderWidget (song_reader_section_grid.dart) renders at
      // `theme.textTheme.titleLarge`, also never scaled by
      // `sharedFontScale` -- fontScale fixed at 1.0, ambient-only factor.
      // Its Text sits directly in the grid's Column too, so it wraps at
      // word boundaries -- a section label CAN be long in practice (a
      // ChordPro `start_of_verse`-style directive can carry an arbitrary
      // custom label), so this is not a hypothetical. `headerCharWidth` is
      // titleLarge's own real measurement (see
      // SongReaderCharWidths.headerCharWidth doc for why, unlike the
      // directive kinds, no existing measurement is a safe proxy here:
      // 22px header text is LARGER than every other measured style, so
      // reusing a smaller one would UNDER-count, not over-count).
      // sectionGap is charged here (see gap-accounting note above).
      //
      // `block.blockText` null (direct FlowBlock construction, as every
      // pre-existing test does) degrades to exactly 1 line, same as
      // above.
      final headerFactor = textScale.factorFor(
        textScale.headerBaseFontSize,
        1.0,
      );
      final headerLines = _wordWrapLineCount(
        text: block.blockText ?? '',
        effectiveLineWidth: effectiveLineWidth,
        charWidth: headerCharWidth * headerFactor,
      );
      return headerLines * headerHeight * headerFactor + sectionGap;
    case FlowBlockKind.line:
      final lineH = _lineItemHeight(
        item: block.line!,
        viewMode: viewMode,
        columnWidth: columnWidth,
        fontScale: fontScale,
        lyricCharWidth: lyricCharWidth,
        chordCharWidth: chordCharWidth,
        textScale: textScale,
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
  double headerCharWidth = characterWidthEstimate,
  SongReaderFitTextScale textScale = SongReaderFitTextScale.identity,
}) {
  final hasHeader = !(section.label == 'Unlabeled' && section.number == null);
  // Kept consistent with flowBlockHeight's FlowBlockKind.sectionHeader case
  // (see that doc for why a section label needs word-wrap modelling, not a
  // flat constant): mirrors song_reader_section_grid.dart's `_sectionLabel`.
  double h;
  if (hasHeader) {
    final headerLabel = section.number == null
        ? section.label
        : '${section.label} ${section.number}';
    final headerFactor = textScale.factorFor(textScale.headerBaseFontSize, 1.0);
    final headerLines = _wordWrapLineCount(
      text: headerLabel,
      effectiveLineWidth: maxWidth.clamp(120.0, 1200.0),
      charWidth: headerCharWidth * headerFactor,
    );
    h = headerLines * headerHeight * headerFactor;
  } else {
    h = 0.0;
  }
  var linesHeight = 0.0;
  for (final item in section.lines) {
    linesHeight += _lineItemHeight(
      item: item,
      viewMode: viewMode,
      columnWidth: maxWidth,
      fontScale: fontScale,
      lyricCharWidth: lyricCharWidth,
      chordCharWidth: chordCharWidth,
      textScale: textScale,
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
  double headerCharWidth = characterWidthEstimate,
  SongReaderFitTextScale textScale = SongReaderFitTextScale.identity,
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
          headerCharWidth: headerCharWidth,
          textScale: textScale,
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
  String? leadingDirectiveText,
  double lyricCharWidth = characterWidthEstimate,
  double chordCharWidth = characterWidthEstimate,
  double headerCharWidth = characterWidthEstimate,
  SongReaderFitTextScale textScale = SongReaderFitTextScale.identity,
}) {
  final blocks = buildFlowBlocks(
    sections: sections,
    hasLeadingDirective: hasLeadingDirective,
    leadingDirectiveText: leadingDirectiveText,
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
          headerCharWidth: headerCharWidth,
          textScale: textScale,
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
  String? leadingDirectiveText,
  double lyricCharWidth = characterWidthEstimate,
  double chordCharWidth = characterWidthEstimate,
  double headerCharWidth = characterWidthEstimate,
  SongReaderFitTextScale textScale = SongReaderFitTextScale.identity,
}) {
  // Single-column total: blocks at full width.
  //
  // [leadingDirectiveText] is the real leading-directive string (so
  // flowBlockHeight can model its word-wrap growth instead of assuming a
  // flat one line); [leadingDirectiveHeight] is the older, purely additive
  // way callers signalled "there IS a leading directive" without giving
  // its text (every pre-existing caller does this, so `hasLeadingDirective`
  // must stay true for them even though `leadingDirectiveText` is null).
  final hasLeadingDirective =
      (leadingDirectiveText != null && leadingDirectiveText.isNotEmpty) ||
      leadingDirectiveHeight > 0;
  final singleBlocks = buildFlowBlocks(
    sections: sections,
    hasLeadingDirective: hasLeadingDirective,
    leadingDirectiveText: leadingDirectiveText,
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
          headerCharWidth: headerCharWidth,
          textScale: textScale,
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
    leadingDirectiveText: leadingDirectiveText,
    lyricCharWidth: lyricCharWidth,
    chordCharWidth: chordCharWidth,
    headerCharWidth: headerCharWidth,
    textScale: textScale,
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
  String? leadingDirectiveText,
  double lyricCharWidth = characterWidthEstimate,
  double chordCharWidth = characterWidthEstimate,
  double headerCharWidth = characterWidthEstimate,
  SongReaderFitTextScale textScale = SongReaderFitTextScale.identity,
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
        leadingDirectiveText: leadingDirectiveText,
        lyricCharWidth: lyricCharWidth,
        chordCharWidth: chordCharWidth,
        headerCharWidth: headerCharWidth,
        textScale: textScale,
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
