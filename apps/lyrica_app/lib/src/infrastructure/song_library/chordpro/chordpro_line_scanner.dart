enum ChordproLineKind { empty, lyric, directive }

class ChordproLine {
  const ChordproLine({
    required this.lineNumber,
    required this.raw,
    required this.kind,
    this.directiveName,
    this.directiveValue,
  });

  final int lineNumber;
  final String raw;
  final ChordproLineKind kind;
  final String? directiveName;
  final String? directiveValue;

  bool get isDirective => kind == ChordproLineKind.directive;
}

class ChordproLineScanner {
  Iterable<ChordproLine> scan(String source) sync* {
    final normalizedSource = source.replaceAll('\r\n', '\n');
    final lines = normalizedSource.split('\n');
    final effectiveLength =
        lines.isNotEmpty &&
            normalizedSource.endsWith('\n') &&
            lines.last.isEmpty
        ? lines.length - 1
        : lines.length;

    for (var index = 0; index < effectiveLength; index++) {
      final rawLine = lines[index];
      final lineNumber = index + 1;
      final trimmed = rawLine.trim();

      if (trimmed.isEmpty) {
        yield ChordproLine(
          lineNumber: lineNumber,
          raw: rawLine,
          kind: ChordproLineKind.empty,
        );
        continue;
      }

      final directive = _parseDirective(trimmed);
      if (directive != null) {
        yield ChordproLine(
          lineNumber: lineNumber,
          raw: rawLine,
          kind: ChordproLineKind.directive,
          directiveName: directive.name,
          directiveValue: directive.value,
        );
        continue;
      }

      yield ChordproLine(
        lineNumber: lineNumber,
        raw: rawLine,
        kind: ChordproLineKind.lyric,
      );
    }
  }

  _Directive? _parseDirective(String trimmedLine) {
    if (!trimmedLine.startsWith('{') || !trimmedLine.endsWith('}')) {
      return null;
    }

    final body = trimmedLine.substring(1, trimmedLine.length - 1).trim();
    if (body.isEmpty) {
      return null;
    }

    final separatorIndex = body.indexOf(':');
    if (separatorIndex == -1) {
      return _Directive(name: body.toLowerCase(), value: null);
    }

    final name = body.substring(0, separatorIndex).trim().toLowerCase();
    final value = body.substring(separatorIndex + 1).trim();
    return _Directive(name: name, value: value);
  }
}

class _Directive {
  const _Directive({required this.name, required this.value});

  final String name;
  final String? value;
}
