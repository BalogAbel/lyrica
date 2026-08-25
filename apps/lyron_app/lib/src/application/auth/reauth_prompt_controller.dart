import 'dart:async';

import 'package:flutter/foundation.dart';

/// A pending confirmation of a destructive local-data operation, published
/// by [ReauthPromptController] and presented by `ReauthPromptHost`.
///
/// Two variants share one host and one at-most-one-pending guard rather than
/// each owning a separate controller (ADR-029; D5.4/ADR-035 Phase 4 reuses
/// this host rather than introducing a second one): [ReauthDifferentUserPrompt]
/// for a different-user sign-in wipe, and [MembershipRevocationPurgePrompt]
/// for the two-confirmation membership-revocation purge.
sealed class ReauthPrompt {
  const ReauthPrompt({required this.requestId});

  final int requestId;
}

/// The prior user's email and how much local work a different-user
/// sign-in wipe would destroy. `pendingCount` of `null` means the count
/// could not be determined -- an honest "unknown", not a guess (see D4 in
/// `docs/specs/2026-07-30-recovery-actions-that-outlive-their-widget.md`).
final class ReauthDifferentUserPrompt extends ReauthPrompt {
  const ReauthDifferentUserPrompt({
    required super.requestId,
    required this.email,
    required this.pendingCount,
  });

  final String email;
  final int? pendingCount;
}

/// How much local work a membership-revocation purge would destroy (D5.4,
/// docs/specs/2026-08-19-local-data-durability-contract.md, ADR-035 Phase
/// 4). `pendingCount` of `null` means the count could not be determined --
/// treated as nonzero, never as zero, mirroring [ReauthDifferentUserPrompt].
final class MembershipRevocationPurgePrompt extends ReauthPrompt {
  const MembershipRevocationPurgePrompt({
    required super.requestId,
    required this.pendingCount,
  });

  final int? pendingCount;
}

enum ReauthPromptResult { confirmed, cancelled, superseded }

/// Publishes a pending reauth confirmation and awaits its answer.
///
/// Lives app-scoped (see `reauthPromptControllerProvider` in
/// `auth_providers.dart`) and NOT autoDispose: a pending prompt must survive
/// whatever screen happens to be on top when the different-user sign-in is
/// detected, not get torn down along with it.
///
/// Only one prompt may be pending at a time. `resolveReauth` awaits a single
/// `confirmDifferentUser` call per `signedIn` transition before doing
/// anything else, so a second concurrent request would mean two
/// different-user resolutions racing. `lastKnownIdentityPersistenceProvider`
/// (`auth_providers.dart`) enforces this structurally, not just by
/// assertion: it serializes every signedIn-edge resolution through a single
/// future chain, so a second resolution's `confirmDifferentUser` call can
/// only ever start after the first has fully finished, including the wait
/// for its own dialog answer. The `StateError` below is therefore a
/// defence-in-depth invariant, not a path any caller in this codebase can
/// currently reach -- rejecting the second request turns a would-be race
/// into a loud bug instead of silently queueing or dropping a confirmation
/// that guards data deletion.
class ReauthPromptController extends ChangeNotifier {
  int _nextRequestId = 0;
  ReauthPrompt? _pending;
  Completer<ReauthPromptResult>? _completer;

  ReauthPrompt? get pending => _pending;

  /// Publishes [email]/[pendingCount] as the pending different-user prompt
  /// and returns a future that completes with the answer once [answer] is
  /// called. [pendingCount] of `null` means the count could not be
  /// determined.
  Future<ReauthPromptResult> requestConfirmation({
    required String email,
    required int? pendingCount,
  }) {
    return _publish(
      (requestId) => ReauthDifferentUserPrompt(
        requestId: requestId,
        email: email,
        pendingCount: pendingCount,
      ),
    );
  }

  /// Publishes [pendingCount] as the pending membership-revocation-purge
  /// prompt (D5.4) and returns a future that completes with the answer once
  /// [answer] is called. Shares this controller's single-pending guard with
  /// [requestConfirmation] -- the two prompt kinds are mutually exclusive at
  /// any one time, same as two different-user requests would be.
  Future<ReauthPromptResult> requestMembershipRevocationConfirmation({
    required int? pendingCount,
  }) {
    return _publish(
      (requestId) => MembershipRevocationPurgePrompt(
        requestId: requestId,
        pendingCount: pendingCount,
      ),
    );
  }

  Future<ReauthPromptResult> _publish(
    ReauthPrompt Function(int requestId) build,
  ) {
    if (_pending != null) {
      throw StateError(
        'A reauth prompt is already pending; cannot request a second one '
        'before the first is answered.',
      );
    }
    final completer = Completer<ReauthPromptResult>();
    _completer = completer;
    _pending = build(_nextRequestId++);
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
