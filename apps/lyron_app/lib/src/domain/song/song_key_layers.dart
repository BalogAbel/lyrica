/// The two key fields a song's layers resolve (PS1).
enum SongKeyField { transpose, capo }

/// The layers a key field can come from, top to bottom in precedence order
/// (PS1). A future layer is a new value here plus its label in
/// `song_key_source_style.dart` (PS22).
enum SongKeyLayerId { temporary, plan, song }

/// The PS9 value bounds of a plan or temporary key. The song base may lie
/// outside them; the step rules only ever move toward the range.
abstract final class SongKeyRange {
  static const minTranspose = -11;
  static const maxTranspose = 11;
  static const minCapo = 0;
  static const maxCapo = 11;

  static int min(SongKeyField field) => switch (field) {
    SongKeyField.transpose => minTranspose,
    SongKeyField.capo => minCapo,
  };

  static int max(SongKeyField field) => switch (field) {
    SongKeyField.transpose => maxTranspose,
    SongKeyField.capo => maxCapo,
  };

  static bool contains(SongKeyField field, int value) =>
      value >= min(field) && value <= max(field);
}

/// One layer of the key chain (PS1): nullable absolute values per field. A
/// [isTransient] layer claims a field only while its value differs from what
/// the layers below give (the PS5 rule).
class SongKeyLayer {
  const SongKeyLayer({
    required this.id,
    this.transpose,
    this.capo,
    this.isTransient = false,
  });

  final SongKeyLayerId id;
  final int? transpose;
  final int? capo;
  final bool isTransient;

  int? valueOf(SongKeyField field) => switch (field) {
    SongKeyField.transpose => transpose,
    SongKeyField.capo => capo,
  };
}

/// A resolved field: its value and the layer that gave it (PS1).
class ResolvedSongKeyField {
  const ResolvedSongKeyField({required this.value, required this.source});

  final int value;
  final SongKeyLayerId source;

  @override
  bool operator ==(Object other) =>
      other is ResolvedSongKeyField &&
      other.value == value &&
      other.source == source;

  @override
  int get hashCode => Object.hash(value, source);
}

/// The key the layers resolve to, with the source of each field (PS1).
class ResolvedSongKey {
  const ResolvedSongKey({required this.transpose, required this.capo});

  final ResolvedSongKeyField transpose;
  final ResolvedSongKeyField capo;

  ResolvedSongKeyField field(SongKeyField field) => switch (field) {
    SongKeyField.transpose => transpose,
    SongKeyField.capo => capo,
  };

  /// Whether [id] gave at least one field. A transient layer that does not
  /// claim a field (the PS5 rule) is not a source.
  bool hasSource(SongKeyLayerId id) =>
      transpose.source == id || capo.source == id;

  @override
  bool operator ==(Object other) =>
      other is ResolvedSongKey &&
      other.transpose == transpose &&
      other.capo == capo;

  @override
  int get hashCode => Object.hash(transpose, capo);
}

/// Resolves [layers], ordered from the highest precedence to the lowest, per
/// field: the first layer with a value wins (PS1). A transient layer wins
/// only while its value differs from what the layers below give (PS5). The
/// last layer must give both fields. The reader, the projection and the plan
/// detail all go through this one function (PS22).
ResolvedSongKey resolveSongKey(List<SongKeyLayer> layers) => ResolvedSongKey(
  transpose: _resolveField(layers, SongKeyField.transpose),
  capo: _resolveField(layers, SongKeyField.capo),
);

/// Walks [layers] bottom-up, so each layer is compared once with the value
/// the layers below it already resolved to.
ResolvedSongKeyField _resolveField(
  List<SongKeyLayer> layers,
  SongKeyField field,
) {
  if (layers.isEmpty) {
    throw ArgumentError.value(layers, 'layers', 'must not be empty');
  }
  final base = layers.last;
  final baseValue = base.valueOf(field);
  if (baseValue == null) {
    throw ArgumentError.value(
      layers,
      'layers',
      'the last layer (${base.id.name}) must give ${field.name}',
    );
  }
  var resolved = ResolvedSongKeyField(value: baseValue, source: base.id);
  for (var i = layers.length - 2; i >= 0; i--) {
    final layer = layers[i];
    final value = layer.valueOf(field);
    if (value == null) continue;
    if (layer.isTransient && value == resolved.value) continue;
    resolved = ResolvedSongKeyField(value: value, source: layer.id);
  }
  return resolved;
}

/// Whether `±` ([delta] is 1 or -1) may step [field] from [current] (PS9). A
/// step never moves away from the range and never jumps: from outside the
/// range only the step toward it is allowed, and a range edge blocks the step
/// outward.
bool canStepSongKey(SongKeyField field, int current, int delta) {
  if (delta != 1 && delta != -1) {
    throw ArgumentError.value(delta, 'delta', 'must be 1 or -1');
  }
  return delta == 1
      ? current < SongKeyRange.max(field)
      : current > SongKeyRange.min(field);
}

/// The value the [transientLayer] should hold for [field] after a `±` step of
/// [delta], or null when the step lands on the value the layers below give
/// and the transient value drops (PS5). Throws a [StateError] for a step
/// [canStepSongKey] refuses, and an [ArgumentError] when [layers] has no
/// [transientLayer].
int? nextTransientValue(
  List<SongKeyLayer> layers, {
  required SongKeyLayerId transientLayer,
  required SongKeyField field,
  required int delta,
}) {
  final index = layers.indexWhere((layer) => layer.id == transientLayer);
  if (index < 0) {
    throw ArgumentError.value(
      transientLayer,
      'transientLayer',
      'not in the layer list',
    );
  }
  final current = resolveSongKey(layers).field(field).value;
  if (!canStepSongKey(field, current, delta)) {
    throw StateError('Cannot step ${field.name} from $current by $delta');
  }
  final target = current + delta;
  final below = resolveSongKey(layers.sublist(index + 1)).field(field).value;
  return target == below ? null : target;
}
