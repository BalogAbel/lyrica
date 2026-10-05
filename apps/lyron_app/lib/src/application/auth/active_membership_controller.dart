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
    this.firstRunTimeout = const Duration(seconds: 15),
  }) : _currentUserIdReader = currentUserIdReader ?? _nobody,
       _knownOrganizationIdReader = knownOrganizationIdReader ?? _nobody,
       _hasPendingInviteReader = hasPendingInviteReader ?? _noPendingInvite;

  static String? _nobody() => null;
  static bool _noPendingInvite() => false;

  final String? Function() _currentUserIdReader;
  final String? Function() _knownOrganizationIdReader;
  final bool Function() _hasPendingInviteReader;

  /// SG4: how long the gate shows its loading state before the connectivity
  /// message (with Retry) replaces it. Above the 10 s native connect
  /// timeout, so an unroutable network reports its real failure first.
  final Duration firstRunTimeout;

  ActiveOrganizationResolution? _last;
  String? _lastUserId;
  bool _resolving = false;
  bool _firstRunTimedOut = false;
  Timer? _firstRunTimer;
  bool _disposed = false;

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

  MembershipGateView viewFor({required bool hasPendingInvite}) {
    return decideMembershipGate(
      knownOrganizationId: _knownOrganizationIdReader(),
      liveResolution: last,
      hasPendingInvite: hasPendingInvite,
      awaitingFirstResolution: _resolving && !_firstRunTimedOut,
    );
  }

  /// Whether authenticated routes outside the membership flow may open. The
  /// router redirect reads this, so it can never disagree with the gate.
  bool get allowsAuthenticatedRoutes =>
      viewFor(hasPendingInvite: _hasPendingInviteReader()) ==
      MembershipGateView.home;

  /// A resolution for [userId] started. Starts the SG4 first-run timer.
  void beginResolution({required String userId}) {
    if (_lastUserId != null && _lastUserId != userId) {
      _last = null;
    }
    _lastUserId = userId;
    _resolving = true;
    _firstRunTimedOut = false;
    _firstRunTimer?.cancel();
    _firstRunTimer = Timer(firstRunTimeout, () {
      _firstRunTimer = null;
      _firstRunTimedOut = true;
      _notify();
    });
    _notify();
  }

  /// Records a finished resolution (SG3). [userId] is the user the
  /// resolution was started for; omit it only where no user is known.
  void update(ActiveOrganizationResolution next, {String? userId}) {
    final current = _currentUserIdReader();
    if (userId != null && userId != current) {
      // Resolved for a user who is no longer current (including nobody, after
      // an explicit sign-out): never keep it, or the same user signing in
      // again would start from a stale result.
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

  /// Explicit sign-out: forget the live resolution entirely.
  void reset() {
    _last = null;
    _lastUserId = null;
    _stopResolving();
    _notify();
  }

  /// An input behind one of the readers changed (auth state, last known
  /// identity, pending invite). Lets the gate and the router re-evaluate.
  void noteInputsChanged() => _notify();

  void _stopResolving() {
    _resolving = false;
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
