// apps/lyron_app/test/app/reader_theme_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/app/reader_theme.dart';

void main() {
  final lightBase = ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0B6E4F)),
    useMaterial3: true,
  );

  group('ReaderTheme.fromM3', () {
    test('reproduces the styles the reader widgets derive by hand today', () {
      final tokens = ReaderTheme.fromM3(
        colorScheme: lightBase.colorScheme,
        textTheme: lightBase.textTheme,
      );

      expect(
        tokens.lyricStyle,
        lightBase.textTheme.bodyLarge!.copyWith(height: 1.25),
      );
      expect(
        tokens.chordStyle,
        lightBase.textTheme.labelLarge!.copyWith(
          fontWeight: FontWeight.w700,
          color: lightBase.colorScheme.primary,
        ),
      );
      expect(
        tokens.sectionLabelStyle,
        lightBase.textTheme.titleLarge!.copyWith(
          color: lightBase.colorScheme.primary,
        ),
      );
      expect(tokens.unknownSectionLabelColor, lightBase.colorScheme.tertiary);
      expect(tokens.chordChipColor, isNull);
    });
  });

  group('lerp', () {
    test('returns the receiver when other is null', () {
      final tokens = ReaderTheme.fromM3(
        colorScheme: lightBase.colorScheme,
        textTheme: lightBase.textTheme,
      );

      expect(tokens.lerp(null, 0.5), same(tokens));
    });

    test('interpolates every colour field', () {
      final a = ReaderTheme.fromM3(
        colorScheme: lightBase.colorScheme,
        textTheme: lightBase.textTheme,
      ).copyWith(unknownSectionLabelColor: const Color(0xFF000000));
      final b = a.copyWith(unknownSectionLabelColor: const Color(0xFFFFFFFF));

      final mid = a.lerp(b, 0.5);

      expect(
        mid.unknownSectionLabelColor,
        Color.lerp(const Color(0xFF000000), const Color(0xFFFFFFFF), 0.5),
      );
    });
  });

  group('stageDark', () {
    test('uses the stage palette rather than inverting the light one', () {
      final darkBase = ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0B6E4F),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      );

      final tokens = ReaderTheme.stageDark(textTheme: darkBase.textTheme);

      expect(tokens.lyricStyle.color, const Color(0xFFCDCAC0));
      expect(tokens.chordStyle.color, const Color(0xFF7ACFA8));
      expect(tokens.sectionLabelStyle.color, const Color(0xFF6FA98D));
      // The light-theme green is unreadable on black; it must not leak through.
      expect(tokens.chordStyle.color, isNot(const Color(0xFF0B6E4F)));
    });
  });
}
