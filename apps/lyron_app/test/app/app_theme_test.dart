// apps/lyron_app/test/app/app_theme_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/app/app_theme.dart';
import 'package:lyron_app/src/app/reader_theme.dart';

void main() {
  test('the light theme registers reader tokens', () {
    final theme = buildLightTheme();

    expect(theme.extension<ReaderThemeSet>(), isNotNull);
    expect(theme.brightness, Brightness.light);
    expect(theme.scaffoldBackgroundColor, const Color(0xFFF7F4EA));
  });

  test('the dark theme registers reader tokens and a black page', () {
    final theme = buildDarkTheme();

    expect(theme.extension<ReaderThemeSet>(), isNotNull);
    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, const Color(0xFF000000));
  });

  test('the light regular tokens equal the fallback, so a tree without the '
      'extension renders identically to one with it', () {
    final theme = buildLightTheme();

    expect(
      theme.extension<ReaderThemeSet>()!.regular,
      ReaderTheme.stageLight(
        colorScheme: theme.colorScheme,
        textTheme: theme.textTheme,
        compact: false,
      ),
    );
  });

  test('the light compact tokens are the registered compact set', () {
    final theme = buildLightTheme();

    expect(
      theme.extension<ReaderThemeSet>()!.compact,
      ReaderTheme.stageLight(
        colorScheme: theme.colorScheme,
        textTheme: theme.textTheme,
        compact: true,
      ),
    );
  });

  testWidgets('the app offers both themes to the system', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLightTheme(),
        darkTheme: buildDarkTheme(),
        home: Builder(
          builder: (context) =>
              Text('reader', style: ReaderTheme.of(context).lyricStyle),
        ),
      ),
    );

    expect(find.text('reader'), findsOneWidget);
  });
}
