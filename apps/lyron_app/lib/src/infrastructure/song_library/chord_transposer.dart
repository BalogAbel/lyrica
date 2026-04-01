import 'package:lyron_app/src/domain/song/chord_symbol.dart';

class ChordTransposer {
  const ChordTransposer();

  String transpose(String chord, int semitoneOffset) {
    return ChordSymbol.parse(chord).transpose(semitoneOffset).displayName;
  }
}
