import 'package:flutter_test/flutter_test.dart';
import 'package:lyrica_app/src/domain/song/parsed_song.dart';

void main() {
  test('parsed song preserves metadata, ordered sections, and diagnostics', () {
    const song = ParsedSong(
      title: 'A forrásnál',
      subtitle: 'Ha szólsz megdobban a szív',
      sections: [SongSection(kind: SongSectionKind.verse, label: 'Verse')],
      diagnostics: [],
    );

    expect(song.title, 'A forrásnál');
    expect(song.subtitle, 'Ha szólsz megdobban a szív');
    expect(song.sections.first.label, 'Verse');
    expect(song.sections.first.number, isNull);
    expect(song.diagnostics, isEmpty);
  });
}
