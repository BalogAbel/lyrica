import 'dart:async';

import 'package:flutter/widgets.dart';

abstract interface class AppForegroundState {
  bool get isForeground;

  Stream<bool> watchForeground();
}

class WidgetsBindingAppForegroundState
    with WidgetsBindingObserver
    implements AppForegroundState {
  WidgetsBindingAppForegroundState()
    : _isForeground = _isForegroundLifecycleState(
        WidgetsBinding.instance.lifecycleState,
      ) {
    WidgetsBinding.instance.addObserver(this);
  }

  final StreamController<bool> _foregroundController =
      StreamController<bool>.broadcast();
  bool _isForeground;

  @override
  bool get isForeground => _isForeground;

  @override
  Stream<bool> watchForeground() => _foregroundController.stream;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final isForeground = _isForegroundLifecycleState(state);
    if (isForeground == _isForeground) {
      return;
    }

    _isForeground = isForeground;
    _foregroundController.add(isForeground);
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_foregroundController.close());
  }

  static bool _isForegroundLifecycleState(AppLifecycleState? state) {
    return state == null || state == AppLifecycleState.resumed;
  }
}
