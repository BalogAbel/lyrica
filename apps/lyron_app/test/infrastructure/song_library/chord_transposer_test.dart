import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/infrastructure/song_library/chord_transposer.dart';

void main() {
  test('transposes major and minor chords', () {
    final transposer = ChordTransposer();

    expect(transposer.transpose('F#m', 1), 'Gm');
    expect(transposer.transpose('Am', -2), 'Gm');
  });

  test('transposes slash chords with bass notes', () {
    final transposer = ChordTransposer();

    expect(transposer.transpose('E/G#', -1), 'D#/G');
  });

  test('supports repeated semitone movement', () {
    final transposer = ChordTransposer();

    var chord = 'C';
    chord = transposer.transpose(chord, 1);
    chord = transposer.transpose(chord, 1);
    chord = transposer.transpose(chord, 1);

    expect(chord, 'D#');
  });
}
