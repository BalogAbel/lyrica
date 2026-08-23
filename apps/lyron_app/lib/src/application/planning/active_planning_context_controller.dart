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

class ActivePlanningContextController extends ChangeNotifier {
  ActivePlanningContextController({
    required this._authSessionReader,
    required this._organizationReader,
    required this._latestOrganizationReader,
    this._onVerifiedEmptyMembership,
  });

  final PlanningAuthSessionReader _authSessionReader;
  final ActiveOrganizationReader _organizationReader;
  final LatestPlanningOrganizationReader _latestOrganizationReader;
  final VerifiedEmptyMembershipHandler? _onVerifiedEmptyMembership;

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
    try {
      organizationId = await _organizationReader();
      if (organizationId == null) {
        _verifiedEmptyMembershipSeen = true;
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

    if (organizationId == null &&
        organizationLookupWasConnectivityFailure &&
        !_verifiedEmptyMembershipSeen) {
      if (_state != null) {
        return;
      }
      clear();
      return;
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
