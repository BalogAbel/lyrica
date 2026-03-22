import 'package:flutter_test/flutter_test.dart';
import 'package:lyrica_app/src/infrastructure/song_library/chordpro/chordpro_parser.dart';

void main() {
  test('keeps parsing when it encounters an unknown directive', () {
    final parser = ChordproParser();

    final result = parser.parse('''
{title:Example Song}
{comment:<Verse>}
Line one
{unknown:token}
Line two
''');

    expect(result.song.sections, isNotEmpty);
    expect(result.song.sections.single.lines, hasLength(2));
    expect(result.diagnostics, hasLength(1));
    expect(result.diagnostics.single.severity.name, 'warning');
    expect(result.diagnostics.single.line.lineNumber, 4);
    expect(result.diagnostics.single.context, contains('unknown'));
    expect(result.hasRecoverableWarnings, isTrue);
  });
}
