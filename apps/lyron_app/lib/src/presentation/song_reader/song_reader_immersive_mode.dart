import 'package:flutter/services.dart';

/// Applies the reader's system UI mode, skipping the platform call when the
/// requested mode already matches the last applied one.
class SongReaderImmersiveMode {
  bool? _lastApplied;

  void apply(bool active) {
    if (_lastApplied == active) {
      return;
    }
    _lastApplied = active;
    SystemChrome.setEnabledSystemUIMode(
      active ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }
}
