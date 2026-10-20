import 'package:lyron_app/src/domain/song/parsed_song.dart';
import 'package:lyron_app/src/domain/song/song_key_layers.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';

/// The layers the reader resolves a song's key from (PS1): the temporary
/// layer, the plan layer when the reader was opened from a plan item, and the
/// song's own base. Everything the screen needs about the key (the resolved
/// values, which `±` steps are allowed, what a step writes) goes through this
/// one value, on top of the domain resolver.
class SongReaderKeyLayers {
  const SongReaderKeyLayers({
    this.temporary,
    this.isPlanScoped = false,
    this.planTranspose,
    this.planCapo,
  });

  /// No temporary and no plan layer: the song's own key.
  static const baseOnly = SongReaderKeyLayers();

  /// Already matched to the open reader by the caller
  /// (`SongReaderState.temporaryLayerFor`).
  final SongReaderTemporaryLayer? temporary;

  /// Whether the plan layer exists at all (the reader was opened from a plan
  /// item); its values may still be null.
  final bool isPlanScoped;
  final int? planTranspose;
  final int? planCapo;

  /// The layers for [song], highest precedence first. The temporary layer is
  /// always present, with null values when there is none, so a step can start
  /// one. The song layer floors a negative capo at 0 and shows an
  /// out-of-range base as it is (PS9).
  List<SongKeyLayer> layersFor(ParsedSong song) => [
    SongKeyLayer(
      id: SongKeyLayerId.temporary,
      transpose: temporary?.transpose,
      capo: temporary?.capo,
      isTransient: true,
    ),
    if (isPlanScoped)
      SongKeyLayer(
        id: SongKeyLayerId.plan,
        transpose: planTranspose,
        capo: planCapo,
      ),
    SongKeyLayer(
      id: SongKeyLayerId.song,
      transpose: song.baseTranspose,
      capo: song.baseCapo < SongKeyRange.minCapo
          ? SongKeyRange.minCapo
          : song.baseCapo,
    ),
  ];

  ResolvedSongKey resolveFor(ParsedSong song) =>
      resolveSongKey(layersFor(song));

  /// Whether `±` ([delta] is 1 or -1) may step [field] from its resolved
  /// value (PS9).
  bool canStep(ParsedSong song, SongKeyField field, int delta) =>
      canStepSongKey(field, resolveFor(song).field(field).value, delta);

  /// The temporary layer after a `±` step of [field]: the stepped value, or
  /// the field dropped when the step lands on what the layers below give
  /// (PS5). Null when nothing is left. Only valid for a step [canStep]
  /// allows.
  SongReaderTemporaryLayer? temporaryAfterStep(
    ParsedSong song,
    SongKeyField field,
    int delta, {
    required String ownerId,
  }) {
    final value = nextTransientValue(
      layersFor(song),
      transientLayer: SongKeyLayerId.temporary,
      field: field,
      delta: delta,
    );
    return (temporary ?? SongReaderTemporaryLayer(ownerId: ownerId)).withValue(
      field,
      value,
    );
  }

  /// The temporary layer without the fields that resolve to another layer
  /// (the PS5 elision made permanent, so a later change below cannot revive
  /// them), or null when nothing is left.
  SongReaderTemporaryLayer? prunedTemporary(ParsedSong song) {
    final resolved = resolveFor(song);
    var pruned = temporary;
    for (final field in SongKeyField.values) {
      if (resolved.field(field).source != SongKeyLayerId.temporary) {
        pruned = pruned?.withValue(field, null);
      }
    }
    return pruned;
  }
}
