import 'package:flutter/foundation.dart';
import 'package:lyron_app/src/application/active_organization_resolution.dart';

class ActiveMembershipController extends ChangeNotifier {
  ActiveOrganizationResolution _last =
      const ActiveOrganizationUnknownConnectivityFailure();

  ActiveOrganizationResolution get last => _last;

  void update(ActiveOrganizationResolution next) {
    _last = next;
    notifyListeners();
  }
}
