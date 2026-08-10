// apps/lyron_app/lib/src/app/app_theme.dart
import 'package:flutter/material.dart';
import 'package:lyron_app/src/app/reader_theme.dart';

const _seedColor = Color(0xFF0B6E4F);
const _lightPage = Color(0xFFF7F4EA);

/// The dark reader keeps a pure black page: emitted light — and therefore
/// glare on a dim stage — comes from the text, not the background, so the
/// text is dimmed instead. See docs/specs/2026-08-09-song-presentation.md.
const _darkPage = Color(0xFF000000);

ThemeData buildLightTheme() {
  final base = ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: _seedColor),
    useMaterial3: true,
    scaffoldBackgroundColor: _lightPage,
  );

  return base.copyWith(
    extensions: <ThemeExtension<dynamic>>[
      ReaderTheme.fromM3(
        colorScheme: base.colorScheme,
        textTheme: base.textTheme,
      ),
    ],
  );
}

ThemeData buildDarkTheme() {
  final base = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.dark,
    ),
    useMaterial3: true,
    scaffoldBackgroundColor: _darkPage,
  );

  return base.copyWith(
    extensions: <ThemeExtension<dynamic>>[
      ReaderTheme.stageDark(textTheme: base.textTheme),
    ],
  );
}
