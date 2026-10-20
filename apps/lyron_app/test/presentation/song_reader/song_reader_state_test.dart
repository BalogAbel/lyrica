import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/domain/song/song_key_layers.dart';
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

  group('SongReaderState temporary key layer', () {
    const layer = SongReaderTemporaryLayer(ownerId: 'item-1', transpose: 2);

    test('defaults to no temporary layer', () {
      expect(SongReaderState().temporaryLayer, isNull);
    });

    test('withTemporaryLayer sets and clears the layer', () {
      final withLayer = SongReaderState().withTemporaryLayer(layer);

      expect(withLayer.temporaryLayer, layer);
      expect(withLayer.withTemporaryLayer(null).temporaryLayer, isNull);
    });

    test('withTemporaryLayer keeps every other field', () {
      final state = SongReaderState(
        viewMode: SongReaderViewMode.lyricsOnly,
        instrumentDisplayMode: SongReaderInstrumentDisplayMode.piano,
        sharedFontScale: 1.4,
        areCompactControlsVisible: true,
        controlPresentationMode: SongReaderControlPresentationMode.pinned,
        isAutoFitEnabled: false,
      );

      expect(
        state.withTemporaryLayer(layer),
        SongReaderState(
          viewMode: SongReaderViewMode.lyricsOnly,
          instrumentDisplayMode: SongReaderInstrumentDisplayMode.piano,
          sharedFontScale: 1.4,
          areCompactControlsVisible: true,
          controlPresentationMode: SongReaderControlPresentationMode.pinned,
          isAutoFitEnabled: false,
          temporaryLayer: layer,
        ),
      );
    });

    test('copyWith of an unrelated field keeps the layer', () {
      final state = SongReaderState().withTemporaryLayer(layer);

      expect(
        state.copyWith(viewMode: SongReaderViewMode.lyricsOnly).temporaryLayer,
        layer,
      );
    });

    test('equality and hashCode include the layer', () {
      final a = SongReaderState().withTemporaryLayer(layer);
      final b = SongReaderState().withTemporaryLayer(
        const SongReaderTemporaryLayer(ownerId: 'item-1', transpose: 2),
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(SongReaderState()));
      expect(
        a,
        isNot(
          SongReaderState().withTemporaryLayer(
            const SongReaderTemporaryLayer(ownerId: 'item-1', transpose: 3),
          ),
        ),
      );
    });

    test('temporaryLayerFor returns null for another owner', () {
      final state = SongReaderState().withTemporaryLayer(layer);

      expect(state.temporaryLayerFor('item-1')?.transpose, 2);
      expect(state.temporaryLayerFor('item-2'), isNull);
      expect(SongReaderState().temporaryLayerFor('item-1'), isNull);
    });
  });

  group('SongReaderTemporaryLayer', () {
    test('valueOf reads the field', () {
      const layer = SongReaderTemporaryLayer(
        ownerId: 'x',
        transpose: 2,
        capo: 3,
      );

      expect(layer.valueOf(SongKeyField.transpose), 2);
      expect(layer.valueOf(SongKeyField.capo), 3);
    });

    test('withValue sets and clears one field and keeps the other', () {
      const layer = SongReaderTemporaryLayer(ownerId: 'x', transpose: 2);

      expect(
        layer.withValue(SongKeyField.capo, 4),
        const SongReaderTemporaryLayer(ownerId: 'x', transpose: 2, capo: 4),
      );
      expect(
        layer.withValue(SongKeyField.transpose, 5),
        const SongReaderTemporaryLayer(ownerId: 'x', transpose: 5),
      );
    });

    test('withValue returns null when both fields end up null', () {
      const layer = SongReaderTemporaryLayer(ownerId: 'x', transpose: 2);

      expect(layer.withValue(SongKeyField.transpose, null), isNull);
      expect(
        const SongReaderTemporaryLayer(
          ownerId: 'x',
          transpose: 2,
          capo: 1,
        ).withValue(SongKeyField.transpose, null),
        const SongReaderTemporaryLayer(ownerId: 'x', capo: 1),
      );
    });

    test('equality and hashCode cover owner and both fields', () {
      const a = SongReaderTemporaryLayer(ownerId: 'x', transpose: 1, capo: 2);
      const b = SongReaderTemporaryLayer(ownerId: 'x', transpose: 1, capo: 2);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(
        a,
        isNot(
          const SongReaderTemporaryLayer(ownerId: 'y', transpose: 1, capo: 2),
        ),
      );
      expect(
        a,
        isNot(
          const SongReaderTemporaryLayer(ownerId: 'x', transpose: 1, capo: 3),
        ),
      );
      expect(
        a,
        isNot(
          const SongReaderTemporaryLayer(ownerId: 'x', transpose: 2, capo: 2),
        ),
      );
    });
  });
}
