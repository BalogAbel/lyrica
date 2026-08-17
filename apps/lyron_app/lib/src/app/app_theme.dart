// apps/lyron_app/lib/src/app/app_theme.dart
import 'package:flutter/material.dart';
import 'package:lyron_app/src/app/reader_theme.dart';

const _seedColor = Color(0xFF0B6E4F);
const _lightPage = Color(0xFFF7F4EA);

/// The dark reader keeps a pure black page: emitted light — and therefore
/// glare on a dim stage — comes from the text, not the background, so the
/// text is dimmed instead. See docs/specs/2026-08-09-song-presentation.md.
const _darkPage = Color(0xFF000000);

/// Fills in the numeric text geometry (font size, height, letter spacing)
/// that a bare `ThemeData(...)` leaves unset on its `textTheme`.
///
/// `ThemeData()` built outside a widget tree carries a `textTheme` with only
/// colour/weight set -- the size geometry is applied later, on demand, by
/// `Theme.of(context)` (via `ThemeData.localize`) when a widget actually asks
/// for the ambient theme. `ReaderTheme.stageLight`/`stageDark` read
/// `textTheme.bodyLarge!.fontSize` etc. directly off `base.textTheme` here,
/// at `ThemeData` construction time -- before any `Theme.of` call would ever
/// run -- so without this step every reader token built from it would carry
/// a null font size and silently fall back to whatever ambient default size
/// happened to be in force at render time, instead of the M3 scale.
ThemeData _localized(ThemeData theme) {
  return ThemeData.localize(theme, theme.typography.englishLike);
}

ThemeData buildLightTheme() {
  final base = _localized(
    ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: _seedColor),
      useMaterial3: true,
      scaffoldBackgroundColor: _lightPage,
    ),
  );

  return base.copyWith(
    extensions: <ThemeExtension<dynamic>>[
      ReaderThemeSet(
        compact: ReaderTheme.stageLight(
          colorScheme: base.colorScheme,
          textTheme: base.textTheme,
          compact: true,
        ),
        regular: ReaderTheme.stageLight(
          colorScheme: base.colorScheme,
          textTheme: base.textTheme,
          compact: false,
        ),
      ),
    ],
  );
}

ThemeData buildDarkTheme() {
  final base = _localized(
    ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: _seedColor,
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
      scaffoldBackgroundColor: _darkPage,
    ),
  );

  return base.copyWith(
    extensions: <ThemeExtension<dynamic>>[
      ReaderThemeSet(
        compact: ReaderTheme.stageDark(
          textTheme: base.textTheme,
          compact: true,
        ),
        regular: ReaderTheme.stageDark(
          textTheme: base.textTheme,
          compact: false,
        ),
      ),
    ],
  );
}
