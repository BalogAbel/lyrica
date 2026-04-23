import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/domain/song/parsed_song.dart';
import 'package:lyron_app/src/infrastructure/song_library/chordpro/chordpro_parser.dart';

void main() {
  test(
    'parses supported metadata, sections, empty lines, and inline chords',
    () {
      final parser = ChordproParser();

      final song = parser.parse('''
{title:Example Song}
{subtitle:Example Subtitle}
{key:E}
{capo:2}
{transpose:-2}
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
      expect(song.baseCapo, 2);
      expect(song.baseTranspose, -2);
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

    expect(song.sections, hasLength(2));
    expect(song.sections.first.label, 'Verse');
    expect(song.sections.first.lines.single.segments.single.text, 'Line one');
    expect(song.sections.last.label, 'Unlabeled');
    expect(song.sections.last.lines.single.segments.single.text, 'Line two');
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

  test(
    'unsupported comment content ends the active section before later lyrics',
    () {
      final parser = ChordproParser();

      final song = parser.parse('''
{title:Example Song}
{comment:<Bridge>}
Bridge line
{comment:// footer note}
Trailing line
''');

      expect(song.sections, hasLength(2));
      expect(song.sections[0].label, 'Bridge');
      expect(song.sections[0].lines.single.segments.single.text, 'Bridge line');
      expect(song.sections[1].label, 'Unlabeled');
      expect(
        song.sections[1].lines.single.segments.single.text,
        'Trailing line',
      );
      expect(song.diagnostics.single.context, 'comment:// footer note');
    },
  );

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

  test('accepts common comment section variants without angle brackets', () {
    final parser = ChordproParser();

    final song = parser.parse('''
{title:Example Song}
{comment: Verse 1}
Line one
{comment:[Chorus]}
Line two
''');

    expect(song.sections, hasLength(2));
    expect(song.sections[0].kind, SongSectionKind.verse);
    expect(song.sections[0].number, 1);
    expect(song.sections[0].lines.single.segments.single.text, 'Line one');
    expect(song.sections[1].kind, SongSectionKind.chorus);
    expect(song.sections[1].number, isNull);
    expect(song.sections[1].lines.single.segments.single.text, 'Line two');
    expect(song.diagnostics, isEmpty);
  });

  test(
    'defaults capo and transpose metadata to zero when directives missing',
    () {
      final parser = ChordproParser();

      final song = parser.parse('''
{title:Example Song}
{key:G}
[G]Line
''');

      expect(song.sourceKey, 'G');
      expect(song.baseCapo, 0);
      expect(song.baseTranspose, 0);
    },
  );

  test(
    'ignores later transpose directives for current global reader slice',
    () {
      final parser = ChordproParser();

      final song = parser.parse('''
{title:Example Song}
{transpose:2}
[C]Line one
{transpose:-3}
[D]Line two
''');

      expect(song.baseTranspose, 2);
      expect(song.baseCapo, 0);
      expect(song.diagnostics, isEmpty);
    },
  );

  test('reads global transpose after blank lines before the first lyric', () {
    final parser = ChordproParser();

    final song = parser.parse('''
{title:Example Song}

{transpose:4}
[C]Line one
''');

    expect(song.baseTranspose, 4);
    expect(song.baseCapo, 0);
  });

  test('ignores later capo directives after song content starts', () {
    final parser = ChordproParser();

    final song = parser.parse('''
{title:Example Song}
{capo:2}
[C]Line one
{capo:7}
[D]Line two
''');

    expect(song.baseCapo, 2);
    expect(song.baseTranspose, 0);
  });

  test('ignores later key directives after song content starts', () {
    final parser = ChordproParser();

    final song = parser.parse('''
{title:Example Song}
{key:G}
[G]Line one
{key:D}
[D]Line two
''');

    expect(song.sourceKey, 'G');
    expect(song.baseCapo, 0);
    expect(song.baseTranspose, 0);
  });

  test('treats body directives before the first lyric as song content', () {
    final parser = ChordproParser();

    final song = parser.parse('''
{title:Example Song}
{comment:<Verse>}
{key:G}
{capo:2}
{transpose:4}
[C]Line one
''');

    expect(song.sourceKey, isNull);
    expect(song.baseCapo, 0);
    expect(song.baseTranspose, 0);
  });

  test(
    'keeps metadata open after unsupported directives before the first lyric',
    () {
      final parser = ChordproParser();

      final song = parser.parse('''
{title:Example Song}
{foobar:ignore me}
{key:G}
{capo:2}
{transpose:4}
[C]Line one
''');

      expect(song.sourceKey, 'G');
      expect(song.baseCapo, 2);
      expect(song.baseTranspose, 4);
      expect(song.diagnostics.single.context, '{foobar:ignore me}');
    },
  );

  test(
    'keeps metadata open after malformed comments before the first lyric',
    () {
      final parser = ChordproParser();

      final song = parser.parse('''
{title:Example Song}
{comment:// note}
{key:D}
{capo:3}
{transpose:1}
[C]Line one
''');

      expect(song.sourceKey, 'D');
      expect(song.baseCapo, 3);
      expect(song.baseTranspose, 1);
      expect(song.diagnostics.single.context, 'comment:// note');
    },
  );

  test('rejects blank key values and negative capo values', () {
    final parser = ChordproParser();

    final song = parser.parse('''
{title:Example Song}
{key:}
{capo:-1}
{transpose:3}
[C]Line
''');

    expect(song.sourceKey, isNull);
    expect(song.baseCapo, 0);
    expect(song.baseTranspose, 3);
    expect(song.diagnostics, hasLength(2));
    expect(song.diagnostics.map((diagnostic) => diagnostic.context).toList(), [
      'key:',
      'capo:-1',
    ]);
  });

  test(
    'keeps earlier capo and transpose values when later directives are invalid',
    () {
      final parser = ChordproParser();

      final song = parser.parse('''
{title:Example Song}
{capo:2}
{transpose:-3}
{capo:abc}
{transpose:}
[C]Line
''');

      expect(song.baseCapo, 2);
      expect(song.baseTranspose, -3);
      expect(song.diagnostics, hasLength(2));
      expect(
        song.diagnostics.map((diagnostic) => diagnostic.context).toList(),
        ['capo:abc', 'transpose:'],
      );
      expect(
        song.diagnostics.map((diagnostic) => diagnostic.message).toList(),
        ['Invalid capo value: abc', 'Invalid transpose value: '],
      );
    },
  );
}
