import 'package:lyron_app/src/infrastructure/song_library/chordpro/chordpro_line_scanner.dart';
import 'package:lyron_app/src/presentation/song_editor/song_editor_directives.dart';
import 'package:lyron_app/src/presentation/song_editor/song_editor_state.dart';

class SongEditorController {
  SongEditorController({
    String source = defaultSource,
    SongEditorCanonicalViewMode canonicalViewMode =
        SongEditorCanonicalViewMode.source,
  }) : _state = SongEditorState(
         source: source,
         canonicalViewMode: canonicalViewMode,
       );

  static const defaultSource = '''
{title: Heart of Worship}
{artist: Matt Redman}
{key: D}
{tempo: 72}
{tags: worship, acoustic}
{transpose: 0}
{capo: 0}

{comment: Verse 1}
[D]When the music fades
[A]And all is stripped away
[Bm]And I simply come
[G]Longing just to bring
''';

  SongEditorState _state;

  SongEditorState get state => _state;

  void setSource(String source) {
    _state = _state.copyWith(source: source);
  }

  void setCanonicalViewMode(SongEditorCanonicalViewMode mode) {
    _state = _state.copyWith(canonicalViewMode: mode);
  }

  void toggleCanonicalViewMode() {
    setCanonicalViewMode(
      _state.canonicalViewMode == SongEditorCanonicalViewMode.source
          ? SongEditorCanonicalViewMode.preview
          : SongEditorCanonicalViewMode.source,
    );
  }

  void transposeUp() {
    _state = _state.copyWith(
      source: _upsertDirective(
        _state.source,
        directiveName: 'transpose',
        value: currentPreLyricDirectiveInt(_state.source, 'transpose') + 1,
      ),
    );
  }

  void transposeDown() {
    _state = _state.copyWith(
      source: _upsertDirective(
        _state.source,
        directiveName: 'transpose',
        value: currentPreLyricDirectiveInt(_state.source, 'transpose') - 1,
      ),
    );
  }

  void capoUp() {
    _state = _state.copyWith(
      source: _upsertDirective(
        _state.source,
        directiveName: 'capo',
        value: currentPreLyricDirectiveInt(_state.source, 'capo') + 1,
      ),
    );
  }

  void capoDown() {
    _state = _state.copyWith(
      source: _upsertDirective(
        _state.source,
        directiveName: 'capo',
        value: currentPreLyricDirectiveInt(_state.source, 'capo') - 1,
        clampAtZero: true,
      ),
    );
  }
}

String _upsertDirective(
  String source, {
  required String directiveName,
  required int value,
  bool clampAtZero = false,
}) {
  final adjustedValue = clampAtZero && value < 0 ? 0 : value;
  final lineEnding = _detectLineEnding(source);
  final lines = source.split(RegExp(r'\r\n?|\n'));
  final directive = '{$directiveName: $adjustedValue}';
  final regex = RegExp('^\\s*\\{\\s*$directiveName\\s*:', caseSensitive: false);
  final firstLyricIndex = _firstLyricLineIndex(lines);
  final insertionIndex = _baseDirectiveInsertionIndex(lines);
  final matchingIndices = <int>[
    for (var index = 0; index < lines.length; index += 1)
      if (regex.hasMatch(lines[index])) index,
  ];
  final preLyricIndex = matchingIndices.firstWhere(
    (index) => index < firstLyricIndex,
    orElse: () => -1,
  );

  if (preLyricIndex >= 0) {
    lines[preLyricIndex] = directive;
    for (final index in matchingIndices.reversed) {
      if (index != preLyricIndex) {
        lines.removeAt(index);
      }
    }
    return lines.join(lineEnding);
  }

  for (final index in matchingIndices.reversed) {
    lines.removeAt(index);
  }

  if (insertionIndex < lines.length) {
    lines.insert(insertionIndex, directive);
  } else if (source.trim().isEmpty) {
    return directive;
  } else {
    lines.add(directive);
  }

  return lines.join(lineEnding);
}

String _detectLineEnding(String source) {
  if (source.contains('\r\n')) {
    return '\r\n';
  }
  if (source.contains('\r')) {
    return '\r';
  }
  return '\n';
}

int _baseDirectiveInsertionIndex(List<String> lines) {
  var lastMetadataIndex = -1;
  for (var index = 0; index < lines.length; index += 1) {
    final trimmed = lines[index].trim();
    if (trimmed.isEmpty) {
      continue;
    }

    final line = ChordproLineScanner().scan(trimmed).first;
    if (line.kind == ChordproLineKind.lyric) {
      return lastMetadataIndex >= 0 ? lastMetadataIndex + 1 : index;
    }

    if (_isEditorMetadataDirective(line.directiveName)) {
      lastMetadataIndex = index;
      continue;
    }

    return lastMetadataIndex >= 0 ? lastMetadataIndex + 1 : index;
  }

  return lastMetadataIndex >= 0 ? lastMetadataIndex + 1 : lines.length;
}

bool _isEditorMetadataDirective(String? directiveName) {
  return switch (directiveName) {
    'title' ||
    'subtitle' ||
    'artist' ||
    'key' ||
    'tempo' ||
    'tags' ||
    'transpose' ||
    'capo' => true,
    _ => false,
  };
}

int _firstLyricLineIndex(List<String> lines) {
  for (var index = 0; index < lines.length; index += 1) {
    final trimmed = lines[index].trim();
    if (trimmed.isEmpty || trimmed.startsWith('{')) {
      continue;
    }

    return index;
  }

  return lines.length;
}
