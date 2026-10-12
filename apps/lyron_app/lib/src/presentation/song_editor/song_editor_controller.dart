import 'package:lyron_app/src/infrastructure/song_library/chordpro/chordpro_line_scanner.dart';
import 'package:lyron_app/src/infrastructure/song_library/chordpro/chordpro_normalizer.dart';
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
{title: My New Song}
{artist: }
{key: C}
{tempo: 120}
{tags: }
{transpose: 0}
{capo: 0}

{comment: Replace this sample with your own lyrics}
[C]Type a line of lyrics and put [G]chords in brackets
[Am]Delete these lines when you [F]start your song
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
        value: _state.parsedSong.baseTranspose + 1,
      ),
    );
  }

  void transposeDown() {
    _state = _state.copyWith(
      source: _upsertDirective(
        _state.source,
        directiveName: 'transpose',
        value: _state.parsedSong.baseTranspose - 1,
      ),
    );
  }

  void capoUp() {
    _state = _state.copyWith(
      source: _upsertDirective(
        _state.source,
        directiveName: 'capo',
        value: _state.parsedSong.baseCapo + 1,
      ),
    );
  }

  void capoDown() {
    _state = _state.copyWith(
      source: _upsertDirective(
        _state.source,
        directiveName: 'capo',
        value: _state.parsedSong.baseCapo - 1,
        clampAtZero: true,
      ),
    );
  }
}

/// Rewrites the base `{name: value}` directive of [source] (BD6).
///
/// Only lines in the base region (before the first song-content line) are
/// read or edited; everything from the boundary line onwards is copied
/// byte for byte. The source is split into line records with the scanner's
/// line model so every untouched line keeps its own terminator.
///
/// The region, the occurrences and the insertion index come from scanning
/// the normalized source (what the save path stores and the reader parses),
/// while the bytes are edited on the raw records. Normalization maps every
/// line to exactly one line, so record `i` is normalized scanner line
/// `i + 1`.
String _upsertDirective(
  String source, {
  required String directiveName,
  required int value,
  bool clampAtZero = false,
}) {
  final adjustedValue = clampAtZero && value < 0 ? 0 : value;
  final directive = '{$directiveName: $adjustedValue}';
  if (source.trim().isEmpty) {
    return directive;
  }

  final records = _splitLineRecords(source);
  final scanned = ChordproLineScanner()
      .scan(ChordproNormalizer().normalize(source))
      .toList();
  // Unreachable today: the normalizer maps each line to exactly one line, so
  // record i is always scanned line i + 1. This runtime check (not an
  // assert, which release builds skip) makes a future normalizer change that
  // breaks the mapping a no-op instead of an edit to the wrong line.
  if (records.length != scanned.length) {
    return source;
  }
  final region = ChordproBaseRegion.of(scanned);

  final occurrences = <int>[
    for (var index = 0; index < scanned.length; index += 1)
      if (scanned[index].kind == ChordproLineKind.directive &&
          scanned[index].directiveName == directiveName &&
          region.contains(scanned[index]) &&
          _isSingleDirective(scanned[index]))
        index,
  ];

  if (occurrences.isNotEmpty) {
    final keep = occurrences.last;
    records[keep] = _LineRecord(directive, records[keep].terminator);
    for (final index in occurrences.reversed) {
      if (index != keep) {
        records.removeAt(index);
      }
    }
    return _joinLineRecords(records);
  }

  final insertionIndex = _baseDirectiveInsertionIndex(scanned, region);
  final eol = source.contains('\r\n') ? '\r\n' : '\n';
  if (insertionIndex >= records.length) {
    final last = records.last;
    if (last.terminator.isEmpty) {
      records[records.length - 1] = _LineRecord(last.text, eol);
      records.add(_LineRecord(directive, ''));
    } else {
      records.add(_LineRecord(directive, eol));
    }
  } else {
    records.insert(insertionIndex, _LineRecord(directive, eol));
  }
  return _joinLineRecords(records);
}

/// Whether [line] holds one directive and nothing else. A brace inside the
/// value means other text shares the line (for example a lyric joined to it
/// by a lone `\r`); such a line is never rewritten or removed, and its
/// invalid value is already ignored by the parser.
bool _isSingleDirective(ChordproLine line) {
  final value = line.directiveValue ?? '';
  return !value.contains('{') && !value.contains('}');
}

class _LineRecord {
  const _LineRecord(this.text, this.terminator);

  final String text;
  final String terminator;
}

/// Splits [source] like [ChordproLineScanner.scan]: `\n` separates lines, a
/// preceding `\r` makes the terminator `\r\n` and is not part of the text,
/// a lone `\r` stays inside the line text, and a trailing segment without a
/// terminator is a record only when it is not empty.
List<_LineRecord> _splitLineRecords(String source) {
  final records = <_LineRecord>[];
  var start = 0;
  for (var index = 0; index < source.length; index += 1) {
    if (source.codeUnitAt(index) != 0x0A) {
      continue;
    }
    final crlf = index > start && source.codeUnitAt(index - 1) == 0x0D;
    records.add(
      _LineRecord(
        source.substring(start, crlf ? index - 1 : index),
        crlf ? '\r\n' : '\n',
      ),
    );
    start = index + 1;
  }
  if (start < source.length) {
    records.add(_LineRecord(source.substring(start), ''));
  }
  return records;
}

String _joinLineRecords(List<_LineRecord> records) {
  final buffer = StringBuffer();
  for (final record in records) {
    buffer
      ..write(record.text)
      ..write(record.terminator);
  }
  return buffer.toString();
}

/// Record index at which a new base directive goes: right after the leading
/// metadata block, before the first other directive or the base boundary.
int _baseDirectiveInsertionIndex(
  List<ChordproLine> lines,
  ChordproBaseRegion region,
) {
  var lastMetadataIndex = -1;
  for (var index = 0; index < lines.length; index += 1) {
    final line = lines[index];
    if (!region.contains(line)) {
      return lastMetadataIndex >= 0 ? lastMetadataIndex + 1 : index;
    }
    if (line.kind == ChordproLineKind.empty) {
      continue;
    }
    if (line.kind == ChordproLineKind.directive &&
        _isEditorMetadataDirective(line.directiveName)) {
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
