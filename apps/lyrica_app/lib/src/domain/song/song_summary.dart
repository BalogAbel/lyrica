class SongSummary {
  const SongSummary({
    required this.id,
    required this.title,
  });

  final String id;
  final String title;

  @override
  bool operator ==(Object other) {
    return other is SongSummary && other.id == id && other.title == title;
  }

  @override
  int get hashCode => Object.hash(id, title);
}
