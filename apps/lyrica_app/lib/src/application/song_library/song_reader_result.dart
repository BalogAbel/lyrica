import 'package:lyrica_app/src/domain/song/parsed_song.dart';

class SongReaderResult {
  const SongReaderResult({required ParsedSong song}) : _song = song;

  final ParsedSong _song;

  ParsedSong get song => _song;
  String get title => _song.title;
  String? get subtitle => _song.subtitle;
  String? get sourceKey => _song.sourceKey;
  List<SongSection> get sections => _song.sections;
  List<ParseDiagnostic> get diagnostics => _song.diagnostics;

  bool get hasRecoverableWarnings {
    return diagnostics.any(
      (diagnostic) => diagnostic.severity == ParseDiagnosticSeverity.warning,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SongReaderResult && other._song == _song;
  }

  @override
  int get hashCode => _song.hashCode;
}
