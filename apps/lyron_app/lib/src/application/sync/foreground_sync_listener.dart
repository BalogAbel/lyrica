import 'dart:async';

import 'package:lyron_app/src/application/song_library/app_foreground_state.dart';

typedef ForegroundSyncCallback = Future<void> Function();

class ForegroundSyncListener {
  ForegroundSyncListener({
    required AppForegroundState foregroundState,
    required ForegroundSyncCallback onResume,
  }) : _onResume = onResume {
    _subscription = foregroundState.watchForeground().listen(_handle);
  }

  final ForegroundSyncCallback _onResume;
  late final StreamSubscription<bool> _subscription;
  bool? _previousIsForeground;

  void _handle(bool isForeground) {
    final previous = _previousIsForeground;
    _previousIsForeground = isForeground;
    if (previous != false || !isForeground) return;
    unawaited(_onResume());
  }

  Future<void> dispose() async {
    await _subscription.cancel();
  }
}
