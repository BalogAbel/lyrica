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
///
/// Side-effect callbacks report completion by returning `bool`: `true` if
/// the action actually ran, `false` if a last-moment currentness guard
/// prevented it. A `false` report resolves as [ReauthSuperseded], so the
/// outcome never claims a wipe or cancellation that did not actually run.
///
/// The callback types are concrete `Future<bool> Function()` -- not
/// generic -- on purpose: a callback that cannot report whether it ran
/// (for example one that reverts to returning `void`) must fail to
/// compile here rather than silently being treated as "ran". Generic
/// result types previously allowed exactly that regression with no
/// compile error and no test.
Future<ReauthOutcome> resolveReauth({
  required String newUserId,
  required String? priorUserId,
  required String? priorEmail,
  required Future<int?> Function() priorPendingCount,
  required Future<bool> Function() flushSameUser,
  required Future<bool> Function() wipePriorAndProceed,
  required Future<ReauthPromptResult> Function({
    required String email,
    required int? pendingCount,
  })
  confirmDifferentUser,
  required Future<bool> Function() cancelToPriorUser,
  bool Function()? isCurrent,
}) async {
  bool current() => isCurrent?.call() ?? true;

  if (!current()) {
    return const ReauthSuperseded();
  }

  // Same user or no prior identity: proceed as same-user
  if (priorUserId == null || priorUserId == newUserId) {
    if (!await flushSameUser()) {
      return const ReauthSuperseded();
    }
    return const ReauthProceededSameUser();
  }

  // Different user: check pending count. null means "could not be
  // determined" and must NOT be treated as zero.
  final count = await priorPendingCount();
  if (!current()) return const ReauthSuperseded();

  if (count == 0) {
    // No pending data: safe to wipe without confirmation
    if (!await wipePriorAndProceed()) {
      return const ReauthSuperseded();
    }
    return const ReauthWipedPriorAndProceeded();
  }

  // Pending data exists, or its amount is unknown: require confirmation
  // before wipe either way -- uncertainty must never authorise a wipe.
  final promptResult = await confirmDifferentUser(
    email: priorEmail ?? '',
    pendingCount: count,
  );

  if (!current()) {
    return const ReauthSuperseded();
  }

  // M5 (PR #64 review): exhaustive over the *sealed* ReauthPromptResult
  // enum, not an if/else-if chain with a trailing catch-all -- the same
  // argument this file's own doc already makes for the concrete callback
  // types (top of file) and for switching on the outcome at the call site
  // (auth_providers.dart, Finding 3). A `ReauthPromptResult` value added
  // later fails this switch to compile instead of silently falling through
  // to a return that used to be reachable only by construction.
  return switch (promptResult) {
    ReauthPromptResult.superseded => const ReauthSuperseded(),
    ReauthPromptResult.confirmed =>
      await wipePriorAndProceed()
          ? const ReauthWipedPriorAndProceeded()
          : const ReauthSuperseded(),
    ReauthPromptResult.cancelled =>
      await cancelToPriorUser()
          ? const ReauthCancelledKeptPriorUser()
          : const ReauthSuperseded(),
  };
}
