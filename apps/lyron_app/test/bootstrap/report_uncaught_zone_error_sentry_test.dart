import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/bootstrap/bootstrap.dart';
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
      await pumpEventQueue();

      expect(events, hasLength(1));
      final event = events.single;
      final exception = event.exceptions!.single;
      expect(exception.value, contains('boom'));
      expect(exception.mechanism!.type, 'runZonedGuarded');
      expect(exception.mechanism!.handled, isFalse);
      expect(event.level, SentryLevel.fatal);
      expect(httpAttempts, isEmpty);
    });

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
      await pumpEventQueue();

      expect(transaction.status, const SpanStatus.internalError());
      await transaction.finish();
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

        expect(dumped, hasLength(1));
        expect(dumped.single.exception, isA<StateError>());
        expect(unhandled, isEmpty);
        expect(events, isEmpty);
      },
    );
  });
}
