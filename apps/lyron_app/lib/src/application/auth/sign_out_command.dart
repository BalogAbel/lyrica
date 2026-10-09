enum SignOutOutcome { signedOut, cancelled, superseded, alreadyRunning, failed }

/// Shows the warning for [pendingCount] (null: unknown) and returns whether
/// the user confirmed the loss. Must answer false when it cannot ask.
typedef SignOutConfirmation = Future<bool> Function(int? pendingCount);

typedef SignOutPendingWorkCounter =
    Future<int> Function({required String userId});

typedef SignOutErrorReporter =
    void Function(Object error, StackTrace stackTrace);

/// SO1–SO3 (docs/specs/2026-10-07-sign-out-pending-work-guard.md): the one
/// explicit sign-out rule every sign-out control runs through.
///
/// The warning is decided from the signing-out user's user-wide pending
/// count, the same count and scope as the different-user wipe (ADR-029 D4),
/// which is also the scope of the sign-out purges. An unreadable count, or
/// no current user, is asked about with `null` and never treated as zero
/// (ADR-029 honest null, ADR-035 D5.4). A confirmed sign-out still deletes
/// (the 2026-08-19 product decision). An error while asking or from the
/// sign-out sequence never escapes [run]: it is reported once through the
/// injected reporter. (The user reader is a plain state getter.)
///
/// Holds no `Ref`: the provider in auth_providers.dart injects the reader,
/// the counter, the sign-out sequence and the reporter.
class SignOutCommand {
  SignOutCommand({
    required this._currentUserIdReader,
    required this._countPendingWork,
    required this._signOut,
    required this._reportError,
  });

  final String? Function() _currentUserIdReader;
  final SignOutPendingWorkCounter _countPendingWork;
  final Future<void> Function() _signOut;
  final SignOutErrorReporter _reportError;
  bool _running = false;

  Future<SignOutOutcome> run({
    required SignOutConfirmation confirmDiscard,
  }) async {
    if (_running) {
      return SignOutOutcome.alreadyRunning;
    }
    _running = true;
    try {
      final userId = _currentUserIdReader();
      final pendingCount = userId == null ? null : await _readCount(userId);
      // SO3: the purges target the current user when they run. If that is no
      // longer the user whose work was counted, nothing was confirmed for
      // the new one.
      if (_currentUserIdReader() != userId) {
        return SignOutOutcome.superseded;
      }
      if (pendingCount != 0) {
        if (!await _confirm(confirmDiscard, pendingCount)) {
          return SignOutOutcome.cancelled;
        }
        if (_currentUserIdReader() != userId) {
          return SignOutOutcome.superseded;
        }
      }
      try {
        await _signOut();
      } catch (error, stackTrace) {
        // SO3: no sign-out control may raise an unhandled error. The user
        // can try again: the lock is released below.
        _reportError(error, stackTrace);
        return SignOutOutcome.failed;
      }
      return SignOutOutcome.signedOut;
    } finally {
      _running = false;
    }
  }

  Future<int?> _readCount(String userId) async {
    try {
      return await _countPendingWork(userId: userId);
    } catch (_) {
      return null;
    }
  }

  /// An error while asking is reported and is not a confirmation.
  Future<bool> _confirm(
    SignOutConfirmation confirmDiscard,
    int? pendingCount,
  ) async {
    try {
      return await confirmDiscard(pendingCount);
    } catch (error, stackTrace) {
      _reportError(error, stackTrace);
      return false;
    }
  }
}
