import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/domain/song/parsed_song.dart';
import 'package:lyron_app/src/domain/song/song_key_layers.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_key_layers.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';

ParsedSong _song({int transpose = 0, int capo = 0}) => ParsedSong(
  title: 'Key song',
  baseTranspose: transpose,
  baseCapo: capo,
  sections: const [],
  diagnostics: const [],
);

ResolvedSongKeyField _at(int value, SongKeyLayerId source) =>
    ResolvedSongKeyField(value: value, source: source);

void main() {
  group('layersFor', () {
    test('orders temporary, plan, song inside a plan', () {
      final layers = const SongReaderKeyLayers(
        isPlanScoped: true,
        planTranspose: 3,
      ).layersFor(_song());

      expect(layers.map((layer) => layer.id), [
        SongKeyLayerId.temporary,
        SongKeyLayerId.plan,
        SongKeyLayerId.song,
      ]);
      expect(layers[0].isTransient, isTrue);
      expect(layers[1].isTransient, isFalse);
      expect(layers[1].transpose, 3);
      expect(layers[1].capo, isNull);
    });

    test('orders temporary, song outside a plan', () {
      final layers = SongReaderKeyLayers.baseOnly.layersFor(_song());

      expect(layers.map((layer) => layer.id), [
        SongKeyLayerId.temporary,
        SongKeyLayerId.song,
      ]);
    });

    test('keeps the temporary layer with null values when there is none', () {
      final layers = SongReaderKeyLayers.baseOnly.layersFor(_song());

      expect(layers.first.id, SongKeyLayerId.temporary);
      expect(layers.first.isTransient, isTrue);
      expect(layers.first.transpose, isNull);
      expect(layers.first.capo, isNull);
    });

    test('carries the temporary values', () {
      final layers = const SongReaderKeyLayers(
        temporary: SongReaderTemporaryLayer(
          ownerId: 'x',
          transpose: 2,
          capo: 4,
        ),
      ).layersFor(_song());

      expect(layers.first.transpose, 2);
      expect(layers.first.capo, 4);
    });
  });

  group('resolveFor', () {
    test('resolves the song base when nothing overrides it', () {
      final key = SongReaderKeyLayers.baseOnly.resolveFor(
        _song(transpose: 1, capo: 2),
      );

      expect(key.transpose, _at(1, SongKeyLayerId.song));
      expect(key.capo, _at(2, SongKeyLayerId.song));
    });

    test('floors the song capo at 0', () {
      final key = SongReaderKeyLayers.baseOnly.resolveFor(_song(capo: -2));

      expect(key.capo, _at(0, SongKeyLayerId.song));
    });

    test('shows an out-of-range song capo as it is', () {
      final key = SongReaderKeyLayers.baseOnly.resolveFor(_song(capo: 13));

      expect(key.capo, _at(13, SongKeyLayerId.song));
    });

    test('shows an out-of-range song transpose as it is', () {
      final key = SongReaderKeyLayers.baseOnly.resolveFor(_song(transpose: 14));

      expect(key.transpose, _at(14, SongKeyLayerId.song));
    });

    test('lets the temporary layer win over the song', () {
      final key = const SongReaderKeyLayers(
        temporary: SongReaderTemporaryLayer(ownerId: 'x', transpose: 3),
      ).resolveFor(_song());

      expect(key.transpose, _at(3, SongKeyLayerId.temporary));
      expect(key.capo, _at(0, SongKeyLayerId.song));
    });

    test('lets the plan values win over the song inside a plan', () {
      final key = const SongReaderKeyLayers(
        isPlanScoped: true,
        planTranspose: 3,
        planCapo: 2,
      ).resolveFor(_song(transpose: 1));

      expect(key.transpose, _at(3, SongKeyLayerId.plan));
      expect(key.capo, _at(2, SongKeyLayerId.plan));
    });

    test('ignores plan values outside a plan', () {
      final key = const SongReaderKeyLayers(
        planTranspose: 3,
      ).resolveFor(_song(transpose: 1));

      expect(key.transpose, _at(1, SongKeyLayerId.song));
    });
  });

  group('canStep', () {
    test('follows the resolved value', () {
      const layers = SongReaderKeyLayers();

      expect(
        layers.canStep(_song(transpose: 11), SongKeyField.transpose, 1),
        isFalse,
      );
      expect(
        layers.canStep(_song(transpose: 11), SongKeyField.transpose, -1),
        isTrue,
      );
      expect(layers.canStep(_song(capo: 0), SongKeyField.capo, -1), isFalse);
      expect(layers.canStep(_song(capo: 0), SongKeyField.capo, 1), isTrue);
    });

    test('enables only the step toward the range from outside it', () {
      const layers = SongReaderKeyLayers();
      final song = _song(transpose: 14, capo: 13);

      expect(layers.canStep(song, SongKeyField.transpose, 1), isFalse);
      expect(layers.canStep(song, SongKeyField.transpose, -1), isTrue);
      expect(layers.canStep(song, SongKeyField.capo, 1), isFalse);
      expect(layers.canStep(song, SongKeyField.capo, -1), isTrue);
    });

    test('steps from the temporary value, not the song base', () {
      const layers = SongReaderKeyLayers(
        temporary: SongReaderTemporaryLayer(ownerId: 'x', transpose: 11),
      );

      expect(layers.canStep(_song(), SongKeyField.transpose, 1), isFalse);
      expect(layers.canStep(_song(), SongKeyField.transpose, -1), isTrue);
    });
  });

  group('temporaryAfterStep', () {
    test('starts a temporary layer owned by the given owner', () {
      final next = SongReaderKeyLayers.baseOnly.temporaryAfterStep(
        _song(),
        SongKeyField.transpose,
        1,
        ownerId: 'x',
      );

      expect(next, const SongReaderTemporaryLayer(ownerId: 'x', transpose: 1));
    });

    test('drops the layer when the step lands back on the layers below', () {
      const layers = SongReaderKeyLayers(
        temporary: SongReaderTemporaryLayer(ownerId: 'x', transpose: 1),
      );

      expect(
        layers.temporaryAfterStep(
          _song(),
          SongKeyField.transpose,
          -1,
          ownerId: 'x',
        ),
        isNull,
      );
    });

    test('keeps the other temporary field', () {
      const layers = SongReaderKeyLayers(
        temporary: SongReaderTemporaryLayer(ownerId: 'x', capo: 3),
      );

      expect(
        layers.temporaryAfterStep(
          _song(),
          SongKeyField.transpose,
          1,
          ownerId: 'x',
        ),
        const SongReaderTemporaryLayer(ownerId: 'x', transpose: 1, capo: 3),
      );
    });

    test('steps from the plan value inside a plan', () {
      const layers = SongReaderKeyLayers(isPlanScoped: true, planTranspose: 3);

      expect(
        layers.temporaryAfterStep(
          _song(),
          SongKeyField.transpose,
          1,
          ownerId: 'x',
        ),
        const SongReaderTemporaryLayer(ownerId: 'x', transpose: 4),
      );
      expect(
        layers.temporaryAfterStep(
          _song(),
          SongKeyField.transpose,
          -1,
          ownerId: 'x',
        ),
        const SongReaderTemporaryLayer(ownerId: 'x', transpose: 2),
      );
    });

    test('moves an out-of-range song base toward the range one step', () {
      final next = SongReaderKeyLayers.baseOnly.temporaryAfterStep(
        _song(transpose: 14),
        SongKeyField.transpose,
        -1,
        ownerId: 'x',
      );

      expect(next, const SongReaderTemporaryLayer(ownerId: 'x', transpose: 13));
    });

    test('refuses a step away from the range', () {
      expect(
        () => SongReaderKeyLayers.baseOnly.temporaryAfterStep(
          _song(transpose: 14),
          SongKeyField.transpose,
          1,
          ownerId: 'x',
        ),
        throwsStateError,
      );
    });
  });

  group('prunedTemporary', () {
    test('is null without a temporary layer', () {
      expect(
        const SongReaderKeyLayers(
          isPlanScoped: true,
          planTranspose: 3,
        ).prunedTemporary(_song()),
        isNull,
      );
    });

    test('drops a value that equals the plan value', () {
      const layers = SongReaderKeyLayers(
        temporary: SongReaderTemporaryLayer(ownerId: 'x', transpose: 3),
        isPlanScoped: true,
        planTranspose: 3,
      );

      expect(layers.prunedTemporary(_song()), isNull);
    });

    test('keeps only the fields the temporary layer still gives', () {
      const layers = SongReaderKeyLayers(
        temporary: SongReaderTemporaryLayer(
          ownerId: 'x',
          transpose: 3,
          capo: 1,
        ),
        isPlanScoped: true,
        planTranspose: 3,
      );

      expect(
        layers.prunedTemporary(_song()),
        const SongReaderTemporaryLayer(ownerId: 'x', capo: 1),
      );
    });

    test('leaves a differing value unchanged', () {
      const layers = SongReaderKeyLayers(
        temporary: SongReaderTemporaryLayer(ownerId: 'x', transpose: 4),
        isPlanScoped: true,
        planTranspose: 3,
      );

      expect(
        layers.prunedTemporary(_song()),
        const SongReaderTemporaryLayer(ownerId: 'x', transpose: 4),
      );
    });

    test('drops a value that equals the song base outside a plan', () {
      const layers = SongReaderKeyLayers(
        temporary: SongReaderTemporaryLayer(ownerId: 'x', capo: 2),
      );

      expect(layers.prunedTemporary(_song(capo: 2)), isNull);
    });
  });
}
