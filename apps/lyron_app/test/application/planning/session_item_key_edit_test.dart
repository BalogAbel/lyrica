import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/session_item_key_edit.dart';

void main() {
  group('SessionItemKeyFieldMode', () {
    test('round-trips through its stored value', () {
      for (final mode in SessionItemKeyFieldMode.values) {
        expect(sessionItemKeyFieldModeFromValue(mode.value), mode);
      }
      expect(SessionItemKeyFieldMode.keep.value, 'keep');
      expect(SessionItemKeyFieldMode.set.value, 'set');
      expect(SessionItemKeyFieldMode.clear.value, 'clear');
    });

    test('refuses an unknown value', () {
      expect(
        () => sessionItemKeyFieldModeFromValue('other'),
        throwsArgumentError,
      );
    });
  });

  group('SessionItemKeyEdit validation', () {
    test('accepts valid combinations', () {
      expect(
        () => SessionItemKeyEdit(
          transposeMode: SessionItemKeyFieldMode.set,
          transpose: -11,
          capoMode: SessionItemKeyFieldMode.set,
          capo: 11,
        ),
        returnsNormally,
      );
      expect(
        () => SessionItemKeyEdit(
          transposeMode: SessionItemKeyFieldMode.set,
          transpose: 11,
          capoMode: SessionItemKeyFieldMode.set,
          capo: 0,
        ),
        returnsNormally,
      );
    });

    test('set without a value throws', () {
      expect(
        () => SessionItemKeyEdit(
          transposeMode: SessionItemKeyFieldMode.set,
          capoMode: SessionItemKeyFieldMode.keep,
        ),
        throwsArgumentError,
      );
      expect(
        () => SessionItemKeyEdit(
          transposeMode: SessionItemKeyFieldMode.keep,
          capoMode: SessionItemKeyFieldMode.set,
        ),
        throwsArgumentError,
      );
    });

    test('keep and clear with a value throw', () {
      for (final mode in [
        SessionItemKeyFieldMode.keep,
        SessionItemKeyFieldMode.clear,
      ]) {
        expect(
          () => SessionItemKeyEdit(
            transposeMode: mode,
            transpose: 1,
            capoMode: SessionItemKeyFieldMode.keep,
          ),
          throwsArgumentError,
        );
        expect(
          () => SessionItemKeyEdit(
            transposeMode: SessionItemKeyFieldMode.keep,
            capoMode: mode,
            capo: 1,
          ),
          throwsArgumentError,
        );
      }
    });

    test('out-of-bounds values throw', () {
      for (final transpose in [-12, 12]) {
        expect(
          () => SessionItemKeyEdit(
            transposeMode: SessionItemKeyFieldMode.set,
            transpose: transpose,
            capoMode: SessionItemKeyFieldMode.keep,
          ),
          throwsArgumentError,
        );
      }
      for (final capo in [-1, 12]) {
        expect(
          () => SessionItemKeyEdit(
            transposeMode: SessionItemKeyFieldMode.keep,
            capoMode: SessionItemKeyFieldMode.set,
            capo: capo,
          ),
          throwsArgumentError,
        );
      }
    });
  });

  group('SessionItemKeyEdit.foldOnto (PS14)', () {
    SessionItemKeyEdit edit(
      SessionItemKeyFieldMode tm,
      int? t,
      SessionItemKeyFieldMode cm,
      int? c,
    ) => SessionItemKeyEdit(
      transposeMode: tm,
      transpose: t,
      capoMode: cm,
      capo: c,
    );
    const keep = SessionItemKeyFieldMode.keep;
    const set = SessionItemKeyFieldMode.set;
    const clear = SessionItemKeyFieldMode.clear;

    test('set over set replaces the value', () {
      final folded = edit(
        set,
        5,
        keep,
        null,
      ).foldOnto(edit(set, 3, keep, null));
      expect(folded, edit(set, 5, keep, null));
    });

    test('keep over set leaves the earlier intent', () {
      final folded = edit(
        keep,
        null,
        set,
        2,
      ).foldOnto(edit(set, 3, keep, null));
      expect(folded, edit(set, 3, set, 2));
    });

    test('clear over set replaces with clear', () {
      final folded = edit(
        clear,
        null,
        keep,
        null,
      ).foldOnto(edit(set, 3, set, 2));
      expect(folded, edit(clear, null, set, 2));
    });

    test('set over clear replaces with set', () {
      final folded = edit(
        set,
        4,
        keep,
        null,
      ).foldOnto(edit(clear, null, clear, null));
      expect(folded, edit(set, 4, clear, null));
    });
  });

  group('SessionItemKeyEdit.applyTo', () {
    test('every mode on both fields', () {
      const keep = SessionItemKeyFieldMode.keep;
      const set = SessionItemKeyFieldMode.set;
      const clear = SessionItemKeyFieldMode.clear;

      expect(
        SessionItemKeyEdit(
          transposeMode: keep,
          capoMode: keep,
        ).applyTo(transpose: 2, capo: 3),
        (transpose: 2, capo: 3),
      );
      expect(
        SessionItemKeyEdit(
          transposeMode: set,
          transpose: 7,
          capoMode: set,
          capo: 4,
        ).applyTo(transpose: 2, capo: 3),
        (transpose: 7, capo: 4),
      );
      expect(
        SessionItemKeyEdit(
          transposeMode: clear,
          capoMode: clear,
        ).applyTo(transpose: 2, capo: 3),
        (transpose: null, capo: null),
      );
      expect(
        SessionItemKeyEdit(
          transposeMode: keep,
          capoMode: clear,
        ).applyTo(transpose: null, capo: 3),
        (transpose: null, capo: null),
      );
    });
  });
}
