class SongSummary {
  const SongSummary({
    required this.id,
    required this.title,
    String? slug,
    int? version,
  }) : slug = slug ?? id,
       version = version ?? 1;

  final String id;
  final String title;
  final String slug;
  final int version;

  @override
  bool operator ==(Object other) {
    return other is SongSummary &&
        other.id == id &&
        other.title == title &&
        other.slug == slug &&
        other.version == version;
  }

  @override
  int get hashCode => Object.hash(id, title, slug, version);
}
