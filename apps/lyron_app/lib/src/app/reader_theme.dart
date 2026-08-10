// apps/lyron_app/lib/src/app/reader_theme.dart
import 'package:flutter/material.dart';

/// Colours and text styles for the song reader's content surface.
///
/// The reader's renderer and its fit estimator must describe the *same* text
/// styles: `measureSongReaderCharWidths` measures the styles the reader draws
/// with and feeds the result into an estimate that must never fall below the
/// rendered height. Before this extension existed they agreed only by
/// convention — `song_line_view.dart` and `song_reader_char_metrics.dart` each
/// re-derived `labelLarge + w700` / `bodyLarge + height: 1.25` by hand. Reading
/// both from one object makes that agreement structural.
///
/// Spacing is deliberately NOT here. Line, section and padding constants live
/// in `song_reader_metrics.dart` and `song_reader_fit.dart`, are shared by the
/// renderer and the estimator already, and do not vary by theme. Copying them
/// into a theme object would create the second definition this class exists to
/// remove.
@immutable
class ReaderTheme extends ThemeExtension<ReaderTheme> {
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
  });

  /// Lyric text. Font size is the BASE size; the reader multiplies it by
  /// `sharedFontScale` at render time and the estimator converts it with
  /// `SongReaderFitTextScale.factorFor`.
  final TextStyle lyricStyle;

  /// Chord label text, at its base size.
  final TextStyle chordStyle;

  /// Background fill behind a chord label, or null for no fill.
  ///
  /// Null in both themes today. PR2 introduces the tinted chip; it is declared
  /// now so the chip's colour has a home and the renderer/estimator agree from
  /// the start about whether a chip exists.
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

  /// Builds the tokens exactly as the reader widgets derived them from a
  /// Material 3 theme before this class existed. Used for the light theme, and
  /// as the fallback for any `ThemeData` that has not registered the extension
  /// (notably widget tests that pump a bare `MaterialApp`), so that such a tree
  /// renders identically to how it did before.
  factory ReaderTheme.fromM3({
    required ColorScheme colorScheme,
    required TextTheme textTheme,
  }) {
    return ReaderTheme(
      lyricStyle: textTheme.bodyLarge!.copyWith(height: 1.25),
      chordStyle: textTheme.labelLarge!.copyWith(
        fontWeight: FontWeight.w700,
        color: colorScheme.primary,
      ),
      chordChipColor: null,
      sectionLabelStyle: textTheme.titleLarge!.copyWith(
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
  factory ReaderTheme.stageDark({required TextTheme textTheme}) {
    const lyricColor = Color(0xFFCDCAC0);
    const chordColor = Color(0xFF7ACFA8);
    const sectionLabelColor = Color(0xFF6FA98D);
    const unknownSectionColor = Color(0xFFD8B892);

    return ReaderTheme(
      lyricStyle: textTheme.bodyLarge!.copyWith(
        height: 1.25,
        color: lyricColor,
      ),
      chordStyle: textTheme.labelLarge!.copyWith(
        fontWeight: FontWeight.w700,
        color: chordColor,
      ),
      chordChipColor: null,
      sectionLabelStyle: textTheme.titleLarge!.copyWith(
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
    );
  }

  /// The reader tokens for [context].
  ///
  /// Falls back to [ReaderTheme.fromM3] over the ambient theme when no
  /// extension is registered, so a tree that predates the extension renders
  /// unchanged. `app_theme_test.dart` pins the fallback to the registered
  /// light tokens so the two cannot drift.
  static ReaderTheme of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<ReaderTheme>() ??
        ReaderTheme.fromM3(
          colorScheme: theme.colorScheme,
          textTheme: theme.textTheme,
        );
  }

  @override
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
    );
  }

  @override
  ReaderTheme lerp(ThemeExtension<ReaderTheme>? other, double t) {
    if (other is! ReaderTheme) {
      return this;
    }

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
        other.tabBackgroundColor == tabBackgroundColor;
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
  );
}
