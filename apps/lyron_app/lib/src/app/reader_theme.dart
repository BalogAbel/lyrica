// apps/lyron_app/lib/src/app/reader_theme.dart
import 'package:flutter/material.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_metrics.dart';

/// Below this width the reader uses the compact (phone) type scale; at or
/// above it, the regular (tablet/desktop) set.
///
/// This is the third width threshold in the reader, alongside
/// `denseLayoutMinWidth` (1180, two-column content) and the expanded shell's
/// 1600 — see song_reader_fit.dart and song_reader_layout.dart. All three key
/// off viewport WIDTH, deliberately, rather than one of them measuring
/// `shortestSide`. 600 is also Material 3's own phone/tablet boundary.
const double readerRegularTypeScaleMinWidth = 600.0;

/// Font sizes for one breakpoint, shared by [ReaderTheme.stageLight] and
/// [ReaderTheme.stageDark] so light and dark cannot diverge on the type
/// scale the same way [_readerMetrics] already keeps them from diverging on
/// row heights and gaps.
typedef _ReaderFontSizes = ({double lyric, double chord, double sectionLabel});

_ReaderFontSizes _readerFontSizes({required bool compact}) {
  return (
    lyric: compact ? 19.0 : 22.0,
    chord: compact ? 13.0 : 15.0,
    sectionLabel: compact ? 13.0 : 15.0,
  );
}

/// Builds the row heights and gaps for one breakpoint, shared by
/// [ReaderTheme.stageLight] and [ReaderTheme.stageDark] so light and dark
/// cannot diverge on layout.
///
/// See docs/specs/2026-08-09-song-presentation.md section 1 for the spec
/// table these values come from.
SongReaderMetrics _readerMetrics({required bool compact}) {
  return SongReaderMetrics(
    // Between the wrapped rows of ONE lyric line since the word-boundary
    // wrapping change (#70), not only between distinct Wrap children -- 10
    // here cost ~20-30px per wrapped line on a phone, where wrapping is the
    // normal state. Measured on a 380px column, one wrapped lyric line went
    // from 114px to 144px. Not 0: the lyric leading is now 24/22 ~= 1.09
    // (against 1.25 before), so wrapped rows would nearly touch. At 2 a
    // continuation row sits 26px below its own line against 24 + 6 = 30px to
    // the next line, keeping the hierarchy readable.
    lineRunSpacing: 2.0,
    chordOnlySpacing: 22.0,
    chordToLyricGap: 0.0,
    sectionGap: 14.0,
    sectionLabelRowHeight: compact ? 18.0 : 20.0,
    sectionLabelToLineGap: 4.0,
    lineGap: 6.0,
    chordRowHeight: compact ? 16.0 : 18.0,
    lyricRowHeight: compact ? 21.0 : 24.0,
    directiveLineHeight: 36.0,
    tabBlockVerticalPadding: 16.0,
    lineWidgetBottomPadding: 2.0,
    chordChipHorizontalPadding: 3.0,
  );
}

/// Colours and text styles for the song reader's content surface, resolved
/// for one breakpoint.
///
/// The reader's renderer and its fit estimator must describe the *same* text
/// styles: `measureSongReaderCharWidths` measures the styles the reader draws
/// with and feeds the result into an estimate that must never fall below the
/// rendered height. Before this extension existed they agreed only by
/// convention — `song_line_view.dart` and `song_reader_char_metrics.dart` each
/// re-derived `labelLarge + w700` / `bodyLarge + height: 1.25` by hand. Reading
/// both from one object makes that agreement structural.
///
/// This class is no longer the registered `ThemeExtension` itself — see
/// [ReaderThemeSet], which holds a `compact`/`regular` pair of these and is
/// what `app_theme.dart` registers. `ReaderTheme` is the token bundle already
/// resolved for one breakpoint.
@immutable
class ReaderTheme {
  const ReaderTheme({
    required this.lyricStyle,
    required this.chordStyle,
    required this.chordChipColor,
    required this.sectionLabelStyle,
    required this.unknownSectionLabelColor,
    required this.commentStyle,
    required this.directiveStyle,
    required this.leadingDirectiveStyle,
    required this.tabStyle,
    required this.tabBackgroundColor,
    required this.metrics,
  });

  /// Lyric text. Font size is the BASE size; the reader multiplies it by
  /// `sharedFontScale` at render time and the estimator converts it with
  /// `SongReaderFitTextScale.factorFor`.
  final TextStyle lyricStyle;

  /// Chord label text, at its base size.
  final TextStyle chordStyle;

