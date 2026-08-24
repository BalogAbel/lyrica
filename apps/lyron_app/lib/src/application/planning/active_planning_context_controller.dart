import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/song_library/active_catalog_context.dart';
import 'package:lyron_app/src/application/song_library/song_catalog_controller.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/shared/connectivity_failure.dart';

typedef LatestPlanningOrganizationReader =
    Future<String?> Function({required String userId});
typedef PlanningAuthSessionReader = AppAuthSession? Function();
// D5.4/D5.5 (docs/specs/2026-08-19-local-data-durability-contract.md,
// ADR-035 Phase 4): reports whether a purge actually ran, mirroring
// SongCatalogController's identically-motivated handler type.
typedef VerifiedEmptyMembershipHandler =
    Future<bool> Function({required String userId});
// RED 2 (final whole-branch review, D5.2): the only event allowed to clear
// an outstanding membership-revocation marker, mirroring
// SongCatalogController's identically-motivated hook.
typedef VerifiedNonEmptyMembershipHandler =
    Future<void> Function({required String userId});

class ActivePlanningContextController extends ChangeNotifier {
  ActivePlanningContextController({
    required this._authSessionReader,
    required this._organizationReader,
    required this._latestOrganizationReader,
    this._onVerifiedEmptyMembership,
    this._onVerifiedNonEmptyMembership,
  });

  final PlanningAuthSessionReader _authSessionReader;
  final ActiveOrganizationReader _organizationReader;
  final LatestPlanningOrganizationReader _latestOrganizationReader;
  final VerifiedEmptyMembershipHandler? _onVerifiedEmptyMembership;
  final VerifiedNonEmptyMembershipHandler? _onVerifiedNonEmptyMembership;

  ActivePlanningReadContext? _state;
  bool _verifiedEmptyMembershipSeen = false;

  ActivePlanningReadContext? get state => _state;

  Future<void> refresh({bool allowCachedFallback = false}) async {
    final session = _authSessionReader();
    if (session == null) {
      resetForSessionLifecycle();
      return;
    }

    String? organizationId;
    var organizationLookupWasConnectivityFailure = false;
    // YELLOW 5 fix (final whole-branch review): whether the organization
    // lookup itself resolved verified-empty. The purge-gate handler call
    // used to live inside this try -- a throw from it (or from the purge it
    // triggers) was misclassified as an organization-lookup failure and
    // silently cleared or kept the planning context. The handler is now
    // invoked below, outside this try/catch entirely.
    var reachedVerifiedEmpty = false;
    try {
      organizationId = await _organizationReader();
      if (organizationId == null) {
        reachedVerifiedEmpty = true;
      }
    } on Object catch (error) {
      if (isConnectivityFailure(error)) {
        organizationLookupWasConnectivityFailure = true;
        if (allowCachedFallback &&
            _state == null &&
            !_verifiedEmptyMembershipSeen) {
          organizationId = await _latestOrganizationReader(
            userId: session.userId,
          );
        } else if (_state != null) {
          return;
        } else {
          clear();
          return;
        }
      } else if (_state != null) {
        return;
      } else {
        clear();
        return;
      }
    }

    if (reachedVerifiedEmpty) {
      _verifiedEmptyMembershipSeen = true;
      // YELLOW 6 fix (D5.5 rule 4): `session` was captured before the
      // awaited organization lookup above -- re-read and compare identity
      // immediately before entering the purge gate, so a resolution
      // captured under one user can never purge a different user's data
      // after that user signed in during the await.
      final currentSession = _authSessionReader();
      if (currentSession == null || currentSession.userId != session.userId) {
        return;
      }
      // D5.4/D5.5 -- Step 2: do NOT clear _state up front. A single
      // verified-empty resolution must not hide plans that are still
      // fully intact (ADR-020) -- only clear once the handler reports a
      // purge genuinely ran. With no handler wired (test-only
      // construction), there is nothing to gate a purge on, so this
      // conservatively leaves the state untouched.
      final handler = _onVerifiedEmptyMembership;
      final purged = handler == null
          ? false
          : await handler(userId: session.userId);
      if (purged) {
        _setState(null);
      }
      return;
    }

    if (organizationId == null &&
        organizationLookupWasConnectivityFailure &&
        !_verifiedEmptyMembershipSeen) {
      if (_state != null) {
        return;
      }
      clear();
      return;
    }

    // D5.2: a genuinely fresh non-empty resolution is the only event
    // permitted to clear the revocation marker.
    //
    // The `organizationLookupWasConnectivityFailure` guard is load-bearing,
    // not a belt-and-braces check: the cached-fallback path above does reach
    // this line, with a cached organizationId and the flag set. Deleting the
    // guard would let an offline cached fallback clear the marker, which
    // D5.2 forbids in both directions.
    //
    // Awaited and reported rather than fire-and-forget, for the same reason
    // as the equivalent call in `SongCatalogController._refreshCatalog`: a
    // dropped store failure would leave the marker set with no audit record
    // and no retry, silently reinstating the empty/non-empty/empty sequence
    // this clear exists to break. Reported rather than rethrown so a
    // transient identity-store error cannot break the read path (ADR-020).
    if (organizationId != null && !organizationLookupWasConnectivityFailure) {
      // D5.5 rule 4, mirroring SongCatalogController's identical guard:
      // `session` was captured before the awaited organization lookup, and
      // staleness alone does not assert session identity. Re-read and
      // compare before clearing the marker.
      //
      // This SKIPS the clear rather than returning. The rest of this method
      // establishes the planning read context; returning here would leave
      // that context unset whenever the session changed mid-lookup.
      final currentSession = _authSessionReader();
      final sessionUnchanged =
          currentSession != null && currentSession.userId == session.userId;
      if (sessionUnchanged) {
        try {
          await _onVerifiedNonEmptyMembership?.call(userId: session.userId);
        } catch (error, stackTrace) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stackTrace,
              library: 'ActivePlanningContextController',
              context: ErrorDescription(
                'failed to clear the membership-revocation marker after a '
                'freshly verified non-empty membership resolution -- the '
                'marker is still set and will be cleared by the next '
                'successful non-empty refresh',
              ),
            ),
          );
        }
      }
    }

    _setState(
      organizationId == null
          ? null
          : ActivePlanningReadContext(
              userId: session.userId,
              organizationId: organizationId,
            ),
    );
  }

  void clear() {
    _setState(null);
  }

  void resetForSessionLifecycle() {
    _verifiedEmptyMembershipSeen = false;
    clear();
  }

  void syncToCatalogContext(ActiveCatalogContext? context) {
    if (context == null) {
      _setState(null);
      return;
    }

    _verifiedEmptyMembershipSeen = false;
    _setState(
      ActivePlanningReadContext(
        userId: context.userId,
        organizationId: context.organizationId,
      ),
    );
  }

  void _setState(ActivePlanningReadContext? nextState) {
    if (_state == nextState) {
      return;
    }

    _state = nextState;
    notifyListeners();
  }
}
