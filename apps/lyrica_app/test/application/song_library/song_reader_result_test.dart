import 'package:flutter_test/flutter_test.dart';
import 'package:lyrica_app/src/application/song_library/song_reader_result.dart';
import 'package:lyrica_app/src/domain/song/parsed_song.dart';

void main() {
  test('derives warning state from diagnostics', () {
    final result = SongReaderResult(
      song: ParsedSong(
        title: 'Example Song',
        sections: const [],
        diagnostics: const [],
      ),
    );

    expect(result.song.title, 'Example Song');
    expect(result.diagnostics, isEmpty);
    expect(result.hasRecoverableWarnings, isFalse);
  });

  test('reports recoverable warnings when diagnostics contain warnings', () {
    final result = SongReaderResult(
      song: ParsedSong(
        title: 'Example Song',
        sections: const [],
        diagnostics: [
          ParseDiagnostic(
            severity: ParseDiagnosticSeverity.warning,
            message: 'Unknown directive',
            line: const ParseDiagnosticLineMetadata(lineNumber: 4),
            context: 'unknown:token',
          ),
        ],
      ),
    );

    expect(result.diagnostics.single.severity.name, 'warning');
    expect(result.hasRecoverableWarnings, isTrue);
  });
}
