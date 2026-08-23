import 'dart:async';

import 'package:flutter/foundation.dart';

/// A pending confirmation prompt owned by [ReauthPromptController]. `null`
/// on [pendingCount] means the count could not be determined -- an honest
/// "unknown", not a guess (see D4 in
/// `docs/specs/2026-07-30-recovery-actions-that-outlive-their-widget.md`).
///
/// Sealed with two variants (D5/Phase 4, ADR-035 Gap 3): the pre-existing
/// different-user reauth prompt ([ReauthDifferentUserPrompt]), and the new
/// membership-quarantine confirmed-purge prompt
/// ([MembershipQuarantinePurgePrompt]). Both are surfaced through this same
/// controller/host pair rather than a second one -- see the class doc below
/// and `ReauthPromptHost` (`presentation/auth/reauth_prompt_host.dart`),
/// which switches on the variant to show the right dialog. The two are
/// mutually exclusive by construction (a quarantine-purge prompt requires
/// the SAME user's membership resolving empty twice; a different-user
/// prompt requires a DIFFERENT user signing in, which clears any pending
/// quarantine marker as part of its own wipe-or-confirm path first), but the
/// "at most one prompt pending" guard below still applies uniformly across
/// both variants.
sealed class ReauthPrompt {
  const ReauthPrompt({required this.requestId, required this.pendingCount});

  final int requestId;
  final int? pendingCount;
}

/// The pre-existing different-user reauth prompt: the prior user's email
/// and how much local work a wipe would destroy.
class ReauthDifferentUserPrompt extends ReauthPrompt {
  const ReauthDifferentUserPrompt({
    required super.requestId,
    required super.pendingCount,
    required this.email,
  });

  final String email;
}

/// D5/Phase 4 (ADR-035 Gap 3): the second, independent verified-empty
/// membership resolution for [userId] found nonzero or unreadable pending
/// local work, and needs the user's confirmation before
/// `LocalDataLifecycle.resolveVerifiedEmptyMembership` proceeds to purge.
class MembershipQuarantinePurgePrompt extends ReauthPrompt {
  const MembershipQuarantinePurgePrompt({
    required super.requestId,
    required super.pendingCount,
    required this.userId,
  });

  final String userId;
}

enum ReauthPromptResult { confirmed, cancelled, superseded }

/// Publishes a pending reauth confirmation and awaits its answer.
///
/// Lives app-scoped (see `reauthPromptControllerProvider` in
/// `auth_providers.dart`) and NOT autoDispose: a pending prompt must survive
/// whatever screen happens to be on top when the different-user sign-in is
/// detected, not get torn down along with it.
///
/// Only one prompt may be pending at a time, across BOTH prompt variants
/// (different-user reauth and membership-quarantine purge) -- they are
/// mutually exclusive by construction (see the class doc on [ReauthPrompt]),
/// but the guard below applies uniformly regardless. Two different, single-
/// producer-per-variant mechanisms are what keep the `StateError` below from
/// ever firing in practice, not a shared one:
///
///  * `requestConfirmation` (different-user reauth): `resolveReauth` awaits
///    a single `confirmDifferentUser` call per `signedIn` transition before
///    doing anything else, so a second concurrent request would mean two
///    different-user resolutions racing.
///    `lastKnownIdentityPersistenceProvider` (`auth_providers.dart`)
///    enforces this structurally, not just by assertion: it serializes
///    every signedIn-edge resolution through a single future chain, so a
///    second resolution's `confirmDifferentUser` call can only ever start
///    after the first has fully finished, including the wait for its own
///    dialog answer.
///  * `requestMembershipQuarantinePurgeConfirmation` (membership-quarantine
///    purge): up to three independent listeners can call
///    `LocalDataLifecycle.resolveVerifiedEmptyMembership` for the same
///    `userId` off the same `signedIn` transition (`auth_providers.dart`'s
///    `persistIdentity`, and `VerifiedEmptyMembershipCleanupCoordinator`
///    reached separately from `SongCatalogController` and
///    `ActivePlanningContextController`) -- there is no single serialized
///    producer here. What prevents a second concurrent request instead is
///    `LocalDataLifecycle`'s own in-flight coalescing, keyed per `userId`
///    (`_inFlightResolutions` in `local_data_lifecycle.dart`): concurrent
///    callers for the same `userId` are handed the SAME `Future` rather
///    than each performing its own read-decide-act pass, so only one
///    execution per `userId` ever reaches this controller at a time.
///
/// The `StateError` below is therefore a defence-in-depth invariant for
/// each variant's own upstream guarantee, not a path either mechanism's
/// caller can currently reach -- rejecting the second request turns a
/// would-be race into a loud bug instead of silently queueing or dropping a
/// confirmation that guards data deletion.
class ReauthPromptController extends ChangeNotifier {
  int _nextRequestId = 0;
  ReauthPrompt? _pending;
  Completer<ReauthPromptResult>? _completer;

