import 'package:lyron_app/src/domain/song/song_summary.dart';

class SessionItemSummary {
  const SessionItemSummary({
    required this.id,
    required this.position,
    required this.song,
    String? slug,
  }) : slug = slug ?? id;

  final String id;
  final String slug;
  final int position;
  final SongSummary song;

  @override
  bool operator ==(Object other) {
    return other is SessionItemSummary &&
        other.id == id &&
        other.slug == slug &&
        other.position == position &&
        other.song == song;
  }

  @override
  int get hashCode => Object.hash(id, slug, position, song);
}
