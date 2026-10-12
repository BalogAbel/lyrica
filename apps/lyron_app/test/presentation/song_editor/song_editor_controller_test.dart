import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/infrastructure/song_library/chordpro/chordpro_line_scanner.dart';
import 'package:lyron_app/src/infrastructure/song_library/chordpro/chordpro_parser.dart';
import 'package:lyron_app/src/presentation/song_editor/song_editor_controller.dart';

void main() {
  test(
    'loads ChordPro source and derived metadata from the current source',
    () {
      final controller = SongEditorController(
        source: '''
{title: Heart of Worship}
{artist: Matt Redman}
{key: D}
{tempo: 72}
{tags: worship, acoustic}

[D]When the music fades
''',
      );

      expect(controller.state.source, contains('{title: Heart of Worship}'));
      expect(controller.state.parsedSong.title, 'Heart of Worship');
      expect(controller.state.parsedSong.artist, 'Matt Redman');
      expect(controller.state.parsedSong.sourceKey, 'D');
      expect(controller.state.parsedSong.tempoBpm, 72);
      expect(controller.state.parsedSong.tags, ['worship', 'acoustic']);
      expect(controller.state.parsedSong.baseTranspose, 0);
      expect(controller.state.parsedSong.baseCapo, 0);
    },
  );

  test('transpose and capo controls update the stored ChordPro directives', () {
    final controller = SongEditorController(
      source: '''
{title: Heart of Worship}
{artist: Matt Redman}
{key: D}
{tempo: 72}
{tags: worship, acoustic}

[D]When the music fades
''',
    );

    controller.transposeUp();
    controller.transposeUp();
    controller.transposeDown();
    controller.capoUp();
    controller.capoUp();
    controller.capoDown();

    expect(controller.state.parsedSong.baseTranspose, 1);
    expect(controller.state.parsedSong.baseCapo, 1);
    expect(controller.state.source, contains('{transpose: 1}'));
    expect(controller.state.source, contains('{capo: 1}'));
  });

  test('transpose and capo taps never delete in-song directives (E3)', () {
    const source = '''
{title: Heart of Worship}

[D]When the music fades
{transpose: 4}
{capo: 4}
''';
    final controller = SongEditorController(source: source);

    controller.transposeUp();
    controller.capoUp();

    final result = controller.state.source;
    expect(controller.state.parsedSong.baseTranspose, 1);
    expect(controller.state.parsedSong.baseCapo, 1);
    expect(result, contains('{transpose: 1}'));
    expect(result, contains('{capo: 1}'));
    expect(result.indexOf('{transpose: 1}'), lessThan(result.indexOf('[D]')));
    expect(result.indexOf('{capo: 1}'), lessThan(result.indexOf('[D]')));
    expect(
      result.substring(result.indexOf('[D]')),
      source.substring(source.indexOf('[D]')),
    );
  });

  test('a base transpose edit leaves an in-song transpose intact (E4)', () {
    final controller = SongEditorController(
      source: '{transpose: 1}\n[A]x\n{transpose: 3}\n[B]y\n',
    );

    controller.transposeUp();

    expect(
      controller.state.source,
      '{transpose: 2}\n[A]x\n{transpose: 3}\n[B]y\n',
    );
  });

  test('a base edit after a section comment keeps everything else (E5)', () {
    final controller = SongEditorController(
      source: '{title: T}\n{comment:<Intro>}\n{transpose: 2}\n[A]x\n',
    );

    controller.transposeUp();

    expect(
      controller.state.source,
      '{title: T}\n{comment:<Intro>}\n{transpose: 3}\n[A]x\n',
    );
  });

  test('duplicate base transposes collapse into the last one (E6)', () {
    final controller = SongEditorController(
      source: '{transpose: 1}\n{title: T}\n{transpose: 5}\n[A]x\n',
    );

    controller.transposeUp();

    expect(controller.state.source, '{title: T}\n{transpose: 6}\n[A]x\n');
  });

  test('a transpose inside a tab block is never touched (E7)', () {
    final controller = SongEditorController(
      source:
          '{title: T}\n{start_of_tab}\n{transpose: 9}\n{end_of_tab}\n[C]x\n',
    );

    controller.transposeUp();

    expect(
      controller.state.source,
      '{title: T}\n{transpose: 1}\n{start_of_tab}\n{transpose: 9}\n'
      '{end_of_tab}\n[C]x\n',
    );
  });

  test(
    'new transpose and capo directives are inserted before section comments',
    () {
      final controller = SongEditorController(
        source: '''
{title: Heart of Worship}
{subtitle: When the music fades}
{key: D}

{comment:<Intro>}
[D]When the music fades
''',
      );

      controller.transposeUp();
      controller.capoUp();

      final source = controller.state.source;
      final transposeIndex = source.indexOf('{transpose: 1}');
      final capoIndex = source.indexOf('{capo: 1}');
      final commentIndex = source.indexOf('{comment:<Intro>}');

      expect(transposeIndex, isNonNegative);
      expect(capoIndex, isNonNegative);
      expect(commentIndex, isNonNegative);
      expect(transposeIndex, lessThan(commentIndex));
      expect(capoIndex, lessThan(commentIndex));
      expect(transposeIndex, lessThan(capoIndex));
    },
  );

  test('directive updates preserve CRLF line endings', () {
    final controller = SongEditorController(
      source:
          '{title: Heart of Worship}\r\n'
          '{comment:<Intro>}\r\n'
          '[D]When the music fades\r\n',
    );

    controller.transposeUp();

    expect(controller.state.source, contains('{transpose: 1}\r\n'));
    expect(controller.state.source, contains('\r\n{comment:<Intro>}\r\n'));
  });

  test('directive updates match case-insensitive names and spaced colons', () {
    final controller = SongEditorController(
      source: '''
{title: Heart of Worship}
{Transpose : 2}
{CAPO : 3}
[D]When the music fades
''',
    );

    controller.transposeUp();
    controller.capoDown();

    expect(controller.state.parsedSong.baseTranspose, 3);
    expect(controller.state.parsedSong.baseCapo, 2);
    expect(controller.state.source, contains('{transpose: 3}'));
    expect(controller.state.source, contains('{capo: 2}'));
    expect(controller.state.source, isNot(contains('{Transpose : 2}')));
    expect(controller.state.source, isNot(contains('{CAPO : 3}')));
  });

  test('default source is non-copyrighted and parses as valid ChordPro', () {
    final controller = SongEditorController();
    final source = controller.state.source;

    // No copyrighted markers from the previous hardcoded worship song.
    expect(source, isNot(contains('Heart of Worship')));
    expect(source, isNot(contains('Matt Redman')));
    expect(source, isNot(contains('When the music fades')));

    // Still a valid, parseable ChordPro sample with the placeholder title.
    expect(controller.state.parsedSong.title, 'My New Song');
  });

  test(
    'editor reads the last base transpose and capo before the lyric (E1)',
    () {
      final controller = SongEditorController(
        source: '{transpose: 1}\n{transpose: 3}\n{capo: 1}\n{capo: 2}\n[A]x\n',
      );

      expect(controller.state.parsedSong.baseTranspose, 3);
      expect(controller.state.parsedSong.baseCapo, 2);
    },
  );

  test('editor skips an invalid base transpose and uses the next (E2)', () {
    final controller = SongEditorController(
      source: '{transpose: x}\n{transpose: 2}\n[A]x\n',
    );

    expect(controller.state.parsedSong.baseTranspose, 2);

    controller.transposeUp();

    expect(controller.state.parsedSong.baseTranspose, 3);
  });

  group('base directive writes keep the reader and editor in step (E8)', () {
    const fixtures = <String, String>{
      'LF plain': '{title: T}\n{key: D}\n{transpose: 1}\n{capo: 2}\n[D]la\n',
      'section comment before base':
          '{title: T}\n{comment:<Intro>}\n{transpose: 2}\n{capo: 1}\n[D]la\n',
      'start_of_verse before base':
          '{start_of_verse}\n{transpose: 2}\n{capo: 1}\n[D]la\n{end_of_verse}\n',
      'base plus in-song directives':
          '{key: G}\n{transpose: 1}\n[G]la\n{transpose: 4}\n{capo: 5}\n{key: A}\n',
      'duplicates':
          '{transpose: 1}\n{capo: 2}\n{transpose: 5}\n{capo: 3}\n[C]la\n',
      'invalid values': '{transpose: x}\n{capo: -1}\n{transpose: 2}\n[C]la\n',
      'tab before lyric':
          '{title: T}\n{start_of_tab}\n{transpose: 9}\n{capo: 7}\n'
          '{end_of_tab}\n[C]la\n',
      'no directives': '[C]la\n[G]di\n',
      'directives only': '{title: T}\n{transpose: 2}\n{capo: 1}\n',
      'directives only no final newline': '{title: T}\n{transpose: 2}',
      'CRLF with in-song directive':
          '{title: T}\r\n{transpose: 1}\r\n[C]la\r\n{transpose: 7}\r\n',
      'mixed LF and CRLF':
          '{title: T}\n{key: C}\r\n{transpose: 1}\n[C]la\r\n{capo: 3}\n',
      'lone CR': '{title: T}\r{transpose: 1}\r[C]la\r',
      'no final newline': '{title: T}\n[C]la',
    };

    final actions = <String, void Function(SongEditorController)>{
      'transposeUp': (c) => c.transposeUp(),
      'transposeDown': (c) => c.transposeDown(),
      'capoUp': (c) => c.capoUp(),
      'capoDown': (c) => c.capoDown(),
    };

    for (final fixture in fixtures.entries) {
      for (final action in actions.entries) {
        test('${fixture.key} / ${action.key}', () {
          final oldSource = fixture.value;
          final oldParsed = ChordproParser().parse(oldSource);
          final controller = SongEditorController(source: oldSource);

          action.value(controller);

          final newSource = controller.state.source;
          final newParsed = ChordproParser().parse(newSource);
          final state = controller.state.parsedSong;

          // (a) editor state equals what the reader parses from the output.
          expect(state.baseTranspose, newParsed.baseTranspose);
          expect(state.baseCapo, newParsed.baseCapo);
          expect(state.sourceKey, newParsed.sourceKey);

          // (b) expected arithmetic.
          final expectedTranspose = switch (action.key) {
            'transposeUp' => oldParsed.baseTranspose + 1,
            'transposeDown' => oldParsed.baseTranspose - 1,
            _ => oldParsed.baseTranspose,
          };
          final expectedCapo = switch (action.key) {
            'capoUp' => oldParsed.baseCapo + 1,
            'capoDown' => math.max(0, oldParsed.baseCapo - 1),
            _ => oldParsed.baseCapo,
          };
          expect(newParsed.baseTranspose, expectedTranspose);
          expect(newParsed.baseCapo, expectedCapo);
          expect(newParsed.sourceKey, oldParsed.sourceKey);

          // (c) the suffix from the boundary line onwards is byte-identical.
          expect(_boundarySuffix(newSource), _boundarySuffix(oldSource));

          // (d) untouched lines keep their terminators.
          final oldRecords = _records(oldSource);
          final newRecords = _records(newSource);
          final oldTerminators = oldRecords.map((r) => r.$2).toList();
          final newTerminators = newRecords.map((r) => r.$2).toList();
          if (oldSource.contains('\r\n') && !oldSource.contains('\n\r')) {
            // Every old terminator survives in order in the new source.
            expect(
              _isSubsequence(oldTerminators, newTerminators),
              isTrue,
              reason: '$oldTerminators vs $newTerminators',
            );
          }
          if (fixture.key == 'CRLF with in-song directive') {
            expect(newSource.replaceAll('\r\n', ''), isNot(contains('\n')));
          }
          if (fixture.key == 'lone CR') {
            expect(newSource, contains(oldSource));
          }
        });
      }
    }

    test('a repeated transpose on a lone-CR source does not add lines', () {
      final controller = SongEditorController(
        source: '{title: T}\r{transpose: 1}\r[C]la\r',
      );

      controller.transposeUp();
      final afterFirst = controller.state.source;
      expect(controller.state.parsedSong.baseTranspose, 1);

      controller.transposeUp();

      expect(controller.state.parsedSong.baseTranspose, 2);
      expect(
        '{transpose:'.allMatches(controller.state.source).length,
        '{transpose:'.allMatches(afterFirst).length,
      );
    });

    test('record split matches the scanner line count', () {
      for (final source in fixtures.values) {
        expect(
          _records(source).length,
          ChordproLineScanner().scan(source).length,
          reason: source,
        );
      }
    });
  });
}

/// Splits [source] into (text, terminator) records using the scanner's line
/// model: `\n` separates lines, a preceding `\r` joins the terminator.
List<(String, String)> _records(String source) {
  final records = <(String, String)>[];
  var start = 0;
  for (var i = 0; i < source.length; i += 1) {
    if (source[i] != '\n') continue;
    final crlf = i > start && source[i - 1] == '\r';
    records.add((
      source.substring(start, crlf ? i - 1 : i),
      crlf ? '\r\n' : '\n',
    ));
    start = i + 1;
  }
  if (start < source.length) {
    records.add((source.substring(start), ''));
  }
  return records;
}

String _boundarySuffix(String source) {
  final lines = ChordproLineScanner().scan(source).toList();
  final boundary = ChordproBaseRegion.of(lines).boundaryLineNumber;
  if (boundary == null) return '';
  return _records(
    source,
  ).skip(boundary - 1).map((r) => '${r.$1}${r.$2}').join();
}

bool _isSubsequence(List<String> needle, List<String> haystack) {
  var n = 0;
  for (final item in haystack) {
    if (n < needle.length && needle[n] == item) n += 1;
  }
  return n == needle.length;
}
