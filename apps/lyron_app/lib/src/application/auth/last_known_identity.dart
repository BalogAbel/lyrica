class LastKnownIdentity {
  const LastKnownIdentity({
    required this.userId,
    required this.email,
    required this.organizationId,
    this.updatedAt,
    this.membershipRevokedAt,
  });

  final String userId;
  final String email;
  final String? organizationId;
  final DateTime? updatedAt;

  /// D5 (docs/specs/2026-08-19-local-data-durability-contract.md): set on
  /// the first verified-empty-membership resolution for this user, before
  /// any purge. Non-null means the local data is in read-only quarantine.
  final DateTime? membershipRevokedAt;
}

abstract interface class LastKnownIdentityStore {
  Future<LastKnownIdentity?> read();

  Future<void> write(LastKnownIdentity identity);

  Future<void> clear();
}
