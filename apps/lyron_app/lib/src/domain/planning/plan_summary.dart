class PlanSummary {
  const PlanSummary({
    required this.id,
    required this.name,
    required this.description,
    required this.scheduledFor,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String? description;
  final DateTime? scheduledFor;
  final DateTime updatedAt;

  @override
  bool operator ==(Object other) {
    return other is PlanSummary &&
        other.id == id &&
        other.name == name &&
        other.description == description &&
        other.scheduledFor == scheduledFor &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode =>
      Object.hash(id, name, description, scheduledFor, updatedAt);
}
