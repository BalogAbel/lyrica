enum ParseDiagnosticSeverity { info, warning, error }

class ParseDiagnosticLineMetadata {
  const ParseDiagnosticLineMetadata({
    required this.lineNumber,
    this.columnNumber,
  });

  final int lineNumber;
  final int? columnNumber;

  @override
  bool operator ==(Object other) {
    return other is ParseDiagnosticLineMetadata &&
        other.lineNumber == lineNumber &&
        other.columnNumber == columnNumber;
  }

  @override
  int get hashCode => Object.hash(lineNumber, columnNumber);
}

class ParseDiagnostic {
  const ParseDiagnostic({
    required this.severity,
    required this.message,
    required this.line,
  });

  final ParseDiagnosticSeverity severity;
  final String message;
  final ParseDiagnosticLineMetadata line;

  @override
  bool operator ==(Object other) {
    return other is ParseDiagnostic &&
        other.severity == severity &&
        other.message == message &&
        other.line == line;
  }

  @override
  int get hashCode => Object.hash(severity, message, line);
}
