import 'package:lyron_app/src/domain/song/parsed_song.dart';
import 'package:lyron_app/src/infrastructure/song_library/chordpro/chordpro_line_scanner.dart';

class ChordproParser {
  ChordproParser({ChordproLineScanner? lineScanner})
    : _lineScanner = lineScanner ?? ChordproLineScanner();

  final ChordproLineScanner _lineScanner;

  ParsedSong parse(String source) {
    var title = '';
    String? subtitle;
    String? artist;
    String? sourceKey;
    int? tempoBpm;
    var tags = const <String>[];
    var baseTranspose = 0;
    var baseCapo = 0;
    var hasSeenSongContent = false;
    final sections = <_SectionBuilder>[];
    final diagnostics = <ParseDiagnostic>[];
    _SectionBuilder? currentSection;

    for (final line in _lineScanner.scan(source)) {
      if (line.kind == ChordproLineKind.empty) {
        if (currentSection != null) {
          if (currentSection.kind == SongSectionKind.tab) {
            currentSection.appendTabLine('');
          } else {
            currentSection.lines.add(
              LyricLine(segments: const [LyricSegment(text: '')]),
            );
          }
        }
      } else if (line.kind == ChordproLineKind.lyric) {
        hasSeenSongContent = true;
        currentSection = _ensureSection(
          sections: sections,
          currentSection: currentSection,
          kind: SongSectionKind.other,
          label: 'Unlabeled',
        );
        if (currentSection.kind == SongSectionKind.tab) {
          currentSection.appendTabLine(line.raw);
        } else {
          currentSection.lines.add(LyricLine(segments: _parseLyricLine(line.raw)));
        }
      } else {
        final directiveName = line.directiveName ?? '';
        if (directiveName == 'title') {
          title = line.directiveValue ?? '';
        } else if (directiveName == 'subtitle') {
          subtitle = line.directiveValue;
        } else if (directiveName == 'artist') {
          artist = line.directiveValue?.trim();
        } else if (directiveName == 'key') {
          if (!hasSeenSongContent) {
            final normalizedKey = line.directiveValue?.trim();
            if (normalizedKey == null || normalizedKey.isEmpty) {
              diagnostics.add(
                ParseDiagnostic(
                  severity: ParseDiagnosticSeverity.warning,
                  message: 'Invalid key value: ${line.directiveValue ?? ''}',
                  line: ParseDiagnosticLineMetadata(
                    lineNumber: line.lineNumber,
                    columnNumber: 1,
                  ),
                  context: 'key:${line.directiveValue ?? ''}',
                ),
              );
            } else {
              sourceKey = normalizedKey;
            }
          }
        } else if (directiveName == 'capo') {
          if (!hasSeenSongContent) {
            final parsedCapo = _parseDirectiveInteger(
              directiveValue: line.directiveValue,
              directiveName: directiveName,
              lineNumber: line.lineNumber,
              diagnostics: diagnostics,
            );
            if (parsedCapo != null && parsedCapo >= 0) {
              baseCapo = parsedCapo;
            } else if (parsedCapo != null) {
              diagnostics.add(
                ParseDiagnostic(
                  severity: ParseDiagnosticSeverity.warning,
                  message: 'Invalid capo value: $parsedCapo',
                  line: ParseDiagnosticLineMetadata(
                    lineNumber: line.lineNumber,
                    columnNumber: 1,
                  ),
                  context: 'capo:$parsedCapo',
                ),
              );
            }
          }
        } else if (directiveName == 'transpose') {
          if (!hasSeenSongContent) {
            final parsedTranspose = _parseDirectiveInteger(
              directiveValue: line.directiveValue,
              directiveName: directiveName,
              lineNumber: line.lineNumber,
              diagnostics: diagnostics,
            );
            if (parsedTranspose != null) {
              baseTranspose = parsedTranspose;
            }
          }
        } else if (directiveName == 'tempo') {
          tempoBpm = _parseDirectiveInteger(
            directiveValue: line.directiveValue,
            directiveName: directiveName,
            lineNumber: line.lineNumber,
            diagnostics: diagnostics,
          );
        } else if (directiveName == 'tags' || directiveName == 'tag') {
          tags = _parseTags(line.directiveValue);
        } else if (directiveName == 't') {
          title = line.directiveValue ?? '';
        } else if (directiveName == 'st') {
          subtitle = line.directiveValue;
        } else if (directiveName == 'meta') {
          // silently ignored
        } else if (directiveName == 'comment') {
          final commentValue = line.directiveValue ?? '';
          final parsedSection = _parseCommentSection(commentValue);
          if (parsedSection != null) {
            if (!_isSameSection(currentSection, parsedSection)) {
              sections.add(parsedSection);
              currentSection = parsedSection;
              hasSeenSongContent = true;
            }
          } else {
            // Not a section header — inline comment line.
            final targetSection = _ensurePreambleOrCurrentSection(
              sections: sections,
              currentSection: currentSection,
            );
            currentSection = targetSection;
            targetSection.lines.add(CommentLine(text: commentValue));
          }
        } else if (directiveName.startsWith('start_of_')) {
          hasSeenSongContent = true;
          final sectionType = directiveName.substring('start_of_'.length);
          final labelOverride = line.directiveValue?.trim();

          switch (sectionType) {
            case 'chorus':
              if (currentSection?.kind != SongSectionKind.chorus) {
                final section = _SectionBuilder(
                  kind: SongSectionKind.chorus,
                  label: labelOverride ?? 'Chorus',
                );
                sections.add(section);
                currentSection = section;
              } else if (labelOverride != null) {
                // already in chorus but label override provided — still create new section
                final section = _SectionBuilder(
                  kind: SongSectionKind.chorus,
                  label: labelOverride,
                );
                sections.add(section);
                currentSection = section;
              }
            case 'verse':
              final section = _SectionBuilder(
                kind: SongSectionKind.verse,
                label: labelOverride ?? 'Verse',
              );
              sections.add(section);
              currentSection = section;
            case 'bridge':
              final section = _SectionBuilder(
                kind: SongSectionKind.bridge,
                label: labelOverride ?? 'Bridge',
              );
              sections.add(section);
              currentSection = section;
            case 'tab':
              final section = _SectionBuilder(
                kind: SongSectionKind.tab,
                label: labelOverride ?? 'Tab',
              );
              sections.add(section);
              currentSection = section;
            default:
              final section = _SectionBuilder(
                kind: SongSectionKind.unknown,
                label: labelOverride ?? sectionType,
              );
              sections.add(section);
              currentSection = section;
          }
        } else if (directiveName.startsWith('end_of_')) {
          hasSeenSongContent = true;
          currentSection = null;
        } else {
          final targetSection = _ensurePreambleOrCurrentSection(
            sections: sections,
            currentSection: currentSection,
          );
          currentSection = targetSection;
          targetSection.lines.add(
            DirectiveLine(name: directiveName, value: line.directiveValue?.trim()),
          );
        }
      }
    }

    return ParsedSong(
      title: title,
      subtitle: subtitle,
      artist: artist,
      sourceKey: sourceKey,
      tempoBpm: tempoBpm,
      tags: tags,
      baseTranspose: baseTranspose,
      baseCapo: baseCapo,
      sections: sections
          .map((section) => section.build())
          .toList(growable: false),
      diagnostics: diagnostics,
    );
  }

