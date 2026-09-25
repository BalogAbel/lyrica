import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/bootstrap/bootstrap.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main() {
  group('reportUncaughtZoneError', () {
    test('captures to Sentry AND dumps locally', () {
      final captured = <(Object, StackTrace)>[];
      final dumped = <FlutterErrorDetails>[];
      final error = StateError('boom');
      final stack = StackTrace.current;

      reportUncaughtZoneError(
        error,
        stack,
        capture: (e, s) => captured.add((e, s)),
        dump: dumped.add,
      );

      expect(captured, hasLength(1));
      expect(captured.single.$1, same(error));
      expect(captured.single.$2, same(stack));
      expect(dumped, hasLength(1));
      expect(dumped.single.exception, same(error));
      expect(dumped.single.stack, same(stack));
    });

    test('still dumps when capture throws synchronously', () {
      final dumped = <FlutterErrorDetails>[];

      reportUncaughtZoneError(
        StateError('boom'),
        StackTrace.current,
        capture: (e, s) => throw StateError('sentry broke'),
        dump: dumped.add,
      );

      expect(dumped, hasLength(1));
    });

    test(
      'a capture future that fails does not become an unhandled error',
      () async {
        final unhandled = <Object>[];
        await runZonedGuarded(() async {
          reportUncaughtZoneError(
            StateError('boom'),
            StackTrace.current,
            capture: (e, s) => Future<void>.error(StateError('sentry broke')),
            dump: (_) {},
          );
          await pumpEventQueue();
        }, (e, s) => unhandled.add(e));

        expect(unhandled, isEmpty);
      },
    );

    test('default path with Sentry disabled still prints loudly and does not '
        're-enter FlutterError.onError', () async {
      expect(Sentry.isEnabled, isFalse);
      final printed = <String>[];
      final originalDebugPrint = debugPrint;
      final originalOnError = FlutterError.onError;
      var onErrorCalls = 0;
      debugPrint = (String? message, {int? wrapWidth}) =>
          printed.add(message ?? '');
      FlutterError.onError = (_) => onErrorCalls++;
      addTearDown(() {
        debugPrint = originalDebugPrint;
        FlutterError.onError = originalOnError;
      });

      reportUncaughtZoneError(StateError('loud-boom'), StackTrace.current);
      await pumpEventQueue();

      expect(printed.join('\n'), contains('loud-boom'));
      expect(onErrorCalls, 0);
    });
  });

  group('runBootstrapGuarded', () {
    test('guarded: runs body in its own error zone', () async {
      final outer = Zone.current;
      Zone? inner;

      await runBootstrapGuarded(
        () async {
          inner = Zone.current;
        },
        useGuardedZone: true,
        onError: (e, s) {},
      );

      expect(inner, isNotNull);
      expect(inner, isNot(same(outer)));
    });

    test(
      'guarded: an async failure of the body reaches the handler once',
      () async {
        final errors = <Object>[];
        final boom = StateError('supabase init failed');

        await runBootstrapGuarded(
          () async {
            await Future<void>.delayed(Duration.zero);
            throw boom;
          },
          useGuardedZone: true,
          onError: (e, s) => errors.add(e),
        );
        await pumpEventQueue();

        expect(errors, [same(boom)]);
      },
    );

    test(
      'guarded: a synchronous throw from the body reaches the handler once',
      () async {
        final errors = <Object>[];
        final boom = StateError('sync');

        await runBootstrapGuarded(
          () => throw boom,
          useGuardedZone: true,
          onError: (e, s) => errors.add(e),
        );
        await pumpEventQueue();

        expect(errors, [same(boom)]);
      },
    );

    test(
      'guarded: an unawaited stray async error reaches the handler once',
      () async {
        final errors = <Object>[];
        final boom = StateError('stray');

        await runBootstrapGuarded(
          () async {
            unawaited(Future<void>.delayed(Duration.zero, () => throw boom));
          },
          useGuardedZone: true,
          onError: (e, s) => errors.add(e),
        );
        await pumpEventQueue();

        expect(errors, [same(boom)]);
      },
    );

    test(
      'guarded: continuation after await stays in the guarded zone',
      () async {
        Zone? before;
        Zone? after;

        await runBootstrapGuarded(
          () async {
            before = Zone.current;
            await Future<void>.delayed(Duration.zero);
            after = Zone.current;
          },
          useGuardedZone: true,
          onError: (e, s) {},
        );

        expect(after, same(before));
      },
    );

    test(
      'native: no zone wrap, error propagates to the caller, handler unused',
      () async {
        final outer = Zone.current;
        Zone? inner;
        var handlerCalls = 0;
        final boom = StateError('native failure');

        await expectLater(
          runBootstrapGuarded(
            () async {
              inner = Zone.current;
              throw boom;
            },
            useGuardedZone: false,
            onError: (e, s) => handlerCalls++,
          ),
          throwsA(same(boom)),
        );

        expect(inner, same(outer));
        expect(handlerCalls, 0);
      },
    );
  });
}