  /// Background fill behind a chord label, or null for no fill.
  ///
  /// Non-null in both themes, since PR3: a filled, low-contrast chip (spec
  /// section 2). Null remains a valid value -- a `ThemeData` with no chip
  /// colour renders the bare label, exactly as before PR3 -- so the renderer
  /// and the estimator agree from a single source about whether a chip
  /// exists at all.
  final Color? chordChipColor;

  /// Section header label ("Verse 1"), at its base size.
  final TextStyle sectionLabelStyle;

  /// Label colour for a section whose kind the parser did not recognise.
  final Color unknownSectionLabelColor;

  /// Comment line ({comment: ...}) text, at its base size.
  final TextStyle commentStyle;

  /// Inline directive line text.
  final TextStyle directiveStyle;

  /// The leading directive line rendered above the first section (capo).
  final TextStyle leadingDirectiveStyle;

  /// Tab block text. Monospaced; the block scrolls horizontally rather than
  /// wrapping.
  final TextStyle tabStyle;

  /// Tab block container fill.
  final Color tabBackgroundColor;

  /// Row heights and gaps for this token set's breakpoint.
  ///
  /// Spacing lives here, alongside the type scale it has to match, because
  /// the 600px breakpoint makes it width-dependent — see ADR-033, which was
  /// amended for exactly this. [ReaderTheme.stageLight] and
  /// [ReaderTheme.stageDark] both build their metrics through the same
  /// private `_readerMetrics` helper, and `reader_theme_test.dart` pins light
  /// and dark to identical metrics for a given `compact`, so the two themes
  /// can never disagree about layout — only about colour.
  final SongReaderMetrics metrics;

  /// Builds the light theme's reader tokens exactly as the reader widgets
  /// derived them from a Material 3 theme before this class existed. Used
  /// for the light theme, and as the fallback for any `ThemeData` that has
  /// not registered the extension (notably widget tests that pump a bare
  /// `MaterialApp`), so that such a tree renders identically to how it did
  /// before.
  factory ReaderTheme.stageLight({
    required ColorScheme colorScheme,
    required TextTheme textTheme,
    required bool compact,
  }) {
    final metrics = _readerMetrics(compact: compact);
    final fontSizes = _readerFontSizes(compact: compact);
    final lyricFontSize = fontSizes.lyric;
    final chordFontSize = fontSizes.chord;
    final labelFontSize = fontSizes.sectionLabel;

    return ReaderTheme(
      // height is DERIVED, never typed as a separate literal: the estimator
      // charges lyricRowHeight per rendered row, and a Text's real row
      // height is fontSize * height. Two independent literals here is
      // exactly the drift that puts the estimate below the render.
      lyricStyle: textTheme.bodyLarge!.copyWith(
        fontSize: lyricFontSize,
        height: metrics.lyricRowHeight / lyricFontSize,
        fontWeight: FontWeight.w500,
      ),
      chordStyle: textTheme.labelLarge!.copyWith(
        fontSize: chordFontSize,
        height: metrics.chordRowHeight / chordFontSize,
        fontWeight: FontWeight.w700,
        color: colorScheme.primary,
      ),
      // Spec section 2: a filled, low-contrast chip in BOTH themes. A solid
      // saturated chip on the dark page would be the brightest thing on
      // screen, pulling the eye off the words being sung.
      chordChipColor: colorScheme.primary.withValues(alpha: 0.13),
      sectionLabelStyle: textTheme.titleLarge!.copyWith(
        fontSize: labelFontSize,
        height: metrics.sectionLabelRowHeight / labelFontSize,
        fontWeight: FontWeight.w700,
        // Spec section 3: 0.07em, expressed in logical px because Flutter's
        // letterSpacing is absolute.
        letterSpacing: labelFontSize * 0.07,
        color: colorScheme.primary,
      ),
      unknownSectionLabelColor: colorScheme.tertiary,
      commentStyle: textTheme.bodyMedium!.copyWith(
        fontStyle: FontStyle.italic,
        color: colorScheme.onSurface.withValues(alpha: 0.55),
        height: 1.4,
      ),
      directiveStyle: textTheme.labelMedium!.copyWith(
        color: colorScheme.tertiary,
        fontWeight: FontWeight.w500,
      ),
      leadingDirectiveStyle: textTheme.labelLarge!.copyWith(
        color: colorScheme.primary,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.02,
      ),
      tabStyle: TextStyle(
        fontFamily: 'monospace',
        fontSize: 13,
        height: 1.5,
        color: colorScheme.onSurface,
      ),
      tabBackgroundColor: colorScheme.surfaceContainerHighest,
      metrics: metrics,
    );
  }

