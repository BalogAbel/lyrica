class PlanSummary {
  const PlanSummary({
    required this.id,
    required this.name,
    required this.description,
    required this.scheduledFor,
    required this.updatedAt,
    int? version,
    String? slug,
    this.contentVersion,
  }) : slug = slug ?? id,
       version = version ?? 1;

  final String id;
  final String slug;
  final String name;
  final String? description;
  final DateTime? scheduledFor;
  final DateTime updatedAt;
  final int version;

  /// The backend's `plans.content_version` as known to the local projection
  /// (spec D4). `null` means unknown, e.g. a row cached before schema 7 that
  /// no refresh has replaced yet.
  final int? contentVersion;

  @override
  bool operator ==(Object other) {
    return other is PlanSummary &&
        other.id == id &&
        other.slug == slug &&
        other.name == name &&
        other.description == description &&
        other.scheduledFor == scheduledFor &&
        other.updatedAt == updatedAt &&
        other.version == version &&
        other.contentVersion == contentVersion;
  }

  @override
  int get hashCode => Object.hash(
    id,
    slug,
    name,
    description,
    scheduledFor,
    updatedAt,
    version,
    contentVersion,
  );
}
