import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';

void main() {
  group('SongReaderState font scale bounds', () {
    test('exposes minSharedFontScale constant', () {
      expect(SongReaderState.minSharedFontScale, 0.25);
    });

    test('exposes maxSharedFontScale constant', () {
      expect(SongReaderState.maxSharedFontScale, 3.0);
    });

    test('exposes defaultSharedFontScale constant', () {
      expect(SongReaderState.defaultSharedFontScale, 1.0);
    });

    test('clamps 0.1 to minSharedFontScale', () {
      expect(
        SongReaderState(sharedFontScale: 0.1).sharedFontScale,
        SongReaderState.minSharedFontScale,
      );
    });

    test('passes through 0.25 (min boundary)', () {
      expect(SongReaderState(sharedFontScale: 0.25).sharedFontScale, 0.25);
    });

    test('passes through 2.5 (mid-range)', () {
      expect(SongReaderState(sharedFontScale: 2.5).sharedFontScale, 2.5);
    });

    test('passes through 3.0 (max boundary)', () {
      expect(SongReaderState(sharedFontScale: 3.0).sharedFontScale, 3.0);
    });

    test('clamps 5.0 to maxSharedFontScale', () {
      expect(
        SongReaderState(sharedFontScale: 5.0).sharedFontScale,
        SongReaderState.maxSharedFontScale,
      );
    });

    test('clamps 0 to defaultSharedFontScale', () {
      expect(
        SongReaderState(sharedFontScale: 0).sharedFontScale,
        SongReaderState.defaultSharedFontScale,
      );
    });

    test('clamps NaN to defaultSharedFontScale', () {
      expect(
        SongReaderState(sharedFontScale: double.nan).sharedFontScale,
        SongReaderState.defaultSharedFontScale,
      );
    });
  });
}
