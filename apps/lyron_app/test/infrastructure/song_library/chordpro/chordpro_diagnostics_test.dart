import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/song_library/song_reader_result.dart';
import 'package:lyron_app/src/infrastructure/song_library/chordpro/chordpro_parser.dart';

void main() {
  test('keeps parsing when it encounters an unknown directive', () {
    final parser = ChordproParser();

    final song = parser.parse('''
{title:Example Song}
{comment:<Verse>}
Line one
{unknown:token}
Line two
''');
    final result = SongReaderResult(song: song);

    expect(result.song.sections, isNotEmpty);
    expect(result.song.sections.single.lines, hasLength(2));
    expect(result.song.diagnostics, hasLength(1));
    expect(result.song.diagnostics.single.severity.name, 'warning');
    expect(result.song.diagnostics.single.line.lineNumber, 4);
    expect(result.song.diagnostics.single.context, contains('unknown'));
    expect(result.hasRecoverableWarnings, isTrue);
  });
}
