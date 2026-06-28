sealed class ReauthOutcome {
  const ReauthOutcome();
}

/// Same user re-authenticated; queue flushed without wiping.
class ReauthProceededSameUser extends ReauthOutcome {
  const ReauthProceededSameUser();
}

/// Different user proceeded; prior user's data wiped first.
class ReauthWipedPriorAndProceeded extends ReauthOutcome {
  const ReauthWipedPriorAndProceeded();
}

/// Different user sign-in was cancelled; prior user kept offline-authenticated.
class ReauthCancelledKeptPriorUser extends ReauthOutcome {
  const ReauthCancelledKeptPriorUser();
}

/// Pure, UI-agnostic coordinator for re-authentication resolution.
/// Mirrors the pure-function style of `resolveMembershipWithCachedFallback`.
///
/// Resolve re-authentication outcome based on user identity change and confirmation.
///
/// Logic:
/// - priorUserId == null || priorUserId == newUserId → await flushSameUser(); return ReauthProceededSameUser().
/// - different user:
///   - count = await priorPendingCount();
///   - if count == 0 → await wipePriorAndProceed(); return ReauthWipedPriorAndProceeded(). (nothing to lose, no prompt)
///   - if count > 0 → confirmed = await confirmDifferentUser(email: priorEmail ?? '', pendingCount: count);
///      - confirmed true → await wipePriorAndProceed(); return ReauthWipedPriorAndProceeded();
///      - confirmed false → await cancelToPriorUser(); return ReauthCancelledKeptPriorUser();
///
/// CRITICAL: wipePriorAndProceed MUST NOT be called before confirmDifferentUser
/// resolves true when count>0 (tests assert ordering — no wipe until confirm).
Future<ReauthOutcome> resolveReauth({
  required String newUserId,
  required String? priorUserId,
  required String? priorEmail,
  required Future<int> Function() priorPendingCount,
  required Future<void> Function() flushSameUser,
  required Future<void> Function() wipePriorAndProceed,
  required Future<bool> Function({
    required String email,
    required int pendingCount,
  })
  confirmDifferentUser,
  required Future<void> Function() cancelToPriorUser,
}) async {
  // Same user or no prior identity: proceed as same-user
  if (priorUserId == null || priorUserId == newUserId) {
    await flushSameUser();
    return const ReauthProceededSameUser();
  }

  // Different user: check pending count
  final count = await priorPendingCount();

  if (count == 0) {
    // No pending data: safe to wipe without confirmation
    await wipePriorAndProceed();
    return const ReauthWipedPriorAndProceeded();
  }

  // Pending data exists: require confirmation before wipe
  final confirmed = await confirmDifferentUser(
    email: priorEmail ?? '',
    pendingCount: count,
  );

  if (confirmed) {
    await wipePriorAndProceed();
    return const ReauthWipedPriorAndProceeded();
  } else {
    await cancelToPriorUser();
    return const ReauthCancelledKeptPriorUser();
  }
}
