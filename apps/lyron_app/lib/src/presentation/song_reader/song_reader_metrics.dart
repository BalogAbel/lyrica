import 'package:flutter/foundation.dart';

/// The string a section label is actually DRAWN as.
///
/// The estimator models this exact string (song_reader_fit.dart's
/// buildFlowBlocks and estimateSectionHeight), not the source label: uppercase
/// glyphs are wider, so modelling the source would under-count how many rows a
/// long label wraps into.
String songReaderSectionLabelText(String label, int? number) {
  final composed = number == null ? label : '$label $number';
  return composed.toUpperCase();
}

/// Layout metrics shared by the reader renderer and the fit estimator.
///
/// These live in ONE object because the estimator has to reproduce the
/// renderer's spacing exactly: a value the two sides define separately drifts
/// silently, and the drift shows up as `estimated < rendered`, which is the
/// overflow that fit-to-screen exists to prevent.
///
/// They used to be module-level `const double`s. They became a value object
/// when the type scale gained a 600px breakpoint (see
/// docs/specs/2026-08-09-song-presentation.md section 7): row heights and gaps
/// differ between the phone and the tablet/desktop set, so a compile-time
/// constant can no longer express them. The resolution happens in exactly one
/// place, `ReaderTheme.of(context)`, which both the renderer and
/// `measureSongReaderCharWidths` call with the same `BuildContext`.
@immutable
class SongReaderMetrics {
  const SongReaderMetrics({
    required this.lineRunSpacing,
    required this.chordOnlySpacing,
    required this.chordToLyricGap,
    required this.sectionGap,
    required this.sectionLabelRowHeight,
    required this.sectionLabelToLineGap,
    required this.lineGap,
    required this.chordRowHeight,
    required this.lyricRowHeight,
    required this.directiveLineHeight,
    required this.tabBlockVerticalPadding,
    required this.lineWidgetBottomPadding,
    required this.chordChipHorizontalPadding,
  });

  /// Vertical gap between runs of a lyric line's `Wrap`.
  ///
  /// Its MEANING changed in PR2 (#70) and its value follows in PR3. Before
  /// PR2 a single-segment line was one `Text` that wrapped internally at plain
  /// text leading, and this spacing only ever separated distinct `Wrap`
  /// children. Since PR2 a line is one box per word, so this spacing also
  /// lands between a single line's OWN wrapped rows. Measured on a 380px
  /// column, one wrapped lyric line went from 114px to 144px at the old value
  /// of 10.
  final double lineRunSpacing;

  /// Horizontal gap between the chord slots of a chord-only line (an
  /// instrumental bar), where there are no words to group.
  final double chordOnlySpacing;

  /// Vertical gap between a segment's chord label and its lyric text.
  final double chordToLyricGap;

  /// Vertical gap between two sections.
  final double sectionGap;

  /// Rendered height of one row of the section label ("Verse 1").
  final double sectionLabelRowHeight;

  /// Gap between a section's label and its first line.
  final double sectionLabelToLineGap;

  /// Gap after each content line inside a section.
  final double lineGap;

  /// Rendered height of one chord row.
  final double chordRowHeight;

  /// Rendered height of one lyric row.
  ///
  /// This must equal the lyric style's real rendered line height, i.e.
  /// `lyricStyle.fontSize * lyricStyle.height`. `ReaderTheme` derives the
  /// style's `height` from this value rather than the other way round, so the
  /// two cannot disagree.
  final double lyricRowHeight;

  /// Rendered height of one directive line (leading or inline).
  final double directiveLineHeight;

  /// Total vertical padding a tab block adds around its raw lines.
  final double tabBlockVerticalPadding;

  /// `SongLineView`'s own `Padding(padding: EdgeInsets.only(bottom: ...))`,
  /// charged once per lyric line because it is part of the widget's measured
  /// render height.
  ///
  /// Measured 2026-07-28: the "chord-only instrumental bar" per-line fixture
  /// rendered at 122px against an estimate of 120px, a 2px shortfall that
  /// reproduced exactly this padding. It is not a safety margin — it is the
  /// literal padding value the widget adds, charged once per lyric line.
  final double lineWidgetBottomPadding;

