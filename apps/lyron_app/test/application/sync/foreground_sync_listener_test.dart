import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/song_library/app_foreground_state.dart';
import 'package:lyron_app/src/application/sync/foreground_sync_listener.dart';

class _FakeForegroundState implements AppForegroundState {
  final _controller = StreamController<bool>.broadcast();

  @override
  bool get isForeground => true;

  @override
  Stream<bool> watchForeground() => _controller.stream;

  void emit(bool isForeground) => _controller.add(isForeground);

  Future<void> close() => _controller.close();
}

void main() {
  test('fires onResume only on background-to-foreground transition', () async {
    final fake = _FakeForegroundState();
    addTearDown(fake.close);
    var calls = 0;
    final listener = ForegroundSyncListener(
      foregroundState: fake,
      onResume: () async => calls++,
    );
    addTearDown(listener.dispose);

    fake.emit(true); // initial true while previous is null → no fire
    await Future<void>.delayed(Duration.zero);
    expect(calls, 0);

    fake.emit(false);
    await Future<void>.delayed(Duration.zero);
    fake.emit(true);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);

    fake.emit(true); // duplicate foreground
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
  });
}
