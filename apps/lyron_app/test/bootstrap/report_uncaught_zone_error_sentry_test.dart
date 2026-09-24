import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/bootstrap/bootstrap.dart';
import 'package:lyron_app/src/infrastructure/observability/sentry_observability.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Offline: real Sentry hub, recording transport, `HttpClient` overridden to
/// fail loudly. The DSN only has to be syntactically valid.
class _NullTransport implements Transport {
  @override
  Future<SentryId?> send(SentryEnvelope envelope) async => null;
}

class _FailingHttpOverrides extends HttpOverrides {
  _FailingHttpOverrides(this.attempted);

  final List<String> attempted;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _FailingHttpClient(attempted);
}

class _FailingHttpClient implements HttpClient {
  _FailingHttpClient(this.attempted);

  final List<String> attempted;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    attempted.add(invocation.memberName.toString());
    throw StateError('network attempted in offline test');
  }
}

void main() {
  late List<SentryEvent> events;
  late List<String> httpAttempts;

  Future<void> initSentry() async {
    await Sentry.init((options) {
      options.dsn = 'https://public@o0.ingest.sentry.io/0';
      options.tracesSampleRate = 1.0;
      options.transport = _NullTransport();
      options.beforeSend = (event, hint) {
        events.add(event);
        return event;
      };
    });
  }

  /// Waits (polling on real timers, 10 s deadline) until [done]. Delivery is
  /// not a fixed number of event-loop hops: on Linux CI the SDK's IO enricher
  /// awaits `Process.run('cat', ['/proc/meminfo'])` on the first event after
  /// every `Sentry.init`, which takes real time. Use this before asserting
  /// that an event was delivered, never `pumpEventQueue`.
  Future<void> pumpUntil(bool Function() done) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!done()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('timed out waiting for the Sentry event to be delivered');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  setUp(() {
    events = [];
    httpAttempts = [];
    HttpOverrides.global = _FailingHttpOverrides(httpAttempts);
  });

  tearDown(() async {
    await Sentry.close();
    HttpOverrides.global = null;
  });

  group('reportUncaughtZoneError through the default Sentry capture', () {
    test('reports an unhandled runZonedGuarded fatal event, like the SDK\'s '
        'own zone path', () async {
      await initSentry();
      final error = StateError('boom');

      reportUncaughtZoneError(error, StackTrace.current, dump: (_) {});
      await pumpUntil(() => events.isNotEmpty);

      expect(events, hasLength(1));
      final event = events.single;
      final exception = event.exceptions!.single;
      expect(exception.value, contains('boom'));
      expect(exception.mechanism!.type, 'runZonedGuarded');
      expect(exception.mechanism!.handled, isFalse);
      expect(event.level, SentryLevel.fatal);
      expect(httpAttempts, isEmpty);
    });

    // SDK-parity pin only: the app itself never binds a scope span
    // (`runInSpan` uses `bindToScope: false`), so this test binds one by hand.
    test('marks the active scope span internalError, like the SDK', () async {
      await initSentry();
      final transaction = Sentry.startTransaction(
        'op',
        'task',
        bindToScope: true,
      );

      reportUncaughtZoneError(
        StateError('boom'),
        StackTrace.current,
        dump: (_) {},
      );
      await pumpUntil(() => events.isNotEmpty);

      expect(transaction.status, const SpanStatus.internalError());
      await transaction.finish();
    });

    test('an error escaping a nested span into the guarded zone is reported '
        'unhandled/fatal AND linked to that span\'s trace', () async {
      await initSentry();
      const observability = SentryObservability();
      final error = StateError('escaped a span');
      String? childTraceParent;

      await runBootstrapGuarded(
        () async {
          await observability.runInSpan('root', 'business.refresh', (
            root,
          ) async {
            // Not awaited: the error escapes into the zone's uncaught
            // handler, like an unhandled error in real code.
            unawaited(
              observability.runInSpan('child', 'db.query', (child) async {
                childTraceParent = observability.currentTraceParent;
                throw error;
              }),
            );
            await pumpEventQueue();
          });
          await pumpEventQueue();
        },
        useGuardedZone: true,
        // The default capture path, only the local dump is silenced.
        onError: (e, s) => reportUncaughtZoneError(e, s, dump: (_) {}),
      );
      // The finished root transaction also passes `beforeSend`.
      Iterable<SentryEvent> errorEvents() =>
          events.where((e) => e is! SentryTransaction);
      await pumpUntil(() => errorEvents().isNotEmpty);

      expect(errorEvents(), hasLength(1));
      final event = errorEvents().single;
      final parts = childTraceParent!.split('-');
      expect(event.contexts.trace!.traceId.toString(), parts[1]);
      expect(event.contexts.trace!.spanId.toString(), parts[2]);
      expect(event.level, SentryLevel.fatal);
      expect(event.exceptions!.single.mechanism!.handled, isFalse);
      expect(event.exceptions!.single.mechanism!.type, 'runZonedGuarded');
      expect(httpAttempts, isEmpty);
    });

    test(
      'is a safe no-op that still prints locally when Sentry is not initialized',
      () async {
        expect(Sentry.isEnabled, isFalse);
        final dumped = <FlutterErrorDetails>[];
        final unhandled = <Object>[];

        await runZonedGuarded(() async {
          reportUncaughtZoneError(
            StateError('loud'),
            StackTrace.current,
            dump: dumped.add,
          );
          await pumpEventQueue();
        }, (e, s) => unhandled.add(e));
        // Negative assertions below: Sentry is disabled, so nothing can ever
        // be delivered; a real short delay (not event-loop hops) still lets a
        // stray capture surface before `isEmpty` is checked.
        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(dumped, hasLength(1));
        expect(dumped.single.exception, isA<StateError>());
        expect(unhandled, isEmpty);
        expect(events, isEmpty);
      },
    );
  });
}
