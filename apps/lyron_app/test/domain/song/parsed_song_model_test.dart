import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/domain/song/parsed_song.dart';

void main() {
  test('parsed song preserves metadata, sections, lines, and diagnostics', () {
    final segments = [
      LyricSegment(leadingChord: 'A', text: 'A forrásnál'),
      LyricSegment(text: ' állok én'),
    ];
    final lines = [SongLine(segments: segments)];
    final sections = [
      SongSection(kind: SongSectionKind.verse, label: 'Verse', lines: lines),
    ];
    final diagnostics = [
      ParseDiagnostic(
        severity: ParseDiagnosticSeverity.warning,
        message: 'Unknown directive',
        line: ParseDiagnosticLineMetadata(lineNumber: 12, columnNumber: 1),
        context: 'comment',
      ),
    ];

    final song = ParsedSong(
      title: 'A forrásnál',
      subtitle: 'Ha szólsz megdobban a szív',
      sourceKey: 'E',
      sections: sections,
      diagnostics: diagnostics,
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

    expect(
      () => song.sections.add(
        SongSection(
          kind: SongSectionKind.bridge,
          label: 'Bridge',
          lines: const [],
        ),
      ),
      throwsUnsupportedError,
    );
    expect(
      () => song.sections.first.lines.add(SongLine(segments: [])),
      throwsUnsupportedError,
    );
    expect(
      () => song.sections.first.lines.first.segments.add(
        LyricSegment(text: 'extra'),
      ),
      throwsUnsupportedError,
    );

    sections.add(
      SongSection(
        kind: SongSectionKind.bridge,
        label: 'Bridge',
        lines: const [],
      ),
    );
    lines.add(SongLine(segments: []));
    segments.add(LyricSegment(text: 'extra'));
    diagnostics.add(
      ParseDiagnostic(
        severity: ParseDiagnosticSeverity.info,
        message: 'Added later',
        line: const ParseDiagnosticLineMetadata(lineNumber: 99),
      ),
    );

    expect(song.sections, hasLength(1));
    expect(song.sections.first.lines, hasLength(1));
    expect(song.sections.first.lines.first.segments, hasLength(2));
    expect(song.diagnostics, hasLength(1));
    expect(
      () => song.diagnostics.add(
        ParseDiagnostic(
          severity: ParseDiagnosticSeverity.info,
          message: 'later',
          line: const ParseDiagnosticLineMetadata(lineNumber: 13),
        ),
      ),
      throwsUnsupportedError,
    );
  });

  test('parsed song value types implement equality and hashCode', () {
    final lyricSegment = LyricSegment(leadingChord: 'A', text: 'Grace');
    final matchingLyricSegment = LyricSegment(leadingChord: 'A', text: 'Grace');
    final differentLyricSegment = LyricSegment(
      leadingChord: 'B',
      text: 'Grace',
    );

    expect(lyricSegment, matchingLyricSegment);
    expect(lyricSegment.hashCode, matchingLyricSegment.hashCode);
    expect(lyricSegment, isNot(differentLyricSegment));

    final songLine = SongLine(
      segments: [
        lyricSegment,
        LyricSegment(text: ' alone'),
      ],
    );
    final matchingSongLine = SongLine(
      segments: [
        matchingLyricSegment,
        LyricSegment(text: ' alone'),
      ],
    );
    final differentSongLine = SongLine(segments: [LyricSegment(text: 'alone')]);

    expect(songLine, matchingSongLine);
    expect(songLine.hashCode, matchingSongLine.hashCode);
    expect(songLine, isNot(differentSongLine));

    final songSection = SongSection(
      kind: SongSectionKind.chorus,
      label: 'Chorus',
      number: 2,
      lines: [songLine],
    );
    final matchingSongSection = SongSection(
      kind: SongSectionKind.chorus,
      label: 'Chorus',
      number: 2,
      lines: [matchingSongLine],
    );
    final differentSongSection = SongSection(
      kind: SongSectionKind.chorus,
      label: 'Chorus',
      number: 3,
      lines: [matchingSongLine],
    );

    expect(songSection, matchingSongSection);
    expect(songSection.hashCode, matchingSongSection.hashCode);
    expect(songSection, isNot(differentSongSection));

    const lineMetadata = ParseDiagnosticLineMetadata(
      lineNumber: 7,
      columnNumber: 3,
    );
    const matchingLineMetadata = ParseDiagnosticLineMetadata(
      lineNumber: 7,
      columnNumber: 3,
    );
    const differentLineMetadata = ParseDiagnosticLineMetadata(lineNumber: 8);

    expect(lineMetadata, matchingLineMetadata);
    expect(lineMetadata.hashCode, matchingLineMetadata.hashCode);
    expect(lineMetadata, isNot(differentLineMetadata));

    final parseDiagnostic = ParseDiagnostic(
      severity: ParseDiagnosticSeverity.warning,
      message: 'Unsupported directive',
      line: lineMetadata,
      context: 'soc',
    );
    final matchingParseDiagnostic = ParseDiagnostic(
      severity: ParseDiagnosticSeverity.warning,
      message: 'Unsupported directive',
      line: matchingLineMetadata,
      context: 'soc',
    );
    final differentParseDiagnostic = ParseDiagnostic(
      severity: ParseDiagnosticSeverity.error,
      message: 'Unsupported directive',
      line: matchingLineMetadata,
      context: 'soc',
    );

    expect(parseDiagnostic, matchingParseDiagnostic);
    expect(parseDiagnostic.hashCode, matchingParseDiagnostic.hashCode);
    expect(parseDiagnostic, isNot(differentParseDiagnostic));

    final parsedSong = ParsedSong(
      title: 'Amazing Grace',
      subtitle: 'Verse 1',
      sourceKey: 'G',
      sections: [songSection],
      diagnostics: [parseDiagnostic],
    );
    final matchingParsedSong = ParsedSong(
      title: 'Amazing Grace',
      subtitle: 'Verse 1',
      sourceKey: 'G',
      sections: [matchingSongSection],
      diagnostics: [matchingParseDiagnostic],
    );
    final differentParsedSong = ParsedSong(
      title: 'Amazing Grace',
      subtitle: 'Verse 1',
      sourceKey: 'A',
      sections: [matchingSongSection],
      diagnostics: [matchingParseDiagnostic],
    );

    expect(parsedSong, matchingParsedSong);
    expect(parsedSong.hashCode, matchingParsedSong.hashCode);
    expect(parsedSong, isNot(differentParsedSong));
  });
}
