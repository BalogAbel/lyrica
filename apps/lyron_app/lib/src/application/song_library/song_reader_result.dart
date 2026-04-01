import 'package:lyron_app/src/domain/song/parsed_song.dart';

class SongReaderResult {
  const SongReaderResult({required this.song});

  final ParsedSong song;

  bool get hasRecoverableWarnings {
    return song.diagnostics.any(
      (diagnostic) => diagnostic.severity == ParseDiagnosticSeverity.warning,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SongReaderResult && other.song == song;
  }

  @override
  int get hashCode => song.hashCode;
}
