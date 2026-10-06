import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:lyron_app/src/application/active_organization_resolution.dart';
import 'package:lyron_app/src/application/auth/membership_gate_decision.dart';

/// Holds the membership gate's live resolution and decides what the gate
/// shows (SG1-SG4, docs/specs/2026-10-05-offline-first-startup-gate.md).
///
/// The decision itself is [decideMembershipGate]. This class owns the two
/// inputs that are not plain reads: the live resolution, scoped by user
/// (SG3), and the first-run timer (SG4). The plain reads (current user,
/// known organization, pending invite) come in through the readers, so the
/// gate and the router redirect always evaluate the same decision.
class ActiveMembershipController extends ChangeNotifier {
  ActiveMembershipController({
    String? Function()? currentUserIdReader,
    String? Function()? knownOrganizationIdReader,
    bool Function()? hasPendingInviteReader,
    bool Function()? sessionExpiredReader,
    this.firstRunTimeout = const Duration(seconds: 15),
  }) : _currentUserIdReader = currentUserIdReader ?? _nobody,
       _knownOrganizationIdReader = knownOrganizationIdReader ?? _nobody,
       _hasPendingInviteReader = hasPendingInviteReader ?? _noPendingInvite,
       _sessionExpiredReader = sessionExpiredReader ?? _noPendingInvite;

  static String? _nobody() => null;
  static bool _noPendingInvite() => false;

  final String? Function() _currentUserIdReader;
  final String? Function() _knownOrganizationIdReader;
  final bool Function() _hasPendingInviteReader;
  final bool Function() _sessionExpiredReader;

  /// SG4: how long the gate shows its loading state before the connectivity
  /// message (with Retry) replaces it. Above the 10 s native connect
  /// timeout, so an unroutable network reports its real failure first.
  final Duration firstRunTimeout;

  ActiveOrganizationResolution? _last;
  String? _lastUserId;
  bool _resolving = false;
  // The user the running resolution (and its first-run timer) belongs to.
  String? _resolvingUserId;
  bool _firstRunTimedOut = false;
  Timer? _firstRunTimer;
  bool _disposed = false;
  // Token of the most recently started resolution. Bumped by every begin,
  // reset, purge and user change, so a result carrying an older token is stale.
  int _gen = 0;
  // The current user as of the last bump check (see _syncUser).
  String? _epochUserId;

  /// The latest live resolution for the current user, or null when none has
  /// completed for them.
  ActiveOrganizationResolution? get last {
    final last = _last;
    if (last == null) {
      return null;
    }
    final current = _currentUserIdReader();
    if (_lastUserId != null && current != null && _lastUserId != current) {
      return null;
    }
    return last;
  }

  String? get currentUserId => _currentUserIdReader();

  /// Whether the app runs offline-authenticated (ADR-020): the current user
  /// is the last known one and there is no live session, so nothing that
  /// needs the network under that user's identity can succeed.
  bool get isSessionExpired => _sessionExpiredReader();

  MembershipGateView viewFor({required bool hasPendingInvite}) {
    return decideMembershipGate(
      knownOrganizationId: _knownOrganizationIdReader(),
      liveResolution: last,
      hasPendingInvite: hasPendingInvite,
      // A resolution running for someone else is not progress for the
      // current user: showing "loading" for it would hide the failure screen
      // (and its Retry) until the timer elapses.
      awaitingFirstResolution:
          _resolving &&
          !_firstRunTimedOut &&
          _resolvingUserId == _currentUserIdReader(),
    );
  }

  /// Whether authenticated routes outside the membership flow may open. The
  /// router redirect reads this, so it can never disagree with the gate.
  bool get allowsAuthenticatedRoutes =>
      viewFor(hasPendingInvite: _hasPendingInviteReader()) ==
      MembershipGateView.home;

