import 'package:lyron_app/src/domain/song/song_summary.dart';

class SessionItemSummary {
  const SessionItemSummary({
    required this.id,
    required this.position,
    required this.song,
    this.version = 1,
    this.planTranspose,
    this.planCapo,
    String? slug,
  }) : slug = slug ?? id;

  final String id;
  final String slug;
  final int position;
  final SongSummary song;

  /// The item's own OCC version (S3 PR 2); 1 until a key edit bumps it.
  final int version;

  /// The plan-level key layer for this item (null = no plan key).
  final int? planTranspose;
  final int? planCapo;

  @override
  bool operator ==(Object other) {
    return other is SessionItemSummary &&
        other.id == id &&
        other.slug == slug &&
        other.position == position &&
        other.song == song &&
        other.version == version &&
        other.planTranspose == planTranspose &&
        other.planCapo == planCapo;
  }

  @override
  int get hashCode =>
      Object.hash(id, slug, position, song, version, planTranspose, planCapo);
}
