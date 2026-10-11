/// RW3 (docs/specs/2026-10-11-reauth-wipe-recount.md): which users have a
/// ChordPro import run in a phase that writes pending work in the background
/// (`isImportRunning`, SO7 of
/// docs/specs/2026-10-07-sign-out-pending-work-guard.md).
///
/// The import controller is a presentation-layer notifier; this is the
/// application layer's view of its runs, so the different-user wipe can
/// refuse to start while one may be writing the PRIOR user's work. The guard
/// is per user: the new user's own import writes the new user's work and must
/// not decline the new user's sign-in. Keyed by the reporting controller
/// instance: each instance adds and removes only itself, and a disposed
/// instance removes itself, so "running" can never outlive the instance that
/// reported it.
class ImportRunTracker {
  /// Running instance -> the user whose catalog context it captured, or
  /// `null` when that is not known.
  final _running = <Object, String?>{};

  bool get isRunning => _running.isNotEmpty;

  /// Whether a run may be writing [userId]'s work. A run whose user is not
  /// known counts for every user (conservative).
  bool isRunningFor(String userId) =>
      _running.values.any((runUser) => runUser == null || runUser == userId);

  void report(Object owner, {required String? userId, required bool running}) {
    if (running) {
      _running[owner] = userId;
    } else {
      _running.remove(owner);
    }
  }
}