  /// Horizontal padding on EACH side of the chord chip.
  ///
  /// Zero means "no chip". Non-zero widens what a chord label occupies, so the
  /// estimator must charge `2 * chordChipHorizontalPadding` per drawn chord —
  /// otherwise a chord that wraps in the render does not wrap in the estimate.
  final double chordChipHorizontalPadding;

  /// What the estimator charges for one rendered row of a section label,
  /// including the gap that follows the label.
  double get headerHeight => sectionLabelRowHeight + sectionLabelToLineGap;

  /// The values in force before the metrics became a passed-in value.
  ///
  /// This is the default for every estimator function in
  /// `song_reader_fit.dart`, so pure unit tests that never construct a
  /// [SongReaderMetrics] keep their original meaning — the same technique
  /// `SongReaderFitTextScale.identity` uses.
  static const legacy = SongReaderMetrics(
    lineRunSpacing: 10.0,
    chordOnlySpacing: 22.0,
    chordToLyricGap: 2.0,
    sectionGap: 20.0,
    sectionLabelRowHeight: 28.0,
    sectionLabelToLineGap: 12.0,
    lineGap: 10.0,
    chordRowHeight: 20.0,
    lyricRowHeight: 24.0,
    directiveLineHeight: 36.0,
    tabBlockVerticalPadding: 16.0,
    lineWidgetBottomPadding: 2.0,
    chordChipHorizontalPadding: 0.0,
  );

  SongReaderMetrics copyWith({
    double? lineRunSpacing,
    double? chordOnlySpacing,
    double? chordToLyricGap,
    double? sectionGap,
    double? sectionLabelRowHeight,
    double? sectionLabelToLineGap,
    double? lineGap,
    double? chordRowHeight,
    double? lyricRowHeight,
    double? directiveLineHeight,
    double? tabBlockVerticalPadding,
    double? lineWidgetBottomPadding,
    double? chordChipHorizontalPadding,
  }) {
    return SongReaderMetrics(
      lineRunSpacing: lineRunSpacing ?? this.lineRunSpacing,
      chordOnlySpacing: chordOnlySpacing ?? this.chordOnlySpacing,
      chordToLyricGap: chordToLyricGap ?? this.chordToLyricGap,
      sectionGap: sectionGap ?? this.sectionGap,
      sectionLabelRowHeight:
          sectionLabelRowHeight ?? this.sectionLabelRowHeight,
      sectionLabelToLineGap:
          sectionLabelToLineGap ?? this.sectionLabelToLineGap,
      lineGap: lineGap ?? this.lineGap,
      chordRowHeight: chordRowHeight ?? this.chordRowHeight,
      lyricRowHeight: lyricRowHeight ?? this.lyricRowHeight,
      directiveLineHeight: directiveLineHeight ?? this.directiveLineHeight,
      tabBlockVerticalPadding:
          tabBlockVerticalPadding ?? this.tabBlockVerticalPadding,
      lineWidgetBottomPadding:
          lineWidgetBottomPadding ?? this.lineWidgetBottomPadding,
      chordChipHorizontalPadding:
          chordChipHorizontalPadding ?? this.chordChipHorizontalPadding,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SongReaderMetrics &&
        other.lineRunSpacing == lineRunSpacing &&
        other.chordOnlySpacing == chordOnlySpacing &&
        other.chordToLyricGap == chordToLyricGap &&
        other.sectionGap == sectionGap &&
        other.sectionLabelRowHeight == sectionLabelRowHeight &&
        other.sectionLabelToLineGap == sectionLabelToLineGap &&
        other.lineGap == lineGap &&
        other.chordRowHeight == chordRowHeight &&
        other.lyricRowHeight == lyricRowHeight &&
        other.directiveLineHeight == directiveLineHeight &&
        other.tabBlockVerticalPadding == tabBlockVerticalPadding &&
        other.lineWidgetBottomPadding == lineWidgetBottomPadding &&
        other.chordChipHorizontalPadding == chordChipHorizontalPadding;
  }

  @override
  int get hashCode => Object.hash(
    lineRunSpacing,
    chordOnlySpacing,
    chordToLyricGap,
    sectionGap,
    sectionLabelRowHeight,
    sectionLabelToLineGap,
    lineGap,
    chordRowHeight,
    lyricRowHeight,
    directiveLineHeight,
    tabBlockVerticalPadding,
    lineWidgetBottomPadding,
    chordChipHorizontalPadding,
  );
}
