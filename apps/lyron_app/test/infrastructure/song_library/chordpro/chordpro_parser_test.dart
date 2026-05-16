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
      final verse1line0 = song.sections[0].lines[0] as LyricLine;
      expect(verse1line0.segments, hasLength(2));
      expect(verse1line0.segments[0].leadingChord, 'A');
      expect(verse1line0.segments[0].text, 'Hello ');
      expect(verse1line0.segments[1].leadingChord, 'F#m');
      expect(verse1line0.segments[1].text, 'world');
      final verse1line1 = song.sections[0].lines[1] as LyricLine;
      expect(verse1line1.segments.single.text, '');
      final verse1line2 = song.sections[0].lines[2] as LyricLine;
      expect(verse1line2.segments.single.text, 'Plain text line');

      expect(song.sections[1].kind, SongSectionKind.chorus);
      expect(song.sections[1].number, isNull);
      expect(song.sections[1].lines, hasLength(1));
      final chorus1line = song.sections[1].lines.single as LyricLine;
      expect(chorus1line.segments, hasLength(3));
      expect(chorus1line.segments[0].leadingChord, '(B)');
      expect(chorus1line.segments[0].text, ' Sing ');
      expect(chorus1line.segments[1].leadingChord, 'E/G#');
      expect(chorus1line.segments[1].text, 'to ');
      expect(chorus1line.segments[2].leadingChord, 'F#m');
      expect(chorus1line.segments[2].text, 'you');

      expect(song.sections[2].kind, SongSectionKind.other);
      expect(song.sections[2].label, 'Unlabeled');
      final unlabeled1line = song.sections[2].lines.single as LyricLine;
      expect(unlabeled1line.segments.single.text, 'After chorus');
      expect(song.sections[3].kind, SongSectionKind.bridge);
      final bridge1line = song.sections[3].lines.single as LyricLine;
      expect(bridge1line.segments.single.text, 'Bridge line');
      expect(song.diagnostics, isEmpty);
    },
  );

  test(
    '{comment:// ...} creates a CommentLine in the current section without a diagnostic',
    () {
      final parser = ChordproParser();

      final song = parser.parse('''
{title:Example Song}
{comment:<Verse>}
Line one
{comment:// Unsupported note}
Line two
''');

      expect(song.sections.single.label, 'Verse');
      expect(song.sections.single.lines, hasLength(3));
      expect(song.sections.single.lines[0], isA<LyricLine>());
      expect(
        (song.sections.single.lines[0] as LyricLine).segments.single.text,
        'Line one',
      );
      expect(song.sections.single.lines[1], isA<CommentLine>());
      expect(
        (song.sections.single.lines[1] as CommentLine).text,
        '// Unsupported note',
      );
      expect(song.sections.single.lines[2], isA<LyricLine>());
      expect(
        (song.sections.single.lines[2] as LyricLine).segments.single.text,
        'Line two',
      );
      expect(song.diagnostics, isEmpty);
    },
  );

  test(
    '{comment:// ...} inside a section stays in the same section as a CommentLine',
    () {
      final parser = ChordproParser();

      final song = parser.parse('''
{title:Example Song}
{comment:<Bridge>}
Bridge line
{comment:// footer note}
Trailing line
''');

      expect(song.sections.single.label, 'Bridge');
      expect(song.sections.single.lines, hasLength(3));
      final bridgeLine = song.sections.single.lines[0] as LyricLine;
      expect(bridgeLine.segments.single.text, 'Bridge line');
      expect(song.sections.single.lines[1], isA<CommentLine>());
      expect(
        (song.sections.single.lines[1] as CommentLine).text,
        '// footer note',
      );
      final trailingLine = song.sections.single.lines[2] as LyricLine;
      expect(trailingLine.segments.single.text, 'Trailing line');
      expect(song.diagnostics, isEmpty);
    },
  );

  test('numbered bridge and intro comment labels are now accepted', () {
    final parser = ChordproParser();

    final song = parser.parse('''
{title:Example Song}
{comment:<Verse>}
Line one
{comment:<Bridge 2>}
{comment:<Intro 2>}
''');

    expect(song.sections, hasLength(3));
    expect(song.sections[0].label, 'Verse');
    expect(song.sections[1].kind, SongSectionKind.bridge);
    expect(song.sections[1].number, 2);
    expect(song.sections[2].kind, SongSectionKind.other);
    expect(song.sections[2].label, 'Intro');
    expect(song.sections[2].number, 2);
    expect(song.diagnostics, isEmpty);
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
    final bracketVerseLine = song.sections[0].lines.single as LyricLine;
    expect(bracketVerseLine.segments.single.text, 'Line one');
    expect(song.sections[1].kind, SongSectionKind.chorus);
    expect(song.sections[1].number, isNull);
    final bracketChorusLine = song.sections[1].lines.single as LyricLine;
    expect(bracketChorusLine.segments.single.text, 'Line two');
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
    'keeps metadata open after unknown directives before the first lyric',
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
      expect(song.diagnostics, isEmpty);
    },
  );

  test('keeps metadata open after comment lines before the first lyric', () {
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
    expect(song.diagnostics, isEmpty);
  });

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

  test('parsed lyric lines are LyricLine instances', () {
    final parser = ChordproParser();
    final song = parser.parse('{title:T}\n{comment:<Verse>}\n[A]Hello\n');
    expect(song.sections.single.lines.single, isA<LyricLine>());
  });

  test('SongSectionKind has unknown and tab values', () {
    expect(SongSectionKind.values, contains(SongSectionKind.unknown));
    expect(SongSectionKind.values, contains(SongSectionKind.tab));
  });

  test('{tag:} singular is an alias for {tags:}', () {
    final parser = ChordproParser();
    final song = parser.parse('{title:T}\n{tag: Worship, Praise}\n');
    expect(song.tags, ['Worship', 'Praise']);
    expect(song.diagnostics, isEmpty);
  });

  test('{meta:} is silently ignored without a diagnostic', () {
    final parser = ChordproParser();
    final song = parser.parse('{title:T}\n{meta: key value}\n');
    expect(song.diagnostics, isEmpty);
  });

  test('parser accepts short aliases robustly (post-normalizer fallback)', () {
    final parser = ChordproParser();
    // {t:} and {st:} should be accepted even without normalizer running first
    final song = parser.parse('{t:My Song}\n{st:Sub}\n');
    expect(song.title, 'My Song');
    expect(song.subtitle, 'Sub');
    expect(song.diagnostics, isEmpty);
  });

  test('{start_of_verse}/{end_of_verse} creates a verse section', () {
    final parser = ChordproParser();
    final song = parser.parse(
      '{title:T}\n{start_of_verse}\n[A]Line\n{end_of_verse}\n',
    );
    expect(song.sections.single.kind, SongSectionKind.verse);
    expect(song.sections.single.label, 'Verse');
    expect(song.diagnostics, isEmpty);
  });

  test('{start_of_bridge}/{end_of_bridge} creates a bridge section', () {
    final parser = ChordproParser();
    final song = parser.parse(
      '{title:T}\n{start_of_bridge}\n[A]Line\n{end_of_bridge}\n',
    );
    expect(song.sections.single.kind, SongSectionKind.bridge);
    expect(song.diagnostics, isEmpty);
  });

  test('{start_of_verse: Verse 1} uses label override', () {
    final parser = ChordproParser();
    final song = parser.parse(
      '{title:T}\n{start_of_verse: Verse 1}\n[A]Line\n{end_of_verse}\n',
    );
    expect(song.sections.single.kind, SongSectionKind.verse);
    expect(song.sections.single.label, 'Verse 1');
    expect(song.diagnostics, isEmpty);
  });

  test('{start_of_chorus: Refrén} uses label override', () {
    final parser = ChordproParser();
    final song = parser.parse(
      '{title:T}\n{start_of_chorus: Refrén}\n[A]Line\n{end_of_chorus}\n',
    );
    expect(song.sections.single.kind, SongSectionKind.chorus);
    expect(song.sections.single.label, 'Refrén');
    expect(song.diagnostics, isEmpty);
  });

  test('{start_of_tab}/{end_of_tab} creates a tab section with TabBlock', () {
    final parser = ChordproParser();
    final song = parser.parse(
      '{title:T}\n{start_of_tab}\ne|---0---\nB|---1---\n{end_of_tab}\n',
    );
    expect(song.sections.single.kind, SongSectionKind.tab);
    expect(song.sections.single.lines, hasLength(1));
    expect(song.sections.single.lines[0], isA<TabBlock>());
    final tab = song.sections.single.lines[0] as TabBlock;
    expect(tab.rawLines, ['e|---0---', 'B|---1---']);
    expect(song.diagnostics, isEmpty);
  });

  test('directives inside {start_of_tab} are treated as literal text', () {
    final parser = ChordproParser();
    final song = parser.parse(
      '{title:T}\n{start_of_tab}\ne|---0---\n{comment:some note}\nB|---1---\n{end_of_tab}\n',
    );
    expect(song.sections.single.kind, SongSectionKind.tab);
    expect(song.sections.single.lines, hasLength(1));
    final tab = song.sections.single.lines[0] as TabBlock;
    expect(tab.rawLines, ['e|---0---', '{comment:some note}', 'B|---1---']);
  });

  test('{start_of_prechorus} creates an unknown section', () {
    final parser = ChordproParser();
    final song = parser.parse(
      '{title:T}\n{start_of_prechorus}\n[A]Line\n{end_of_prechorus}\n',
    );
    expect(song.sections.single.kind, SongSectionKind.unknown);
    expect(song.sections.single.label, 'prechorus');
    expect(song.diagnostics, isEmpty);
  });

  test(
    '<Verse1> (no space before digit) is parsed as verse section number 1',
    () {
      final parser = ChordproParser();
      final song = parser.parse('{title:T}\n{comment:<Verse1>}\n[A]Line\n');
      expect(song.sections.single.kind, SongSectionKind.verse);
      expect(song.sections.single.number, 1);
      expect(song.diagnostics, isEmpty);
    },
  );

  test('<Bridge 1> (numbered bridge) is parsed correctly', () {
    final parser = ChordproParser();
    final song = parser.parse('{title:T}\n{comment:<Bridge 1>}\n[A]Line\n');
    expect(song.sections.single.kind, SongSectionKind.bridge);
    expect(song.sections.single.number, 1);
    expect(song.diagnostics, isEmpty);
  });

  test('<PreChorus> creates an unknown section with label PreChorus', () {
    final parser = ChordproParser();
    final song = parser.parse('{title:T}\n{comment:<PreChorus>}\n[A]Line\n');
    expect(song.sections.single.kind, SongSectionKind.unknown);
    expect(song.sections.single.label, 'PreChorus');
    expect(song.diagnostics, isEmpty);
  });

  test('{comment:// note} creates a CommentLine in current section', () {
    final parser = ChordproParser();
    final song = parser.parse(
      '{title:T}\n{comment:<Verse>}\n[A]Line\n{comment:// Note}\n',
    );
    expect(song.sections.single.lines, hasLength(2));
    expect(song.sections.single.lines[1], isA<CommentLine>());
    final comment = song.sections.single.lines[1] as CommentLine;
    expect(comment.text, '// Note');
    expect(song.diagnostics, isEmpty);
  });

  test('{comment:# Author} creates a CommentLine', () {
    final parser = ChordproParser();
    final song = parser.parse(
      '{title:T}\n{comment:<Verse>}\n[A]Line\n{comment:#Szerző: Pintér}\n',
    );
    expect(song.sections.single.lines[1], isA<CommentLine>());
    expect(
      (song.sections.single.lines[1] as CommentLine).text,
      '#Szerző: Pintér',
    );
    expect(song.diagnostics, isEmpty);
  });

  test('{comment: plain text} creates a CommentLine', () {
    final parser = ChordproParser();
    final song = parser.parse(
      '{title:T}\n{comment:<Verse>}\n[A]Line\n{comment:Some remark}\n',
    );
    expect(song.sections.single.lines[1], isA<CommentLine>());
    expect((song.sections.single.lines[1] as CommentLine).text, 'Some remark');
    expect(song.diagnostics, isEmpty);
  });

  test('unknown directive before any section goes into preamble section', () {
    final parser = ChordproParser();
    final song = parser.parse(
      '{title:T}\n{zoom-ipad: 1.9}\n{comment:<Verse>}\n[A]Line\n',
    );
    expect(song.sections, hasLength(2));
    expect(song.sections[0].kind, SongSectionKind.other);
    expect(song.sections[0].label, 'Unlabeled');
    expect(song.sections[0].lines.single, isA<DirectiveLine>());
    final directive = song.sections[0].lines.single as DirectiveLine;
    expect(directive.name, 'zoom-ipad');
    expect(directive.value, '1.9');
    expect(song.diagnostics, isEmpty);
  });

  test(
    'unknown directive inside a section becomes DirectiveLine in that section',
    () {
      final parser = ChordproParser();
      final song = parser.parse(
        '{title:T}\n{comment:<Verse>}\n[A]Line\n{metronome:120}\n',
      );
      expect(song.sections.single.lines, hasLength(2));
      expect(song.sections.single.lines[1], isA<DirectiveLine>());
      final directive = song.sections.single.lines[1] as DirectiveLine;
      expect(directive.name, 'metronome');
      expect(directive.value, '120');
      expect(song.diagnostics, isEmpty);
    },
  );
}
