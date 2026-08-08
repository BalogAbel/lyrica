import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/song_library/app_foreground_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WidgetsBindingAppForegroundState', () {
    test('reports foreground when constructed before the binding has settled, '
        'even if the sampled lifecycle state is not resumed', () {
      // Simulate the web repro: the binding already reports a non-resumed
      // state (e.g. hidden) before this observer exists, so the value the
      // constructor samples is not trustworthy.
      TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.hidden,
      );

      final state = WidgetsBindingAppForegroundState();
      addTearDown(state.dispose);

      expect(state.isForeground, isTrue);
    });

    test('a genuine backgrounding transition after an optimistic start still '
        'flips isForeground to false and emits on the stream', () async {
      TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.hidden,
      );

      final state = WidgetsBindingAppForegroundState();
      addTearDown(state.dispose);
      expect(state.isForeground, isTrue);

      final emissions = <bool>[];
      final subscription = state.watchForeground().listen(emissions.add);
      addTearDown(subscription.cancel);

      TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.paused,
      );
      await pumpEventQueue();

      expect(state.isForeground, isFalse);
      expect(emissions, [false]);
    });

    test('the first real lifecycle callback reporting resumed after an '
        'optimistic start is a no-op: no spurious stream emission', () async {
      TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.hidden,
      );

      final state = WidgetsBindingAppForegroundState();
      addTearDown(state.dispose);
      expect(state.isForeground, isTrue);

      final emissions = <bool>[];
      final subscription = state.watchForeground().listen(emissions.add);
      addTearDown(subscription.cancel);

      TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
      await pumpEventQueue();

      expect(state.isForeground, isTrue);
      expect(emissions, isEmpty);
    });
  });
}
