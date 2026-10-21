import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/domain/song/song_key_layers.dart';

SongKeyLayer temp({int? t, int? c}) => SongKeyLayer(
  id: SongKeyLayerId.temporary,
  transpose: t,
  capo: c,
  isTransient: true,
);

SongKeyLayer plan({int? t, int? c}) =>
    SongKeyLayer(id: SongKeyLayerId.plan, transpose: t, capo: c);

SongKeyLayer song({int t = 0, int c = 0}) =>
    SongKeyLayer(id: SongKeyLayerId.song, transpose: t, capo: c);

ResolvedSongKeyField at(int value, SongKeyLayerId source) =>
    ResolvedSongKeyField(value: value, source: source);

void main() {
  group('SongKeyRange', () {
    test('holds the PS9 bounds per field', () {
      expect(SongKeyRange.minTranspose, -11);
      expect(SongKeyRange.maxTranspose, 11);
      expect(SongKeyRange.minCapo, 0);
      expect(SongKeyRange.maxCapo, 11);
      expect(SongKeyRange.min(SongKeyField.transpose), -11);
      expect(SongKeyRange.max(SongKeyField.transpose), 11);
      expect(SongKeyRange.min(SongKeyField.capo), 0);
      expect(SongKeyRange.max(SongKeyField.capo), 11);
      expect(SongKeyRange.contains(SongKeyField.transpose, -11), isTrue);
      expect(SongKeyRange.contains(SongKeyField.transpose, 11), isTrue);
      expect(SongKeyRange.contains(SongKeyField.transpose, 12), isFalse);
      expect(SongKeyRange.contains(SongKeyField.capo, -1), isFalse);
      expect(SongKeyRange.contains(SongKeyField.capo, 11), isTrue);
    });
  });

  group('resolveSongKey', () {
    test('resolves each field independently, first non-null wins', () {
      final mixed = resolveSongKey([temp(t: 3), plan(c: 2), song(t: 1, c: 0)]);
      expect(mixed.transpose, at(3, SongKeyLayerId.temporary));
      expect(mixed.capo, at(2, SongKeyLayerId.plan));

      final songOnly = resolveSongKey([temp(), plan(), song(t: 1, c: 4)]);
      expect(songOnly.transpose, at(1, SongKeyLayerId.song));
      expect(songOnly.capo, at(4, SongKeyLayerId.song));

      final noTemporary = resolveSongKey([plan(t: 2), song()]);
      expect(noTemporary.transpose, at(2, SongKeyLayerId.plan));
      expect(noTemporary.capo, at(0, SongKeyLayerId.song));

      final library = resolveSongKey([temp(t: 5), song()]);
      expect(library.transpose, at(5, SongKeyLayerId.temporary));
      expect(library.capo, at(0, SongKeyLayerId.song));
    });

    test('throws when the last layer does not give both fields', () {
      expect(() => resolveSongKey([]), throwsArgumentError);
      expect(() => resolveSongKey([plan(t: 1)]), throwsArgumentError);
    });

    test('a transient value equal to the layers below does not claim the '
        'field', () {
      final transpose = resolveSongKey([temp(t: 2), plan(t: 2), song()]);
      expect(transpose.transpose, at(2, SongKeyLayerId.plan));
      expect(transpose.hasSource(SongKeyLayerId.temporary), isFalse);

      final capo = resolveSongKey([temp(c: 0), plan(), song(c: 0)]);
      expect(capo.capo, at(0, SongKeyLayerId.song));
      expect(capo.hasSource(SongKeyLayerId.temporary), isFalse);
    });

    test('a stored layer equal to the song base keeps its source', () {
      final key = resolveSongKey([temp(), plan(t: 0), song(t: 0)]);
      expect(key.transpose, at(0, SongKeyLayerId.plan));
    });

    test('field and hasSource read the resolved fields', () {
      final key = resolveSongKey([temp(t: 3), plan(c: 2), song()]);
      expect(key.field(SongKeyField.transpose), key.transpose);
      expect(key.field(SongKeyField.capo), key.capo);
      expect(key.hasSource(SongKeyLayerId.temporary), isTrue);
      expect(key.hasSource(SongKeyLayerId.plan), isTrue);
      expect(key.hasSource(SongKeyLayerId.song), isFalse);
    });

    test('value equality', () {
      final a = resolveSongKey([temp(t: 3), song()]);
      final b = resolveSongKey([temp(t: 3), song()]);
      final c = resolveSongKey([temp(t: 4), song()]);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
      expect(at(1, SongKeyLayerId.plan), at(1, SongKeyLayerId.plan));
      expect(at(1, SongKeyLayerId.plan), isNot(at(1, SongKeyLayerId.song)));
    });
  });

  group('canStepSongKey', () {
    const table = <(SongKeyField, int, int, bool)>[
      (SongKeyField.transpose, 0, 1, true),
      (SongKeyField.transpose, 11, 1, false),
      (SongKeyField.transpose, -11, -1, false),
      (SongKeyField.transpose, 14, 1, false),
      (SongKeyField.transpose, 14, -1, true),
      (SongKeyField.transpose, -13, -1, false),
      (SongKeyField.transpose, -13, 1, true),
      (SongKeyField.capo, 0, -1, false),
      (SongKeyField.capo, 0, 1, true),
      (SongKeyField.capo, 11, 1, false),
      (SongKeyField.capo, 13, -1, true),
      (SongKeyField.capo, 13, 1, false),
    ];

    for (final (field, current, delta, expected) in table) {
      test('${field.name} $current by $delta is $expected', () {
        expect(canStepSongKey(field, current, delta), expected);
      });
    }

    test('refuses a delta other than 1 or -1', () {
      expect(
        () => canStepSongKey(SongKeyField.transpose, 0, 0),
        throwsArgumentError,
      );
      expect(
        () => canStepSongKey(SongKeyField.transpose, 0, 2),
        throwsArgumentError,
      );
      expect(
        () => canStepSongKey(SongKeyField.capo, 0, -2),
        throwsArgumentError,
      );
    });
  });

  group('nextTransientValue', () {
    int? next(List<SongKeyLayer> layers, SongKeyField field, int delta) =>
        nextTransientValue(
          layers,
          transientLayer: SongKeyLayerId.temporary,
          field: field,
          delta: delta,
        );

    test('steps from the value below when there is no transient value', () {
      expect(next([temp(), song(t: 0)], SongKeyField.transpose, 1), 1);
      expect(next([temp(), plan(t: 2), song()], SongKeyField.transpose, -1), 1);
    });

    test('returns null when the step lands on the value below', () {
      expect(
        next([temp(t: 1), song(t: 0)], SongKeyField.transpose, -1),
        isNull,
      );
      expect(
        next([temp(t: 3), plan(t: 2), song()], SongKeyField.transpose, -1),
        isNull,
      );
    });

    test('steps an out-of-range value one toward the range', () {
      expect(next([temp(), song(t: 14)], SongKeyField.transpose, -1), 13);
    });

    test('steps the capo field', () {
      expect(next([temp(), song(c: 2)], SongKeyField.capo, 1), 3);
      expect(next([temp(c: 3), song(c: 2)], SongKeyField.capo, -1), isNull);
    });

    test('throws a StateError for a step canStepSongKey refuses', () {
      expect(
        () => next([temp(), song(t: 11)], SongKeyField.transpose, 1),
        throwsStateError,
      );
      expect(
        () => next([temp(), song(c: 0)], SongKeyField.capo, -1),
        throwsStateError,
      );
    });

    test('throws an ArgumentError when the transient layer is missing', () {
      expect(
        () => next([plan(t: 1), song()], SongKeyField.transpose, 1),
        throwsArgumentError,
      );
    });
  });
}
