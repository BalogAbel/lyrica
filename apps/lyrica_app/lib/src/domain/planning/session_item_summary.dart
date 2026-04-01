import 'package:lyrica_app/src/domain/song/song_summary.dart';

class SessionItemSummary {
  const SessionItemSummary({
    required this.id,
    required this.position,
    required this.song,
  });

  final String id;
  final int position;
  final SongSummary song;

  @override
  bool operator ==(Object other) {
    return other is SessionItemSummary &&
        other.id == id &&
        other.position == position &&
        other.song == song;
  }

  @override
  int get hashCode => Object.hash(id, position, song);
}
