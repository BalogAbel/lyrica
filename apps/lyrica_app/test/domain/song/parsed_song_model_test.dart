import 'package:flutter_test/flutter_test.dart';
import 'package:lyrica_app/src/domain/song/parsed_song.dart';

void main() {
  test('parsed song preserves metadata, sections, lines, and diagnostics', () {
    const song = ParsedSong(
      title: 'A forrásnál',
      subtitle: 'Ha szólsz megdobban a szív',
      sourceKey: 'E',
      sections: [
        SongSection(
          kind: SongSectionKind.verse,
          label: 'Verse',
          lines: [
            SongLine(
              segments: [
                LyricSegment(leadingChord: 'A', text: 'A forrásnál'),
                LyricSegment(text: ' állok én'),
              ],
            ),
          ],
        ),
      ],
      diagnostics: [
        ParseDiagnostic(
          severity: ParseDiagnosticSeverity.warning,
          message: 'Unknown directive',
          line: ParseDiagnosticLineMetadata(lineNumber: 12, columnNumber: 1),
          context: 'comment',
        ),
      ],
    );

    expect(song.title, 'A forrásnál');
    expect(song.subtitle, 'Ha szólsz megdobban a szív');
    expect(song.sourceKey, 'E');
    expect(song.sections.first.kind, SongSectionKind.verse);
    expect(song.sections.first.label, 'Verse');
    expect(song.sections.first.number, isNull);
    expect(song.sections.first.lines, hasLength(1));
    expect(song.sections.first.lines.single.segments, hasLength(2));
    expect(song.sections.first.lines.single.segments.first.leadingChord, 'A');
    expect(song.sections.first.lines.single.segments.first.text, 'A forrásnál');
    expect(song.sections.first.lines.single.segments.last.leadingChord, isNull);
    expect(song.sections.first.lines.single.segments.last.text, ' állok én');
    expect(song.diagnostics, hasLength(1));
    expect(song.diagnostics.single.severity, ParseDiagnosticSeverity.warning);
    expect(song.diagnostics.single.message, 'Unknown directive');
    expect(song.diagnostics.single.line.lineNumber, 12);
    expect(song.diagnostics.single.line.columnNumber, 1);
    expect(song.diagnostics.single.context, 'comment');
  });
}
