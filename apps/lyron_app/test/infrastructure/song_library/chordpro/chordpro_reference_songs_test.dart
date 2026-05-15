import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/domain/song/parsed_song.dart';
import 'package:lyron_app/src/domain/song/song_line.dart';
import 'package:lyron_app/src/infrastructure/song_library/chordpro/chordpro_parser.dart';

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
      final introFirstLine = song.sections.first.lines.first as LyricLine;
      expect(introFirstLine.segments.first.leadingChord, 'A');
      expect(
        introFirstLine.segments.last.leadingChord,
        'C#m/G#',
      );
      final introLastLine = song.sections.first.lines.last as LyricLine;
      expect(introLastLine.segments.single.text, '');
      expect(song.sections[2].kind, SongSectionKind.chorus);
      expect(song.sections[2].lines, isNotEmpty);
      final chorusFirstLine = song.sections[2].lines.first as LyricLine;
      expect(chorusFirstLine.segments.first.leadingChord, null);
      expect(
        chorusFirstLine.segments.first.text,
        startsWith('A forrás'),
      );
      expect(song.diagnostics, isEmpty);
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
      'Unlabeled',
      'Verse',
      'Chorus',
      'Verse',
      'Chorus',
      'Bridge',
    ]);
    expect(song.sections[0].kind, SongSectionKind.other);
    final unlabeledFirstLine = song.sections[0].lines.first as LyricLine;
    expect(unlabeledFirstLine.segments.first.leadingChord, 'E');
    expect(song.sections[1].number, 1);
    expect(song.sections[2].kind, SongSectionKind.chorus);
    expect(song.sections[2].number, 1);
    expect(song.sections[2].lines, isNotEmpty);
    expect(
      song.sections[2].lines.whereType<LyricLine>().any(
        (line) => line.segments.first.leadingChord == '(B)',
      ),
      isTrue,
    );
    expect(
      song.sections[2].lines.whereType<LyricLine>().any(
        (line) =>
            line.segments.any((segment) => segment.leadingChord == 'E/G#'),
      ),
      isTrue,
    );
    expect(
      song.sections[2].lines.whereType<LyricLine>().any(
        (line) => line.segments.any((segment) => segment.leadingChord == 'A'),
      ),
      isTrue,
    );
    expect(song.sections[3].number, 2);
    expect(song.sections[5].kind, SongSectionKind.bridge);
    expect(song.diagnostics, isEmpty);
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
      song.sections[2].lines.whereType<LyricLine>().any(
        (line) => line.segments.first.leadingChord == 'B',
      ),
      isTrue,
    );
    expect(
      song.sections[2].lines.whereType<LyricLine>().any(
        (line) => line.segments.any((segment) => segment.leadingChord == 'F#'),
      ),
      isTrue,
    );
    expect(
      song.sections[2].lines.whereType<LyricLine>().any(
        (line) => line.segments.first.leadingChord == 'G#m',
      ),
      isTrue,
    );
    expect(
      song.sections[2].lines.whereType<LyricLine>().any(
        (line) => line.segments.any((segment) => segment.leadingChord == '(B)'),
      ),
      isTrue,
    );
    expect(song.sections[3].kind, SongSectionKind.bridge);
    final bridgeFirstLine = song.sections[3].lines.first as LyricLine;
    expect(bridgeFirstLine.segments.first.leadingChord, 'B');
    // #-prefixed and //-prefixed comment directives now appear as CommentLine in Bridge
    expect(
      song.sections[3].lines.whereType<CommentLine>().map((c) => c.text).toList(),
      containsAll(<String>[
        '#Jonathan Douglass, Joel Houston (Hillsong)',
        '#Hegedűs Róbert (Dics-Suli 2006)',
        '//',
      ]),
    );
    expect(song.diagnostics, isEmpty);
  });
}
