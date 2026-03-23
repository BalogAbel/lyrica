import 'package:lyrica_app/src/domain/song/parsed_song.dart';
import 'package:lyrica_app/src/infrastructure/song_library/chordpro/chordpro_line_scanner.dart';

class ChordproParser {
  ChordproParser({ChordproLineScanner? lineScanner})
    : _lineScanner = lineScanner ?? ChordproLineScanner();

  final ChordproLineScanner _lineScanner;

  ParsedSong parse(String source) {
    var title = '';
    String? subtitle;
    String? sourceKey;
    final sections = <_SectionBuilder>[];
    final diagnostics = <ParseDiagnostic>[];
    _SectionBuilder? currentSection;

    for (final line in _lineScanner.scan(source)) {
      if (line.kind == ChordproLineKind.empty) {
        if (currentSection != null) {
          currentSection.lines.add(
            SongLine(segments: const [LyricSegment(text: '')]),
          );
        }
      } else if (line.kind == ChordproLineKind.lyric) {
        currentSection = _ensureSection(
          sections: sections,
          currentSection: currentSection,
          kind: SongSectionKind.other,
          label: 'Unlabeled',
        );
        currentSection.lines.add(SongLine(segments: _parseLyricLine(line.raw)));
      } else {
        final directiveName = line.directiveName ?? '';
        if (directiveName == 'title') {
          title = line.directiveValue ?? '';
        } else if (directiveName == 'subtitle') {
          subtitle = line.directiveValue;
        } else if (directiveName == 'key') {
          sourceKey = line.directiveValue;
        } else if (directiveName == 'comment') {
          final commentValue = line.directiveValue ?? '';
          final parsedSection = _parseCommentSection(commentValue);
          if (parsedSection == null) {
            diagnostics.add(
              ParseDiagnostic(
                severity: ParseDiagnosticSeverity.warning,
                message: 'Unsupported comment content: $commentValue',
                line: ParseDiagnosticLineMetadata(
                  lineNumber: line.lineNumber,
                  columnNumber: 1,
                ),
                context: 'comment:$commentValue',
              ),
            );
          } else if (!_isSameSection(currentSection, parsedSection)) {
            sections.add(parsedSection);
            currentSection = parsedSection;
          }
        } else if (directiveName == 'start_of_chorus') {
          if (currentSection?.kind != SongSectionKind.chorus) {
            final chorusSection = _SectionBuilder(
              kind: SongSectionKind.chorus,
              label: 'Chorus',
            );
            sections.add(chorusSection);
            currentSection = chorusSection;
          }
        } else if (directiveName == 'end_of_chorus') {
          if (currentSection?.kind == SongSectionKind.chorus) {
            currentSection = null;
          }
        } else {
          diagnostics.add(
            ParseDiagnostic(
              severity: ParseDiagnosticSeverity.warning,
              message: 'Unsupported directive: $directiveName',
              line: ParseDiagnosticLineMetadata(
                lineNumber: line.lineNumber,
                columnNumber: 1,
              ),
              context: line.raw.trim(),
            ),
          );
        }
      }
    }

    return ParsedSong(
      title: title,
      subtitle: subtitle,
      sourceKey: sourceKey,
      sections: sections
          .map((section) => section.build())
          .toList(growable: false),
      diagnostics: diagnostics,
    );
  }

  _SectionBuilder _ensureSection({
    required List<_SectionBuilder> sections,
    required _SectionBuilder? currentSection,
    required SongSectionKind kind,
    required String label,
  }) {
    if (currentSection != null) {
      return currentSection;
    }

    final section = _SectionBuilder(kind: kind, label: label);
    sections.add(section);
    return section;
  }

  bool _isSameSection(_SectionBuilder? left, _SectionBuilder right) {
    if (left == null) {
      return false;
    }

    return left.kind == right.kind &&
        left.label == right.label &&
        left.number == right.number;
  }

  _SectionBuilder? _parseCommentSection(String directiveValue) {
    final match = RegExp(
      r'^<\s*([A-Za-z]+)(?:\s+(\d+))?\s*>$',
    ).firstMatch(directiveValue);
    if (match == null) {
      return null;
    }

    final label = match.group(1)!;
    final number = match.group(2) == null ? null : int.parse(match.group(2)!);
    switch (label.toLowerCase()) {
      case 'verse':
        return _SectionBuilder(
          kind: SongSectionKind.verse,
          label: 'Verse',
          number: number,
        );
      case 'chorus':
        return _SectionBuilder(
          kind: SongSectionKind.chorus,
          label: 'Chorus',
          number: number,
        );
      case 'bridge':
        if (number != null) {
          return null;
        }
        return _SectionBuilder(kind: SongSectionKind.bridge, label: 'Bridge');
      case 'intro':
        if (number != null) {
          return null;
        }
        return _SectionBuilder(kind: SongSectionKind.other, label: 'Intro');
      default:
        return null;
    }
  }

  List<LyricSegment> _parseLyricLine(String rawLine) {
    final segments = <LyricSegment>[];
    var scanIndex = 0;
    String? pendingChord;
    var segmentStart = 0;

    while (scanIndex < rawLine.length) {
      if (rawLine.codeUnitAt(scanIndex) != 0x5B) {
        scanIndex++;
        continue;
      }

      final closingIndex = rawLine.indexOf(']', scanIndex + 1);
      if (closingIndex == -1) {
        break;
      }

      final text = rawLine.substring(segmentStart, scanIndex);
      if (pendingChord == null) {
        if (text.isNotEmpty || segments.isNotEmpty) {
          segments.add(LyricSegment(text: text));
        }
      } else {
        segments.add(LyricSegment(leadingChord: pendingChord, text: text));
      }

      pendingChord = rawLine.substring(scanIndex + 1, closingIndex);
      segmentStart = closingIndex + 1;
      scanIndex = closingIndex + 1;
    }

    final trailingText = rawLine.substring(segmentStart);
    if (pendingChord == null) {
      segments.add(LyricSegment(text: trailingText));
    } else {
      segments.add(
        LyricSegment(leadingChord: pendingChord, text: trailingText),
      );
    }

    return segments;
  }
}

class _SectionBuilder {
  _SectionBuilder({required this.kind, required this.label, this.number});

  final SongSectionKind kind;
  final String label;
  final int? number;
  final List<SongLine> lines = <SongLine>[];

  SongSection build() {
    return SongSection(kind: kind, label: label, number: number, lines: lines);
  }
}
