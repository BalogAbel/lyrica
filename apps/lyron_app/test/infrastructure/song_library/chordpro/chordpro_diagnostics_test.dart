import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/song_library/song_reader_result.dart';
import 'package:lyron_app/src/domain/song/song_line.dart';
import 'package:lyron_app/src/infrastructure/song_library/chordpro/chordpro_parser.dart';

void main() {
  test('unknown directive produces a DirectiveLine and no diagnostic', () {
    final parser = ChordproParser();

    final song = parser.parse('''
{title:Example Song}
{comment:<Verse>}
Line one
{unknown:token}
Line two
''');

    expect(song.sections.single.lines, hasLength(3));
    expect(song.sections.single.lines[1], isA<DirectiveLine>());
    final directive = song.sections.single.lines[1] as DirectiveLine;
    expect(directive.name, 'unknown');
    expect(directive.value, 'token');
    expect(song.diagnostics, isEmpty);
  });
}
