import 'package:lyron_app/src/domain/song/song_key_layers.dart';

/// One field of a key edit (PS11, PS14).
enum SessionItemKeyFieldMode { keep, set, clear }

extension SessionItemKeyFieldModeX on SessionItemKeyFieldMode {
  String get value => switch (this) {
    SessionItemKeyFieldMode.keep => 'keep',
    SessionItemKeyFieldMode.set => 'set',
    SessionItemKeyFieldMode.clear => 'clear',
  };
}

SessionItemKeyFieldMode sessionItemKeyFieldModeFromValue(String value) =>
    switch (value) {
      'keep' => SessionItemKeyFieldMode.keep,
      'set' => SessionItemKeyFieldMode.set,
      'clear' => SessionItemKeyFieldMode.clear,
      _ => throw ArgumentError.value(value, 'value', 'Unknown key mode'),
    };

/// A plan-key edit of one session item: per field keep, set (with a value)
/// or clear (docs/specs/2026-10-13-personal-song-settings.md, PS11, PS14).
class SessionItemKeyEdit {
  SessionItemKeyEdit({
    required this.transposeMode,
    this.transpose,
    required this.capoMode,
    this.capo,
  }) {
    _checkField(
      'transpose',
      transposeMode,
      transpose,
      minTranspose,
      maxTranspose,
    );
    _checkField('capo', capoMode, capo, minCapo, maxCapo);
  }

  static const minTranspose = SongKeyRange.minTranspose;
  static const maxTranspose = SongKeyRange.maxTranspose;
  static const minCapo = SongKeyRange.minCapo;
  static const maxCapo = SongKeyRange.maxCapo;

  final SessionItemKeyFieldMode transposeMode;
  final int? transpose;
  final SessionItemKeyFieldMode capoMode;
  final int? capo;

  static void _checkField(
    String name,
    SessionItemKeyFieldMode mode,
    int? value,
    int min,
    int max,
  ) {
    final valid = mode == SessionItemKeyFieldMode.set
        ? value != null && value >= min && value <= max
        : value == null;
    if (!valid) {
      throw ArgumentError.value(value, name, 'invalid for mode ${mode.value}');
    }
  }

  /// PS14 fold: this (later) edit over [earlier]. A later set or clear
  /// replaces that field's intent; a later keep leaves the earlier one.
  SessionItemKeyEdit foldOnto(SessionItemKeyEdit earlier) => SessionItemKeyEdit(
    transposeMode: transposeMode == SessionItemKeyFieldMode.keep
        ? earlier.transposeMode
        : transposeMode,
    transpose: transposeMode == SessionItemKeyFieldMode.keep
        ? earlier.transpose
        : transpose,
    capoMode: capoMode == SessionItemKeyFieldMode.keep
        ? earlier.capoMode
        : capoMode,
    capo: capoMode == SessionItemKeyFieldMode.keep ? earlier.capo : capo,
  );

  /// The key this edit produces from [transpose]/[capo] (PS12 step 8, PS15).
  ({int? transpose, int? capo}) applyTo({int? transpose, int? capo}) => (
    transpose: switch (transposeMode) {
      SessionItemKeyFieldMode.keep => transpose,
      SessionItemKeyFieldMode.set => this.transpose,
      SessionItemKeyFieldMode.clear => null,
    },
    capo: switch (capoMode) {
      SessionItemKeyFieldMode.keep => capo,
      SessionItemKeyFieldMode.set => this.capo,
      SessionItemKeyFieldMode.clear => null,
    },
  );

  @override
  bool operator ==(Object other) =>
      other is SessionItemKeyEdit &&
      other.transposeMode == transposeMode &&
      other.transpose == transpose &&
      other.capoMode == capoMode &&
      other.capo == capo;

  @override
  int get hashCode => Object.hash(transposeMode, transpose, capoMode, capo);

  @override
  String toString() =>
      'SessionItemKeyEdit(transpose: ${transposeMode.value} $transpose, '
      'capo: ${capoMode.value} $capo)';
}
