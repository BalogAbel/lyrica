import 'package:flutter/foundation.dart';
import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/song_library/active_catalog_context.dart';
import 'package:lyron_app/src/application/song_library/song_catalog_controller.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';

typedef LatestPlanningOrganizationReader =
    Future<String?> Function({required String userId});
typedef PlanningAuthSessionReader = AppAuthSession? Function();

class ActivePlanningContextController extends ChangeNotifier {
  ActivePlanningContextController({
    required PlanningAuthSessionReader authSessionReader,
    required ActiveOrganizationReader organizationReader,
    required LatestPlanningOrganizationReader latestOrganizationReader,
  }) : _authSessionReader = authSessionReader,
       _organizationReader = organizationReader,
       _latestOrganizationReader = latestOrganizationReader;

  final PlanningAuthSessionReader _authSessionReader;
  final ActiveOrganizationReader _organizationReader;
  final LatestPlanningOrganizationReader _latestOrganizationReader;

  ActivePlanningReadContext? _state;

  ActivePlanningReadContext? get state => _state;

  Future<void> refresh({bool allowCachedFallback = false}) async {
    final session = _authSessionReader();
    if (session == null) {
      clear();
      return;
    }

    String? organizationId;
    try {
      organizationId = await _organizationReader();
    } on Object {
      if (allowCachedFallback) {
        organizationId = await _latestOrganizationReader(
          userId: session.userId,
        );
      } else if (_state != null) {
        return;
      } else {
        clear();
        return;
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

  void syncToCatalogContext(ActiveCatalogContext? context) {
    if (context == null) {
      return;
    }

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
