import 'package:lyron_app/src/application/auth/reauth_prompt_controller.dart';

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

/// A newer auth edge made this resolution obsolete before it acted.
class ReauthSuperseded extends ReauthOutcome {
  const ReauthSuperseded();
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
///   - if count > 0 OR count == null (unknown) → confirmed = await confirmDifferentUser(email: priorEmail ?? '', pendingCount: count);
///      - confirmed true → await wipePriorAndProceed(); return ReauthWipedPriorAndProceeded();
///      - confirmed false → await cancelToPriorUser(); return ReauthCancelledKeptPriorUser();
///
/// CRITICAL: wipePriorAndProceed MUST NOT be called before confirmDifferentUser
/// resolves true when count is nonzero or unknown (tests assert ordering —
/// no wipe until confirm). Unknown is deliberately NOT treated as zero: only
/// a count that was actually read as zero skips the prompt.
Future<ReauthOutcome> resolveReauth({
  required String newUserId,
  required String? priorUserId,
  required String? priorEmail,
  required Future<int?> Function() priorPendingCount,
  required Future<void> Function() flushSameUser,
  required Future<void> Function() wipePriorAndProceed,
  required Future<ReauthPromptResult> Function({
    required String email,
    required int? pendingCount,
  })
  confirmDifferentUser,
  required Future<void> Function() cancelToPriorUser,
}) async {
  // Same user or no prior identity: proceed as same-user
  if (priorUserId == null || priorUserId == newUserId) {
    await flushSameUser();
    return const ReauthProceededSameUser();
  }

  // Different user: check pending count. null means "could not be
  // determined" and must NOT be treated as zero.
  final count = await priorPendingCount();

  if (count == 0) {
    // No pending data: safe to wipe without confirmation
    await wipePriorAndProceed();
    return const ReauthWipedPriorAndProceeded();
  }

  // Pending data exists, or its amount is unknown: require confirmation
  // before wipe either way -- uncertainty must never authorise a wipe.
  final promptResult = await confirmDifferentUser(
    email: priorEmail ?? '',
    pendingCount: count,
  );

  if (promptResult == ReauthPromptResult.confirmed) {
    await wipePriorAndProceed();
    return const ReauthWipedPriorAndProceeded();
  } else if (promptResult == ReauthPromptResult.cancelled) {
    await cancelToPriorUser();
    return const ReauthCancelledKeptPriorUser();
  }

  // Typed seam only. Task 4 implements the superseded outcome behavior.
  return const ReauthCancelledKeptPriorUser();
}
