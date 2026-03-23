import 'package:flutter/foundation.dart';

class AuthRouterRefreshNotifier extends ChangeNotifier {
  AuthRouterRefreshNotifier(Listenable source) : _source = source {
    _source.addListener(notifyListeners);
  }

  final Listenable _source;

  @override
  void dispose() {
    _source.removeListener(notifyListeners);
    super.dispose();
  }
}
