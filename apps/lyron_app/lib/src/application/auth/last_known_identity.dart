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

/// The outcome of one atomic [LastKnownIdentityStore.resolveEmptyMembership]
/// call (D5.1: read-and-decide in a single store operation, never a read in
/// application code followed by a later write).
sealed class EmptyMembershipResolutionOutcome {
  const EmptyMembershipResolutionOutcome();
}

/// The stored identity row does not exist, or belongs to a different
/// `userId` than the one this resolution is for. Nothing was written -- a
/// caller must never create or overwrite an identity row for a user that
/// does not own the stored one (closeout finding 5).
final class EmptyMembershipResolutionIgnored
    extends EmptyMembershipResolutionOutcome {
  const EmptyMembershipResolutionIgnored();
}

/// The row is owned by the calling `userId` and had no marker set. The
/// marker was recorded at [markedAt].
final class EmptyMembershipResolutionMarkerRecorded
    extends EmptyMembershipResolutionOutcome {
  const EmptyMembershipResolutionMarkerRecorded({required this.markedAt});

  final DateTime markedAt;
}

/// The row is owned by the calling `userId` and already had a marker set at
/// [markedAt]. The marker is left exactly as found -- not cleared, not
/// moved -- so the caller (LocalDataLifecycle) can apply the monotonic
/// cooldown check and use [markedAt] as the re-validation token for a later
/// purge decision.
final class EmptyMembershipResolutionSecondConfirmationAvailable
    extends EmptyMembershipResolutionOutcome {
  const EmptyMembershipResolutionSecondConfirmationAvailable({
    required this.markedAt,
  });

  final DateTime markedAt;
}

abstract interface class LastKnownIdentityStore {
  Future<LastKnownIdentity?> read();

  Future<void> write(LastKnownIdentity identity);

  Future<void> clear();

  /// D5.1: one atomic store operation that reads the current row, verifies
  /// ownership, and either records the membership-revocation marker or
  /// reports that an unresolved marker already exists. Never sets a marker
  /// on a row that does not belong to [userId], and never creates a row.
  Future<EmptyMembershipResolutionOutcome> resolveEmptyMembership({
    required String userId,
  });

  /// D5.2: clears the membership-revocation marker for the row owned by
  /// [userId], ownership-checked in a single update. Returns `true` only if
  /// a marker was actually cleared, so an ordinary sign-in that finds no
  /// marker writes no spurious audit row.
  Future<bool> clearMembershipRevocation({required String userId});
}
