import 'dart:async';

import 'package:flutter/widgets.dart';

abstract interface class AppForegroundState {
  bool get isForeground;

  Stream<bool> watchForeground();
}

class WidgetsBindingAppForegroundState
    with WidgetsBindingObserver
    implements AppForegroundState {
  WidgetsBindingAppForegroundState() {
    WidgetsBinding.instance.addObserver(this);
  }

  final StreamController<bool> _foregroundController =
      StreamController<bool>.broadcast();

  // Optimistic until the framework reports a real transition. A value read
  // from WidgetsBinding.lifecycleState before the first
  // didChangeAppLifecycleState callback is not trustworthy: on web it can be
  // sampled as non-resumed even though the app is actually foregrounded,
  // which would otherwise permanently disarm the recovery timer with no
  // later callback to correct it. See
  // docs/specs/2026-08-08-web-catalog-refresh-race.md (D3).
  bool _isForeground = true;

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

  static bool _isForegroundLifecycleState(AppLifecycleState state) {
    return state == AppLifecycleState.resumed;
  }
}