  /// The dark theme's reader palette, designed for a dim stage.
  ///
  /// Not an inversion of the light palette. Two measurements drove it:
  /// lifting the page off pure black reduced emitted light by 0% (the light
  /// comes from the text, not the background), while dropping the text from
  /// #E8E6DD to #CDCAC0 cut relative text luminance from 79% to 59% and still
  /// leaves 12.8:1 contrast. And the light theme's #0B6E4F sits near 2:1 on
  /// black, so the accent needs its own value rather than an inversion.
  /// See docs/specs/2026-08-09-song-presentation.md.
  factory ReaderTheme.stageDark({
    required TextTheme textTheme,
    required bool compact,
  }) {
    const lyricColor = Color(0xFFCDCAC0);
    const chordColor = Color(0xFF7ACFA8);
    const sectionLabelColor = Color(0xFF6FA98D);
    const unknownSectionColor = Color(0xFFD8B892);

    final metrics = _readerMetrics(compact: compact);
    final fontSizes = _readerFontSizes(compact: compact);
    final lyricFontSize = fontSizes.lyric;
    final chordFontSize = fontSizes.chord;
    final labelFontSize = fontSizes.sectionLabel;

    return ReaderTheme(
      // height is DERIVED, never typed as a separate literal — see the
      // matching comment in stageLight.
      lyricStyle: textTheme.bodyLarge!.copyWith(
        fontSize: lyricFontSize,
        height: metrics.lyricRowHeight / lyricFontSize,
        fontWeight: FontWeight.w500,
        color: lyricColor,
      ),
      chordStyle: textTheme.labelLarge!.copyWith(
        fontSize: chordFontSize,
        height: metrics.chordRowHeight / chordFontSize,
        fontWeight: FontWeight.w700,
        color: chordColor,
      ),
      // Spec section 2: a filled, low-contrast chip in BOTH themes. A solid
      // saturated chip on the dark page would be the brightest thing on
      // screen, pulling the eye off the words being sung.
      chordChipColor: const Color(0xFF7ACFA8).withValues(alpha: 0.15),
      sectionLabelStyle: textTheme.titleLarge!.copyWith(
        fontSize: labelFontSize,
        height: metrics.sectionLabelRowHeight / labelFontSize,
        fontWeight: FontWeight.w700,
        // Spec section 3: 0.07em, expressed in logical px because Flutter's
        // letterSpacing is absolute.
        letterSpacing: labelFontSize * 0.07,
        color: sectionLabelColor,
      ),
      unknownSectionLabelColor: unknownSectionColor,
      commentStyle: textTheme.bodyMedium!.copyWith(
        fontStyle: FontStyle.italic,
        color: lyricColor.withValues(alpha: 0.62),
        height: 1.4,
      ),
      directiveStyle: textTheme.labelMedium!.copyWith(
        color: unknownSectionColor,
        fontWeight: FontWeight.w500,
      ),
      leadingDirectiveStyle: textTheme.labelLarge!.copyWith(
        color: chordColor,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.02,
      ),
      tabStyle: const TextStyle(
        fontFamily: 'monospace',
        fontSize: 13,
        height: 1.5,
        color: lyricColor,
      ),
      tabBackgroundColor: const Color(0xFF1A1C18),
      metrics: metrics,
    );
  }

  /// The reader tokens for [context], resolved at its viewport width.
  ///
  /// Falls back to [ReaderTheme.stageLight] over the ambient theme when no
  /// [ReaderThemeSet] is registered, so a bare `MaterialApp` in a widget test
  /// renders the same type scale the app does. `app_theme_test.dart` pins the
  /// fallback to the registered light set so the two cannot drift.
  ///
  /// With no `MediaQuery` at all this resolves to the REGULAR set. That is the
  /// conservative direction: the regular set carries the larger type, so an
  /// estimate built without a MediaQuery over-estimates rather than
  /// under-estimates, and only an under-estimate breaks the fit contract.
  static ReaderTheme of(BuildContext context) {
    final theme = Theme.of(context);
    final width =
        MediaQuery.maybeSizeOf(context)?.width ??
        readerRegularTypeScaleMinWidth;
    return theme.extension<ReaderThemeSet>()?.resolve(width) ??
        ReaderTheme.stageLight(
          colorScheme: theme.colorScheme,
          textTheme: theme.textTheme,
          compact: width < readerRegularTypeScaleMinWidth,
        );
  }

