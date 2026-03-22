import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyrica_app/src/domain/song/parsed_song.dart';
import 'package:lyrica_app/src/infrastructure/song_library/chordpro/chordpro_parser.dart';

String _referenceSong(String fileName) {
  final path = '../../docs/examples/chordpro/$fileName';
  return File(path).readAsStringSync();
}

void main() {
  final parser = ChordproParser();

  test(
    'parses A forrásnál into ordered sections and preserves blank lines',
    () {
      final song = parser.parse(
        _referenceSong('a forrasnal - ha szolsz megdobban a sziv.pro'),
      );

      expect(song.title, 'A forrásnál');
      expect(song.subtitle, 'Ha szólsz megdobban a szív');
      expect(song.sourceKey, 'A');
      expect(song.sections.map((section) => section.label).toList(), [
        'Intro',
        'Verse',
        'Chorus',
        'Bridge',
      ]);
      expect(song.sections.first.kind, SongSectionKind.other);
      expect(song.sections.first.lines, hasLength(2));
      expect(song.sections.first.lines.first.segments.first.leadingChord, 'A');
      expect(
        song.sections.first.lines.first.segments.last.leadingChord,
        'C#m/G#',
      );
      expect(song.sections.first.lines.last.segments.single.text, '');
      expect(song.sections[2].kind, SongSectionKind.chorus);
      expect(song.sections[2].lines, isNotEmpty);
      expect(song.sections[2].lines.first.segments.first.leadingChord, null);
      expect(
        song.sections[2].lines.first.segments.first.text,
        startsWith('A forrás'),
      );
      expect(song.diagnostics, isNotEmpty);
    },
  );

  test('parses A mi Istenünk with numbered verse and chorus sections', () {
    final song = parser.parse(
      _referenceSong(
        'a mi istenunk (leborulok elotted) - kegyelmed eleg tobb mint eleg.pro',
      ),
    );

    expect(song.title, 'A mi Istenünk (Leborulok előtted)');
    expect(song.subtitle, 'Kegyelmed elég több mint elég');
    expect(song.sourceKey, 'E');
    expect(song.sections.map((section) => section.label).toList(), [
      'Intro',
      'Verse',
      'Chorus',
      'Verse',
      'Chorus',
      'Bridge',
    ]);
    expect(song.sections[0].kind, SongSectionKind.other);
    expect(song.sections[0].lines.first.segments.first.leadingChord, 'E');
    expect(song.sections[1].number, 1);
    expect(song.sections[2].kind, SongSectionKind.chorus);
    expect(song.sections[2].number, 1);
    expect(song.sections[2].lines, isNotEmpty);
    expect(
      song.sections[2].lines.any(
        (line) => line.segments.first.leadingChord == '(B)',
      ),
      isTrue,
    );
    expect(
      song.sections[2].lines.any(
        (line) =>
            line.segments.any((segment) => segment.leadingChord == 'E/G#'),
      ),
      isTrue,
    );
    expect(
      song.sections[2].lines.any(
        (line) => line.segments.any((segment) => segment.leadingChord == 'A'),
      ),
      isTrue,
    );
    expect(song.sections[3].number, 2);
    expect(song.sections[5].kind, SongSectionKind.bridge);
    expect(song.diagnostics, isNotEmpty);
  });

  test('parses Egy út with all supported section types', () {
    final song = parser.parse(_referenceSong('egy ut - one way.pro'));

    expect(song.title, 'Egy út');
    expect(song.subtitle, 'One Way');
    expect(song.sourceKey, 'B');
    expect(song.sections.map((section) => section.label).toList(), [
      'Verse',
      'Verse',
      'Chorus',
      'Bridge',
    ]);
    expect(song.sections[0].number, 1);
    expect(song.sections[1].number, 2);
    expect(song.sections[2].kind, SongSectionKind.chorus);
    expect(song.sections[2].lines, isNotEmpty);
    expect(
      song.sections[2].lines.any(
        (line) => line.segments.first.leadingChord == 'B',
      ),
      isTrue,
    );
    expect(
      song.sections[2].lines.any(
        (line) => line.segments.any((segment) => segment.leadingChord == 'F#'),
      ),
      isTrue,
    );
    expect(
      song.sections[2].lines.any(
        (line) => line.segments.first.leadingChord == 'G#m',
      ),
      isTrue,
    );
    expect(
      song.sections[2].lines.any(
        (line) => line.segments.any((segment) => segment.leadingChord == '(B)'),
      ),
      isTrue,
    );
    expect(song.sections[3].kind, SongSectionKind.bridge);
    expect(song.sections[3].lines.first.segments.first.leadingChord, 'B');
    expect(song.diagnostics, isNotEmpty);
  });
}