  ReauthPrompt? get pending => _pending;

  /// Publishes [email]/[pendingCount] as the pending prompt and returns a
  /// future that completes with the answer once [answer] is called.
  /// [pendingCount] of `null` means the count could not be determined.
  Future<ReauthPromptResult> requestConfirmation({
    required String email,
    required int? pendingCount,
  }) {
    return _request(
      (requestId) => ReauthDifferentUserPrompt(
        requestId: requestId,
        email: email,
        pendingCount: pendingCount,
      ),
    );
  }

  /// D5/Phase 4 (ADR-035 Gap 3): publishes [userId]/[pendingCount] as the
  /// pending membership-quarantine confirmed-purge prompt and returns a
  /// future that completes with the answer once [answer] is called.
  /// [pendingCount] of `null` means the count could not be determined --
  /// the caller must still ask, never treat it as zero (D5).
  Future<ReauthPromptResult> requestMembershipQuarantinePurgeConfirmation({
    required String userId,
    required int? pendingCount,
  }) {
    return _request(
      (requestId) => MembershipQuarantinePurgePrompt(
        requestId: requestId,
        userId: userId,
        pendingCount: pendingCount,
      ),
    );
  }

  /// Shared "at most one prompt pending" machinery (D2/D3 of ADR-029) behind
  /// both [requestConfirmation] and
  /// [requestMembershipQuarantinePurgeConfirmation] -- see the class doc on
  /// [ReauthPrompt] for why the two variants share this guard uniformly.
  Future<ReauthPromptResult> _request(
    ReauthPrompt Function(int requestId) buildPrompt,
  ) {
    if (_pending != null) {
      throw StateError(
        'A reauth prompt is already pending; cannot request a second one '
        'before the first is answered.',
      );
    }
    final completer = Completer<ReauthPromptResult>();
    _completer = completer;
    _pending = buildPrompt(_nextRequestId++);
    notifyListeners();
    return completer.future;
  }

  /// Feeds the dialog's answer back to whoever is awaiting
  /// [requestConfirmation]. A barrier dismissal must reach here as `false`,
  /// exactly like `showReauthDifferentUserDialog` returns -- never translate
  /// a missing answer into a confirm.
  void answer(bool confirmed, {int? requestId}) {
    final pending = _pending;
    final completer = _completer;
    if (pending == null || completer == null) return;
    if (requestId != null && requestId != pending.requestId) return;
    _pending = null;
    _completer = null;
    notifyListeners();
    completer.complete(
      confirmed ? ReauthPromptResult.confirmed : ReauthPromptResult.cancelled,
    );
  }

  /// Invalidates any request belonging to an obsolete auth transition.
  void supersedePending() {
    final completer = _completer;
    if (_pending == null || completer == null) return;
    _pending = null;
    _completer = null;
    notifyListeners();
    completer.complete(ReauthPromptResult.superseded);
  }

  /// N5 (PR #64 review): completes a pending completer as superseded before
  /// disposing, the same outcome [supersedePending] already reports for
  /// every other kind of obsolescence. This controller is app-scoped (see
  /// the class doc) and effectively never disposed in production, so the
  /// hazard this closes -- an awaiting `requestConfirmation` caller hanging
  /// forever if dispose ran with a request still pending -- is not reachable
  /// there; fixed anyway because reusing `supersedePending` costs nothing and
  /// removes the hazard for tests or any future non-app-scoped use.
  @override
  void dispose() {
    supersedePending();
    super.dispose();
  }
}
