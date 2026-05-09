import 'package:lyron_app/src/infrastructure/song_library/chordpro/chordpro_line_scanner.dart';

int currentPreLyricDirectiveInt(String source, String directiveName) {
  for (final line in ChordproLineScanner().scan(source)) {
    if (line.kind == ChordproLineKind.lyric) {
      break;
    }

    if (line.kind == ChordproLineKind.directive &&
        line.directiveName == directiveName) {
      return int.tryParse(line.directiveValue?.trim() ?? '') ?? 0;
    }
  }

  return 0;
}