  _SectionBuilder _ensurePreambleOrCurrentSection({
    required List<_SectionBuilder> sections,
    required _SectionBuilder? currentSection,
  }) {
    if (currentSection != null && currentSection.kind != SongSectionKind.tab) {
      return currentSection;
    }
    final preamble = _SectionBuilder(
      kind: SongSectionKind.other,
      label: 'Unlabeled',
    );
    sections.add(preamble);
    return preamble;
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
    final normalizedValue = _normalizeCommentSectionValue(directiveValue);
    if (normalizedValue == null) return null;

    final match = RegExp(r'^([A-Za-z]+)\s*(\d+)?$').firstMatch(normalizedValue);
    if (match == null) return null;

    final labelWord = match.group(1)!;
    final number = match.group(2) == null ? null : int.parse(match.group(2)!);
    switch (labelWord.toLowerCase()) {
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
        return _SectionBuilder(
          kind: SongSectionKind.bridge,
          label: 'Bridge',
          number: number,
        );
      case 'intro':
        return _SectionBuilder(
          kind: SongSectionKind.other,
          label: 'Intro',
          number: number,
        );
      default:
        return _SectionBuilder(
          kind: SongSectionKind.unknown,
          label: labelWord,
          number: number,
        );
    }
  }

  String? _normalizeCommentSectionValue(String directiveValue) {
    final trimmed = directiveValue.trim();

    // Values with angle-bracket or square-bracket wrappers are section headers.
    if ((trimmed.startsWith('<') && trimmed.endsWith('>')) ||
        (trimmed.startsWith('[') && trimmed.endsWith(']'))) {
      var normalized = trimmed.substring(1, trimmed.length - 1).trim();
      // Unwrap additional layers if present.
      while ((normalized.startsWith('<') && normalized.endsWith('>')) ||
          (normalized.startsWith('[') && normalized.endsWith(']'))) {
        normalized = normalized.substring(1, normalized.length - 1).trim();
      }
      return normalized;
    }

    // Plain text without wrappers: treat as section header only if it looks
    // like a bare word/number (no special characters like / or #).
    if (!trimmed.contains('/') && !trimmed.contains('#')) {
      return trimmed;
    }

    return null;
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

  List<String> _parseTags(String? directiveValue) {
    if (directiveValue == null) {
      return const [];
    }

    final normalized = directiveValue
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList(growable: false);
    return List.unmodifiable(normalized);
  }

  int? _parseDirectiveInteger({
    required String? directiveValue,
    required String directiveName,
    required int lineNumber,
    required List<ParseDiagnostic> diagnostics,
  }) {
    if (directiveValue == null) {
      diagnostics.add(
        ParseDiagnostic(
          severity: ParseDiagnosticSeverity.warning,
          message: 'Invalid $directiveName value: ',
          line: ParseDiagnosticLineMetadata(
            lineNumber: lineNumber,
            columnNumber: 1,
          ),
          context: '$directiveName:',
        ),
      );
      return null;
    }

    final parsed = int.tryParse(directiveValue.trim());
    if (parsed == null) {
      diagnostics.add(
        ParseDiagnostic(
          severity: ParseDiagnosticSeverity.warning,
          message: 'Invalid $directiveName value: $directiveValue',
          line: ParseDiagnosticLineMetadata(
            lineNumber: lineNumber,
            columnNumber: 1,
          ),
          context: '$directiveName:$directiveValue',
        ),
      );
      return null;
    }

    return parsed;
  }
}

class _SectionBuilder {
  _SectionBuilder({required this.kind, required this.label, this.number});

  final SongSectionKind kind;
  final String label;
  final int? number;
  final List<SongLine> lines = <SongLine>[];
  final List<String> _pendingTabLines = <String>[];

  void appendTabLine(String rawLine) {
    _pendingTabLines.add(rawLine);
  }

  SongSection build() {
    final builtLines = List<SongLine>.from(lines);
    if (_pendingTabLines.isNotEmpty) {
      builtLines.add(TabBlock(rawLines: List.unmodifiable(_pendingTabLines)));
    }
    return SongSection(kind: kind, label: label, number: number, lines: builtLines);
  }
}
