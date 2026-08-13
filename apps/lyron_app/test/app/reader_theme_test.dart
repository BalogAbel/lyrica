// apps/lyron_app/test/app/reader_theme_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/app/app_theme.dart';
import 'package:lyron_app/src/app/reader_theme.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_char_metrics.dart';

void main() {
  final lightBase = ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0B6E4F)),
    useMaterial3: true,
  );

  group('ReaderTheme.stageLight', () {
    test('keeps the base font family and existing colours, chip now set', () {
      final tokens = ReaderTheme.stageLight(
        colorScheme: lightBase.colorScheme,
        textTheme: lightBase.textTheme,
        compact: false,
      );

      expect(
        tokens.lyricStyle.fontFamily,
        lightBase.textTheme.bodyLarge!.fontFamily,
      );
      expect(tokens.lyricStyle.color, lightBase.textTheme.bodyLarge!.color);
      expect(tokens.chordStyle.color, lightBase.colorScheme.primary);
      expect(tokens.sectionLabelStyle.color, lightBase.colorScheme.primary);
      expect(tokens.unknownSectionLabelColor, lightBase.colorScheme.tertiary);
      expect(tokens.chordChipColor, isNotNull);
    });
  });

  group('lerp', () {
    test('interpolates every colour field', () {
      final a = ReaderTheme.stageLight(
        colorScheme: lightBase.colorScheme,
        textTheme: lightBase.textTheme,
        compact: false,
      ).copyWith(unknownSectionLabelColor: const Color(0xFF000000));
      final b = a.copyWith(unknownSectionLabelColor: const Color(0xFFFFFFFF));

      final mid = a.lerpTo(b, 0.5);

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

      final tokens = ReaderTheme.stageDark(
        textTheme: darkBase.textTheme,
        compact: false,
      );

      expect(tokens.lyricStyle.color, const Color(0xFFCDCAC0));
      expect(tokens.chordStyle.color, const Color(0xFF7ACFA8));
      expect(tokens.sectionLabelStyle.color, const Color(0xFF6FA98D));
      // The light-theme green is unreadable on black; it must not leak through.
      expect(tokens.chordStyle.color, isNot(const Color(0xFF0B6E4F)));
    });
  });

  group('breakpoint resolution', () {
    // Two sets distinguishable by one marker value, so these tests assert the
    // RESOLUTION, not the type scale (a later task owns the real numbers).
    ReaderThemeSet markedSet() {
      final base = ThemeData(useMaterial3: true);
      final tokens = ReaderTheme.stageLight(
        colorScheme: base.colorScheme,
        textTheme: base.textTheme,
        compact: false,
      );
      return ReaderThemeSet(
        compact: tokens.copyWith(
          lyricStyle: tokens.lyricStyle.copyWith(fontSize: 11.0),
        ),
        regular: tokens.copyWith(
          lyricStyle: tokens.lyricStyle.copyWith(fontSize: 99.0),
        ),
      );
    }

    Future<ReaderTheme> tokensAt(WidgetTester tester, double width) async {
      late ReaderTheme resolved;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
          ).copyWith(extensions: <ThemeExtension<dynamic>>[markedSet()]),
          home: MediaQuery(
            data: MediaQueryData(size: Size(width, 900)),
            child: Builder(
              builder: (context) {
                resolved = ReaderTheme.of(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      return resolved;
    }

    testWidgets('at 599px the compact set applies', (tester) async {
      expect((await tokensAt(tester, 599)).lyricStyle.fontSize, 11.0);
    });

    testWidgets('at exactly 600px the regular set applies', (tester) async {
      // The spec says "phone (< 600 logical px)", so 600 is the FIRST tablet
      // width, not the last phone width.
      expect((await tokensAt(tester, 600)).lyricStyle.fontSize, 99.0);
    });

    testWidgets('at 834px (tablet portrait, the target) the regular set '
        'applies', (tester) async {
      expect((await tokensAt(tester, 834)).lyricStyle.fontSize, 99.0);
    });

    testWidgets('with no MediaQuery the regular set applies', (tester) async {
      // Conservative direction: the regular set carries the LARGER type, so an
      // estimator built without a MediaQuery over-estimates rather than
      // under-estimates. Under the one-sided contract that is the safe
      // failure.
      late ReaderTheme resolved;
      await tester.pumpWidget(
        Theme(
          data: ThemeData(
            useMaterial3: true,
          ).copyWith(extensions: <ThemeExtension<dynamic>>[markedSet()]),
          child: Builder(
            builder: (context) {
              resolved = ReaderTheme.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(resolved.lyricStyle.fontSize, 99.0);
    });

    testWidgets('the estimator and the renderer resolve the same set', (
      tester,
    ) async {
      // The invariant the whole token layer exists for: whatever width is in
      // effect, measureSongReaderCharWidths sees the SAME metrics the widget
      // renders with, because both go through ReaderTheme.of(context).
      late ReaderTheme widgetTokens;
      late SongReaderCharWidths estimatorInput;

      await tester.pumpWidget(
        MaterialApp(
          theme: buildLightTheme(),
          home: MediaQuery(
            data: const MediaQueryData(size: Size(400, 900)),
            child: Builder(
              builder: (context) {
                widgetTokens = ReaderTheme.of(context);
                estimatorInput = measureSongReaderCharWidths(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      expect(estimatorInput.metrics, widgetTokens.metrics);
      expect(
        estimatorInput.textScale.lyricBaseFontSize,
        widgetTokens.lyricStyle.fontSize,
      );
    });
  });

  group('type scale', () {
    for (final spec in const [
      (
        name: 'regular',
        compact: false,
        lyricSize: 22.0,
        lyricRow: 24.0,
        chordSize: 15.0,
        chordRow: 18.0,
        labelSize: 15.0,
        labelRow: 20.0,
      ),
      (
        name: 'compact',
        compact: true,
        lyricSize: 19.0,
        lyricRow: 21.0,
        chordSize: 13.0,
        chordRow: 16.0,
        labelSize: 13.0,
        labelRow: 18.0,
      ),
    ]) {
      ReaderTheme light() {
        final base = ThemeData(useMaterial3: true);
        return ReaderTheme.stageLight(
          colorScheme: base.colorScheme,
          textTheme: base.textTheme,
          compact: spec.compact,
        );
      }

      test('${spec.name} light tokens match the spec table', () {
        final tokens = light();

        expect(tokens.lyricStyle.fontSize, spec.lyricSize);
        expect(tokens.lyricStyle.fontWeight, FontWeight.w500);
        expect(tokens.chordStyle.fontSize, spec.chordSize);
        expect(tokens.chordStyle.fontWeight, FontWeight.w700);
        expect(tokens.sectionLabelStyle.fontSize, spec.labelSize);
        expect(tokens.sectionLabelStyle.fontWeight, FontWeight.w700);
        expect(tokens.metrics.lyricRowHeight, spec.lyricRow);
        expect(tokens.metrics.chordRowHeight, spec.chordRow);
        expect(tokens.metrics.sectionLabelRowHeight, spec.labelRow);
        expect(tokens.metrics.lineGap, 6.0);
        expect(tokens.metrics.sectionGap, 14.0);
        expect(tokens.metrics.sectionLabelToLineGap, 4.0);
        expect(tokens.metrics.chordToLyricGap, 0.0);
        expect(tokens.metrics.lineRunSpacing, 2.0);
        expect(tokens.metrics.chordChipHorizontalPadding, 3.0);
        expect(tokens.chordChipColor, isNotNull);
      });

      test('${spec.name} section label is letter-spaced at 0.07em', () {
        expect(
          light().sectionLabelStyle.letterSpacing,
          closeTo(spec.labelSize * 0.07, 0.0001),
        );
      });

      test('${spec.name} dark tokens use the same metrics and geometry as '
          'light', () {
        // A theme swap must never move a single pixel of layout: the fit
        // estimate is computed once for the content, not once per theme.
        final base = ThemeData(useMaterial3: true);
        final dark = ReaderTheme.stageDark(
          textTheme: base.textTheme,
          compact: spec.compact,
        );
        final l = light();

        expect(dark.metrics, l.metrics);
        expect(dark.lyricStyle.fontSize, l.lyricStyle.fontSize);
        expect(dark.lyricStyle.height, l.lyricStyle.height);
        expect(dark.chordStyle.fontSize, l.chordStyle.fontSize);
        expect(dark.chordStyle.height, l.chordStyle.height);
        expect(dark.sectionLabelStyle.fontSize, l.sectionLabelStyle.fontSize);
        expect(dark.sectionLabelStyle.height, l.sectionLabelStyle.height);
        expect(
          dark.sectionLabelStyle.letterSpacing,
          l.sectionLabelStyle.letterSpacing,
        );
        expect(dark.chordChipColor, isNotNull);
      });

      test('${spec.name} row heights equal the rendered line heights', () {
        // The invariant: the estimator charges these row heights per rendered
        // row, and a Text's real row height is fontSize * height. Two
        // independent literals would drift and put the estimate below the
        // render.
        final tokens = light();

        expect(
          tokens.lyricStyle.fontSize! * tokens.lyricStyle.height!,
          closeTo(tokens.metrics.lyricRowHeight, 0.001),
        );
        expect(
          tokens.chordStyle.fontSize! * tokens.chordStyle.height!,
          closeTo(tokens.metrics.chordRowHeight, 0.001),
        );
        expect(
          tokens.sectionLabelStyle.fontSize! * tokens.sectionLabelStyle.height!,
          closeTo(tokens.metrics.sectionLabelRowHeight, 0.001),
        );
      });
    }
  });
}
