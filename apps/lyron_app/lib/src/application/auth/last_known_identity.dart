class LastKnownIdentity {
  const LastKnownIdentity({
    required this.userId,
    required this.email,
    required this.organizationId,
    this.updatedAt,
  });

  final String userId;
  final String email;
  final String? organizationId;
  final DateTime? updatedAt;
}

abstract interface class LastKnownIdentityStore {
  Future<LastKnownIdentity?> read();

  Future<void> write(LastKnownIdentity identity);

  Future<void> clear();
}
