import 'package:flutter_test/flutter_test.dart';
import 'package:lyrica_app/src/domain/song/chord_symbol.dart';

void main() {
  test('parses major, minor, slash, and parenthesized chord symbols', () {
    final major = ChordSymbol.parse('E');
    final minor = ChordSymbol.parse('F#m');
    final slash = ChordSymbol.parse('E/G#');
    final parenthesized = ChordSymbol.parse('(B)');

    expect(major.rootNoteName, 'E');
    expect(major.qualitySuffix, isEmpty);
    expect(major.bassNoteName, isNull);
    expect(major.isParenthesized, isFalse);
    expect(major.displayName, 'E');

    expect(minor.rootNoteName, 'F#');
    expect(minor.qualitySuffix, 'm');
    expect(minor.bassNoteName, isNull);
    expect(minor.isParenthesized, isFalse);
    expect(minor.displayName, 'F#m');

    expect(slash.rootNoteName, 'E');
    expect(slash.qualitySuffix, isEmpty);
    expect(slash.bassNoteName, 'G#');
    expect(slash.isParenthesized, isFalse);
    expect(slash.displayName, 'E/G#');

    expect(parenthesized.rootNoteName, 'B');
    expect(parenthesized.qualitySuffix, isEmpty);
    expect(parenthesized.bassNoteName, isNull);
    expect(parenthesized.isParenthesized, isTrue);
    expect(parenthesized.displayName, '(B)');
  });

  test('transposes repeated semitone movement through the model', () {
    final chord = ChordSymbol.parse('F#m');

    expect(chord.transpose(1).displayName, 'Gm');
    expect(chord.transpose(2).displayName, 'G#m');
    expect(chord.transpose(-1).displayName, 'Fm');
  });
}