  ReaderTheme copyWith({
    TextStyle? lyricStyle,
    TextStyle? chordStyle,
    Color? chordChipColor,
    TextStyle? sectionLabelStyle,
    Color? unknownSectionLabelColor,
    TextStyle? commentStyle,
    TextStyle? directiveStyle,
    TextStyle? leadingDirectiveStyle,
    TextStyle? tabStyle,
    Color? tabBackgroundColor,
    SongReaderMetrics? metrics,
  }) {
    return ReaderTheme(
      lyricStyle: lyricStyle ?? this.lyricStyle,
      chordStyle: chordStyle ?? this.chordStyle,
      chordChipColor: chordChipColor ?? this.chordChipColor,
      sectionLabelStyle: sectionLabelStyle ?? this.sectionLabelStyle,
      unknownSectionLabelColor:
          unknownSectionLabelColor ?? this.unknownSectionLabelColor,
      commentStyle: commentStyle ?? this.commentStyle,
      directiveStyle: directiveStyle ?? this.directiveStyle,
      leadingDirectiveStyle:
          leadingDirectiveStyle ?? this.leadingDirectiveStyle,
      tabStyle: tabStyle ?? this.tabStyle,
      tabBackgroundColor: tabBackgroundColor ?? this.tabBackgroundColor,
      metrics: metrics ?? this.metrics,
    );
  }

  ReaderTheme lerpTo(ReaderTheme other, double t) {
    return ReaderTheme(
      lyricStyle: TextStyle.lerp(lyricStyle, other.lyricStyle, t)!,
      chordStyle: TextStyle.lerp(chordStyle, other.chordStyle, t)!,
      chordChipColor: Color.lerp(chordChipColor, other.chordChipColor, t),
      sectionLabelStyle: TextStyle.lerp(
        sectionLabelStyle,
        other.sectionLabelStyle,
        t,
      )!,
      unknownSectionLabelColor: Color.lerp(
        unknownSectionLabelColor,
        other.unknownSectionLabelColor,
        t,
      )!,
      commentStyle: TextStyle.lerp(commentStyle, other.commentStyle, t)!,
      directiveStyle: TextStyle.lerp(directiveStyle, other.directiveStyle, t)!,
      leadingDirectiveStyle: TextStyle.lerp(
        leadingDirectiveStyle,
        other.leadingDirectiveStyle,
        t,
      )!,
      tabStyle: TextStyle.lerp(tabStyle, other.tabStyle, t)!,
      tabBackgroundColor: Color.lerp(
        tabBackgroundColor,
        other.tabBackgroundColor,
        t,
      )!,
      // Row heights must stay a coherent set; a half-interpolated metrics
      // object is meaningless, and an in-between row height would put the
      // estimate below the render mid-animation.
      metrics: t < 0.5 ? metrics : other.metrics,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    return other is ReaderTheme &&
        other.lyricStyle == lyricStyle &&
        other.chordStyle == chordStyle &&
        other.chordChipColor == chordChipColor &&
        other.sectionLabelStyle == sectionLabelStyle &&
        other.unknownSectionLabelColor == unknownSectionLabelColor &&
        other.commentStyle == commentStyle &&
        other.directiveStyle == directiveStyle &&
        other.leadingDirectiveStyle == leadingDirectiveStyle &&
        other.tabStyle == tabStyle &&
        other.tabBackgroundColor == tabBackgroundColor &&
        other.metrics == metrics;
  }

  @override
  int get hashCode => Object.hash(
    lyricStyle,
    chordStyle,
    chordChipColor,
    sectionLabelStyle,
    unknownSectionLabelColor,
    commentStyle,
    directiveStyle,
    leadingDirectiveStyle,
    tabStyle,
    tabBackgroundColor,
    metrics,
  );
}

/// The registered `ThemeExtension`: both reader token sets, unresolved.
///
/// `ThemeData` is built once at app start with no `MediaQuery` in scope, so
/// the breakpoint cannot be applied here. It is applied in [ReaderTheme.of],
/// which every reader widget AND `measureSongReaderCharWidths` go through —
/// that shared resolution point is what stops the renderer and the fit
/// estimator from ever seeing different row heights.
@immutable
class ReaderThemeSet extends ThemeExtension<ReaderThemeSet> {
  const ReaderThemeSet({required this.compact, required this.regular});

  /// Tokens for viewports narrower than [readerRegularTypeScaleMinWidth].
  final ReaderTheme compact;

  /// Tokens for viewports at or above [readerRegularTypeScaleMinWidth].
  final ReaderTheme regular;

  ReaderTheme resolve(double width) =>
      width < readerRegularTypeScaleMinWidth ? compact : regular;

  @override
  ReaderThemeSet copyWith({ReaderTheme? compact, ReaderTheme? regular}) {
    return ReaderThemeSet(
      compact: compact ?? this.compact,
      regular: regular ?? this.regular,
    );
  }

  @override
  ReaderThemeSet lerp(ThemeExtension<ReaderThemeSet>? other, double t) {
    if (other is! ReaderThemeSet) return this;
    return ReaderThemeSet(
      compact: compact.lerpTo(other.compact, t),
      regular: regular.lerpTo(other.regular, t),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ReaderThemeSet &&
        other.compact == compact &&
        other.regular == regular;
  }

  @override
  int get hashCode => Object.hash(compact, regular);
}
