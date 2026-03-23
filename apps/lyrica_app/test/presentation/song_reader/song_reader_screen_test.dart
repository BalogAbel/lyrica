import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyrica_app/src/application/song_library/song_reader_result.dart';
import 'package:lyrica_app/src/domain/song/parse_diagnostic.dart';
import 'package:lyrica_app/src/domain/song/parsed_song.dart';
import 'package:lyrica_app/src/domain/song/song_line.dart';
import 'package:lyrica_app/src/domain/song/song_section.dart';
import 'package:lyrica_app/src/domain/song/lyric_segment.dart';
import 'package:lyrica_app/src/presentation/song_library/song_library_providers.dart';
import 'package:lyrica_app/src/presentation/song_reader/song_reader_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const songId = 'reader_song';

  SongReaderResult buildResult({List<ParseDiagnostic> diagnostics = const []}) {
    return SongReaderResult(
      song: ParsedSong(
        title: 'Reader Song',
        subtitle: 'Live version',
        sourceKey: 'G',
        sections: [
          SongSection(
            kind: SongSectionKind.verse,
            label: 'Verse',
            number: 1,
            lines: [
              SongLine(
                segments: [
                  const LyricSegment(leadingChord: 'F#m', text: 'Hello'),
                  const LyricSegment(text: ' world'),
                ],
              ),
            ],
          ),
          SongSection(
            kind: SongSectionKind.chorus,
            label: 'Chorus',
            number: 2,
            lines: [
              SongLine(
                segments: [
                  const LyricSegment(leadingChord: 'A', text: 'Sing'),
                  const LyricSegment(text: ' along'),
                ],
              ),
            ],
          ),
        ],
        diagnostics: diagnostics,
      ),
    );
  }

  Widget buildApp({required SongReaderResult result}) {
    return ProviderScope(
      overrides: [
        songLibraryReaderProvider.overrideWithProvider(
          (value) => FutureProvider((ref) async => result),
        ),
      ],
      child: const MaterialApp(home: SongReaderScreen(songId: songId)),
    );
  }

  testWidgets('shows metadata, sections, and controls by default', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp(result: buildResult()));
    await tester.pumpAndSettle();

    expect(find.text('Reader Song'), findsOneWidget);
    expect(find.text('Live version'), findsOneWidget);
    expect(find.text('Key: G'), findsOneWidget);
    expect(find.text('Verse 1'), findsOneWidget);
    expect(find.text('Chorus 2'), findsOneWidget);
    expect(find.text('F#m'), findsOneWidget);
  });

  testWidgets('hides chords in lyrics only mode', (tester) async {
    await tester.pumpWidget(buildApp(result: buildResult()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Lyrics only'));
    await tester.pumpAndSettle();

    expect(find.text('F#m'), findsNothing);
    expect(find.text('Hello'), findsOneWidget);
  });

  testWidgets('transposes rendered chords when controls change', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp(result: buildResult()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('+1'));
    await tester.pumpAndSettle();

    expect(find.text('Gm'), findsOneWidget);
    expect(find.text('F#m'), findsNothing);
  });

  testWidgets('updates shared font size when controls change', (tester) async {
    await tester.pumpWidget(buildApp(result: buildResult()));
    await tester.pumpAndSettle();

    final initialText = tester.widget<Text>(find.text('Hello'));
    final initialSize = initialText.style!.fontSize!;

    await tester.tap(find.text('A+'));
    await tester.pumpAndSettle();

    final scaledText = tester.widget<Text>(find.text('Hello'));
    final scaledSize = scaledText.style!.fontSize!;

    expect(scaledSize, greaterThan(initialSize));
  });

  testWidgets(
    'shows a non-blocking warning surface for recoverable diagnostics',
    (tester) async {
      await tester.pumpWidget(
        buildApp(
          result: buildResult(
            diagnostics: [
              ParseDiagnostic(
                severity: ParseDiagnosticSeverity.warning,
                message: 'Unknown directive',
                line: const ParseDiagnosticLineMetadata(lineNumber: 3),
                context: 'unknown:token',
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('warning'), findsWidgets);
    },
  );

  testWidgets('counts only warning diagnostics in the warning surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildApp(
        result: buildResult(
          diagnostics: [
            ParseDiagnostic(
              severity: ParseDiagnosticSeverity.info,
              message: 'Normalized spacing',
              line: const ParseDiagnosticLineMetadata(lineNumber: 1),
            ),
            ParseDiagnostic(
              severity: ParseDiagnosticSeverity.warning,
              message: 'Unknown directive',
              line: const ParseDiagnosticLineMetadata(lineNumber: 3),
              context: 'unknown:token',
            ),
            ParseDiagnostic(
              severity: ParseDiagnosticSeverity.error,
              message: 'Invalid token',
              line: const ParseDiagnosticLineMetadata(lineNumber: 5),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('1 recoverable warning while reading this song.'),
      findsOneWidget,
    );
    expect(
      find.text('3 recoverable warnings while reading this song.'),
      findsNothing,
    );
  });
}
