class PlanSummary {
  const PlanSummary({
    required this.id,
    required this.name,
    required this.description,
    required this.scheduledFor,
    required this.updatedAt,
    int? version,
    String? slug,
  }) : slug = slug ?? id,
       version = version ?? 1;

  final String id;
  final String slug;
  final String name;
  final String? description;
  final DateTime? scheduledFor;
  final DateTime updatedAt;
  final int version;

  @override
  bool operator ==(Object other) {
    return other is PlanSummary &&
        other.id == id &&
        other.slug == slug &&
        other.name == name &&
        other.description == description &&
        other.scheduledFor == scheduledFor &&
        other.updatedAt == updatedAt &&
        other.version == version;
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
  );
}
