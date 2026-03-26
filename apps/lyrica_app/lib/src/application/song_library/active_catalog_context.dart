class ActiveCatalogContext {
  const ActiveCatalogContext({
    required this.userId,
    required this.organizationId,
  });

  final String userId;
  final String organizationId;

  @override
  bool operator ==(Object other) {
    return other is ActiveCatalogContext &&
        other.userId == userId &&
        other.organizationId == organizationId;
  }

  @override
  int get hashCode => Object.hash(userId, organizationId);
}
