import 'package:flutter_test/flutter_test.dart';
import 'package:lyrica_app/src/domain/song/parsed_song.dart';
import 'package:lyrica_app/src/infrastructure/song_library/chordpro/chordpro_parser.dart';

void main() {
  test(
    'parses supported metadata, sections, empty lines, and inline chords',
    () {
      final parser = ChordproParser();

      final song = parser.parse('''
{title:Example Song}
{subtitle:Example Subtitle}
{key:E}
{comment:<Verse 1>}
[A]Hello [F#m]world

Plain text line
{comment:<Chorus>}
{start_of_chorus}
[(B)] Sing [E/G#]to [F#m]you
{end_of_chorus}
After chorus
{comment:<Bridge>}
Bridge line
''');

      expect(song.title, 'Example Song');
      expect(song.subtitle, 'Example Subtitle');
      expect(song.sourceKey, 'E');
      expect(song.sections.map((section) => section.label).toList(), [
        'Verse',
        'Chorus',
        'Unlabeled',
        'Bridge',
      ]);
      expect(song.sections[0].kind, SongSectionKind.verse);
      expect(song.sections[0].number, 1);
      expect(song.sections[0].lines, hasLength(3));
      expect(song.sections[0].lines[0].segments, hasLength(2));
      expect(song.sections[0].lines[0].segments[0].leadingChord, 'A');
      expect(song.sections[0].lines[0].segments[0].text, 'Hello ');
      expect(song.sections[0].lines[0].segments[1].leadingChord, 'F#m');
      expect(song.sections[0].lines[0].segments[1].text, 'world');
      expect(song.sections[0].lines[1].segments.single.text, '');
      expect(song.sections[0].lines[2].segments.single.text, 'Plain text line');

      expect(song.sections[1].kind, SongSectionKind.chorus);
      expect(song.sections[1].number, isNull);
      expect(song.sections[1].lines, hasLength(1));
      expect(song.sections[1].lines.single.segments, hasLength(3));
      expect(song.sections[1].lines.single.segments[0].leadingChord, '(B)');
      expect(song.sections[1].lines.single.segments[0].text, ' Sing ');
      expect(song.sections[1].lines.single.segments[1].leadingChord, 'E/G#');
      expect(song.sections[1].lines.single.segments[1].text, 'to ');
      expect(song.sections[1].lines.single.segments[2].leadingChord, 'F#m');
      expect(song.sections[1].lines.single.segments[2].text, 'you');

      expect(song.sections[2].kind, SongSectionKind.other);
      expect(song.sections[2].label, 'Unlabeled');
      expect(
        song.sections[2].lines.single.segments.single.text,
        'After chorus',
      );
      expect(song.sections[3].kind, SongSectionKind.bridge);
      expect(song.sections[3].lines.single.segments.single.text, 'Bridge line');
      expect(song.diagnostics, isEmpty);
    },
  );

  test('emits warnings for unsupported directives and keeps parsing', () {
    final parser = ChordproParser();

    final song = parser.parse('''
{title:Example Song}
{comment:<Verse>}
Line one
{comment:// Unsupported note}
Line two
''');

    expect(song.sections, hasLength(1));
    expect(song.sections.single.lines, hasLength(2));
    expect(song.diagnostics, hasLength(1));
    expect(song.diagnostics.single.severity, ParseDiagnosticSeverity.warning);
    expect(song.diagnostics.single.context, 'comment:// Unsupported note');
    expect(song.diagnostics.single.line.lineNumber, 4);
    expect(song.diagnostics.single.line.columnNumber, 1);
    expect(
      song.diagnostics.single.message,
      'Unsupported comment content: // Unsupported note',
    );
  });

  test('rejects numbered bridge and intro comment labels with warnings', () {
    final parser = ChordproParser();

    final song = parser.parse('''
{title:Example Song}
{comment:<Verse>}
Line one
{comment:<Bridge 2>}
{comment:<Intro 2>}
''');

    expect(song.sections, hasLength(1));
    expect(song.sections.single.label, 'Verse');
    expect(song.diagnostics, hasLength(2));
    expect(song.diagnostics.map((diagnostic) => diagnostic.context).toList(), [
      'comment:<Bridge 2>',
      'comment:<Intro 2>',
    ]);
    expect(song.diagnostics.map((diagnostic) => diagnostic.message).toList(), [
      'Unsupported comment content: <Bridge 2>',
      'Unsupported comment content: <Intro 2>',
    ]);
  });
}
