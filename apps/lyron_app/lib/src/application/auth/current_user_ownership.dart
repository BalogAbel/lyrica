/// XU2 (docs/specs/2026-10-06-cross-user-local-first-ownership.md): the one
/// ownership rule every in-memory local-first context holder applies (the
/// song catalog context, the active planning context and the planning sync
/// state). A held or newly adopted context may belong only to the user the
/// app is acting for, `AppAuthState.currentUserId`.
///
/// Holders feed it that user on every signedIn and sessionExpired
/// notification. Explicit sign-out is not fed here: the sign-out handlers
/// reset the holders and choose the purge target themselves (ADR-035,
/// unchanged).
final class CurrentUserOwnership {
  String? _userId;

  /// The most recently observed current user; null until the first
  /// observation.
  String? get userId => _userId;

  /// Records [userId] as the current user. Returns true only when it
  /// replaces a different, previously observed user: work the holder
  /// started for that user must stop, and what it holds for them must go.
  ///
  /// The first observation returns false. The holder is new and has started
  /// nothing for an earlier user; reporting a change there would invalidate
  /// work it started for this same user while its provider was being built.
  bool observe(String userId) {
    final previous = _userId;
    _userId = userId;
    return previous != null && previous != userId;
  }

  /// Whether a context owned by [ownerUserId] may be held or adopted. Before
  /// the first observation nothing is known, and the holder's existing
  /// guards apply.
  bool allows(String ownerUserId) => _userId == null || _userId == ownerUserId;
}
