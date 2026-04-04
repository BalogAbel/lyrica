class SongSummary {
  const SongSummary({required this.id, required this.title, String? slug})
    : slug = slug ?? id;

  final String id;
  final String title;
  final String slug;

  @override
  bool operator ==(Object other) {
    return other is SongSummary &&
        other.id == id &&
        other.title == title &&
        other.slug == slug;
  }

  @override
  int get hashCode => Object.hash(id, title, slug);
}