  /// A resolution for [userId] started. Starts the SG4 first-run timer and
  /// returns its token: pass it back to [update]. Only the token of the most
  /// recently started resolution is current, so a result from an earlier one
  /// (superseded by Retry or a redemption refresh, or invalidated by [reset]
  /// or a user change) is ignored (S0 8c C2/C3).
  int beginResolution({required String userId}) {
    _syncUser();
    if (_lastUserId != null && _lastUserId != userId) {
      _last = null;
    }
    _lastUserId = userId;
    _resolving = true;
    _resolvingUserId = userId;
    _firstRunTimedOut = false;
    _firstRunTimer?.cancel();
    _firstRunTimer = Timer(firstRunTimeout, () {
      _firstRunTimer = null;
      _firstRunTimedOut = true;
      _notify();
    });
    final token = ++_gen;
    _notify();
    return token;
  }

  /// Records a finished resolution (SG3). [userId] is the user the
  /// resolution was started for; omit it only where no user is known.
  ///
  /// With a [token] the result is applied only when the token is the latest
  /// one issued: a stale token changes nothing, neither the stored result nor
  /// the running state. Without a token (legacy callers) the userId checks
  /// alone decide.
  void update(ActiveOrganizationResolution next, {String? userId, int? token}) {
    final userChanged = _syncUser();
    if (token != null && token != _gen) {
      if (userChanged) {
        _notify();
      }
      return;
    }
    final current = _currentUserIdReader();
    if (userId != null && userId != current) {
      // Resolved for a user who is no longer current (including nobody, after
      // an explicit sign-out): never keep it, or the same user signing in
      // again would start from a stale result.
      //
      // Whether that result ends the running state: with a token it is the
      // latest resolution, so yes; without one, only the resolution of the
      // user it ran for. Never stop a resolution running for anyone else
      // (the current user's, say).
      if (token != null || userId == _resolvingUserId) {
        _stopResolving();
        _notify();
      } else if (userChanged) {
        _notify();
      }
      return;
    }
    final sameUser =
        userId == null || _lastUserId == null || userId == _lastUserId;
    final isFailure =
        next is ActiveOrganizationUnknownConnectivityFailure ||
        next is ActiveOrganizationUnknownNonConnectivityFailure;
    final keepSelected =
        sameUser && _last is ActiveOrganizationSelected && isFailure;
    _stopResolving();
    if (!keepSelected) {
      _last = next;
      if (userId != null) {
        _lastUserId = userId;
      }
    }
    _notify();
  }

  /// A D5 purge ran for [userId] (SG2). The purge is authoritative for the
  /// current user: whatever resolution is running is superseded and the live
  /// result becomes `verifiedEmpty`. A purge for anyone else changes nothing.
  void recordPurgeResult({required String userId}) {
    final userChanged = _syncUser();
    if (userId != _currentUserIdReader()) {
      if (userChanged) {
        _notify();
      }
      return;
    }
    _gen++;
    _stopResolving();
    _last = const ActiveOrganizationResolution.verifiedEmpty();
    _lastUserId = userId;
    _notify();
  }

  /// Explicit sign-out: forget the live resolution entirely. Also supersedes
  /// every resolution started before it.
  void reset() {
    _gen++;
    _epochUserId = _currentUserIdReader();
    _last = null;
    _lastUserId = null;
    _stopResolving();
    _notify();
  }

  /// An input behind one of the readers changed (auth state, last known
  /// identity, pending invite). Lets the gate and the router re-evaluate.
  void noteInputsChanged() {
    _syncUser();
    _notify();
  }

  /// A change of the current user invalidates every resolution started
  /// before it: it was asked for a user who may no longer be the one the
  /// result would be applied to (A to B to A included), and its running state
  /// belongs to nobody now. Checked wherever a resolution is begun, answered
  /// or noted, and whenever an input changes (the auth controller notifies on
  /// every user change). Nothing is cleared here: the stored result is
  /// already scoped by user. Returns whether the user changed.
  bool _syncUser() {
    final current = _currentUserIdReader();
    if (current == _epochUserId) {
      return false;
    }
    _epochUserId = current;
    _gen++;
    _stopResolving();
    return true;
  }

  void _stopResolving() {
    _resolving = false;
    _resolvingUserId = null;
    _firstRunTimedOut = false;
    _firstRunTimer?.cancel();
    _firstRunTimer = null;
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _firstRunTimer?.cancel();
    _firstRunTimer = null;
    super.dispose();
  }
}
