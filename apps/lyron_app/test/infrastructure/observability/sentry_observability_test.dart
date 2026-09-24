import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/observability/observability.dart';
import 'package:lyron_app/src/infrastructure/observability/sentry_observability.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Recording fake [Transport]. Installed as `options.transport` so no
/// envelope ever leaves the machine. Optionally blocks (or throws) inside
/// `send` to simulate a slow / failing collector.
class _RecordingTransport implements Transport {
  final envelopes = <SentryEnvelope>[];
  final firstSend = Completer<void>();

  /// When non-null, `send` waits on it (a hung / slow sentry.io).
  Completer<void>? gate;

  /// When non-null, `send` throws it (a failing transport).
  Object? failWith;

  @override
  Future<SentryId?> send(SentryEnvelope envelope) async {
    envelopes.add(envelope);
    if (!firstSend.isCompleted) firstSend.complete();
    final pending = gate;
    if (pending != null) await pending.future;
    final error = failWith;
    if (error != null) throw error;
    return null;
  }
}

const _zeroTraceParent =
    '00-00000000000000000000000000000000-0000000000000000-00';

void main() {
  late _RecordingTransport transport;
  late List<SentryTransaction> transactions;
  late List<SentryEvent> events;
  late List<String> httpAttempts;

  setUp(() async {
    transport = _RecordingTransport();
    transactions = [];
    events = [];
    httpAttempts = [];
    // Global (not `runZoned`): the SDK builds its HTTP client during
    // `Sentry.init`, so the override must already be installed then.
    HttpOverrides.global = _FailingHttpOverrides(httpAttempts);
    await Sentry.init((options) {
      options.dsn = 'https://public@o0.ingest.sentry.io/0';
      options.tracesSampleRate = 1.0;
      // Deliberately NOT setting `options.automatedTestMode = true` here:
      // it is annotated `@internal` in the SDK source and would trip
      // `invalid_use_of_internal_member` under `flutter analyze`.
      //
      // NoOpTransport is NOT a safeguard: `SentryClient` replaces a
      // `NoOpTransport` with a real `HttpTransport` as soon as a DSN is
      // set (sentry_client.dart, `options.transport is NoOpTransport`), so
      // without the recording transport below these tests would POST to
      // o0.ingest.sentry.io. The recording fake keeps everything in
      // memory; the DSN only needs to be syntactically valid.
      options.transport = transport;
      options.beforeSendTransaction = (transaction) {
        transactions.add(transaction);
        return transaction;
      };
      options.beforeSend = (event, hint) {
        events.add(event);
        return event;
      };
    });
  });

  tearDown(() async {
    // Never leave a gated send hanging when the SDK closes.
    transport.gate?.complete();
    await Sentry.close();
    HttpOverrides.global = null;
  });

  /// Lets already-scheduled events (timers, microtasks, transport sends)
  /// run.
  Future<void> pump() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test(
    'runInSpan with no enclosing span starts a root, currentSpan sees it',
    () async {
      const observability = SentryObservability();
      ObservabilitySpan? seenInside;

      await observability.runInSpan('root', 'business.refresh', (span) async {
        seenInside = observability.currentSpan;
        expect(seenInside, isNot(isA<NoopObservabilitySpan>()));
        return null;
      });

      expect(observability.currentSpan, isA<NoopObservabilitySpan>());
    },
  );

  test('nested runInSpan becomes a child of the enclosing span', () async {
    const observability = SentryObservability();
    String? parentTraceId;
    String? childTraceId;

    await observability.runInSpan('root', 'business.refresh', (rootSpan) async {
      parentTraceId = observability.currentTraceParent;
      await observability.runInSpan('child', 'http.client', (childSpan) async {
        childTraceId = observability.currentTraceParent;
        return null;
      });
      return null;
    });

    expect(parentTraceId, isNotNull);
    expect(childTraceId, isNotNull);
    // Same trace, different span (different parent-id segment).
    final parentTraceSegment = parentTraceId!.split('-')[1];
    final childTraceSegment = childTraceId!.split('-')[1];
    expect(childTraceSegment, parentTraceSegment);
    expect(childTraceId!.split('-')[2], isNot(parentTraceId!.split('-')[2]));
  });

  test('concurrent sibling runInSpan calls do not cross-attach', () async {
    const observability = SentryObservability();
    final traceIds = <String>[];

    await Future.wait([
      observability.runInSpan('a', 'business.refresh', (span) async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        traceIds.add(observability.currentTraceParent!.split('-')[1]);
      }),
      observability.runInSpan('b', 'business.refresh', (span) async {
        traceIds.add(observability.currentTraceParent!.split('-')[1]);
      }),
    ]);

    expect(
      traceIds.toSet().length,
      2,
      reason: 'each root must have its own trace id',
    );
  });

  test('currentTraceParent matches the real active span\'s ids', () async {
    const observability = SentryObservability();

    await observability.runInSpan('root', 'business.refresh', (span) async {
      final header = observability.currentTraceParent!;
      final parts = header.split('-');
      // header shape: 00-<traceId>-<spanId>-<flag>
      expect(parts[1].length, 32);
      expect(parts[2].length, 16);
    });
  });

  test('span.startChild returns a non-noop child span', () async {
    const observability = SentryObservability();

    await observability.runInSpan('root', 'business.refresh', (span) async {
      final child = span.startChild('db.query', description: 'child op');
      expect(child, isNot(isA<NoopObservabilitySpan>()));
      await child.finish();
    });
  });

  test('span.setData does not throw', () async {
    const observability = SentryObservability();

    await observability.runInSpan('root', 'business.refresh', (span) async {
      expect(() => span.setData('song_count', 42), returnsNormally);
    });
  });

  test('span.setStatus does not throw for ok and cancelled', () async {
    const observability = SentryObservability();

    await observability.runInSpan('root', 'business.refresh', (span) async {
      expect(() => span.setStatus(ObservabilitySpanStatus.ok), returnsNormally);
      expect(
        () => span.setStatus(ObservabilitySpanStatus.cancelled),
        returnsNormally,
      );
    });
  });

  test(
    'runInSpan accepts span-creation data and still behaves normally',
    () async {
      const observability = SentryObservability();

      await observability.runInSpan('root', 'business.refresh', (span) async {
        expect(observability.currentTraceParent, isNotNull);
      }, data: {'song_id': 'abc123'});
    },
  );

  test('runInSpan sets internalError status and rethrows on failure', () async {
    const observability = SentryObservability();
    final error = Exception('boom');

    await expectLater(
      observability.runInSpan('root', 'business.refresh', (span) async {
        throw error;
      }),
      throwsA(same(error)),
    );
    await pump();

    expect(transactions, hasLength(1));
    expect(
      transactions.single.contexts.trace!.status,
      const SpanStatus.internalError(),
    );
  });

  test('runInSpan marks the transaction ok on success', () async {
    const observability = SentryObservability();

    await observability.runInSpan('root', 'business.refresh', (span) async {});
    await pump();

    expect(transactions, hasLength(1));
    expect(transactions.single.contexts.trace!.status, const SpanStatus.ok());
  });

  test('runInSpan marks the child ok/internalError per outcome', () async {
    const observability = SentryObservability();
    final error = Exception('child boom');

    await expectLater(
      observability.runInSpan('root', 'business.refresh', (rootSpan) async {
        await observability.runInSpan('fine', 'db.query', (s) async {});
        await observability.runInSpan('bad', 'db.query', (s) async {
          throw error;
        });
      }),
      throwsA(same(error)),
    );
    await pump();

    expect(transactions, hasLength(1));
    final tx = transactions.single;
    // The exception propagated through the parent: root is marked too.
    expect(tx.contexts.trace!.status, const SpanStatus.internalError());
    final byName = {for (final s in tx.spans) s.context.description: s};
    expect(byName['fine']!.status, const SpanStatus.ok());
    expect(byName['bad']!.status, const SpanStatus.internalError());
  });

  test('runInSpan failure does not file a Sentry issue', () async {
    const observability = SentryObservability();

    await expectLater(
      observability.runInSpan('root', 'business.refresh', (span) async {
        await observability.runInSpan('child', 'db.query', (s) async {
          throw Exception('expected failure');
        });
      }),
      throwsException,
    );
    await pump();

    expect(events, isEmpty, reason: 'runInSpan must not captureException');
  });

  test('currentSpan/currentTraceParent are noop/null outside any span even '
      'after spans ran', () async {
    const observability = SentryObservability();

    await observability.runInSpan('root', 'business.refresh', (span) async {
      await observability.runInSpan('child', 'db.query', (s) async {});
    });
    await pump();

    expect(observability.currentSpan, isA<NoopObservabilitySpan>());
    expect(observability.currentTraceParent, isNull);
  });

  test('runInSpan data param is PII-scrubbed', () async {
    const observability = SentryObservability();

    await observability.runInSpan('root', 'business.refresh', (span) async {
      await observability.runInSpan(
        'child',
        'db.query',
        (s) async {},
        data: {'token': 'child-secret', 'kept': 2},
      );
    }, data: {'token': 'x', 'ok': 1});
    await pump();

    final tx = transactions.single;
    final rootData = tx.contexts.trace!.data!;
    expect(rootData, containsPair('ok', 1));
    expect(rootData.containsKey('token'), isFalse);
    final childData = tx.spans.single.data;
    expect(childData, containsPair('kept', 2));
    expect(childData.containsKey('token'), isFalse);
  });

  group('finished ambient span (zone leak)', () {
    test('work scheduled inside a span and run after it finished sees no span '
        'and starts a real new root', () async {
      const observability = SentryObservability();
      final leaked = Completer<Map<String, Object?>>();
      String? rootTraceId;

      await observability.runInSpan('root', 'business.refresh', (span) async {
        rootTraceId = observability.currentTraceParent!.split('-')[1];
        Timer(Duration.zero, () async {
          final seen = <String, Object?>{
            'traceParent': observability.currentTraceParent,
            'span': observability.currentSpan,
          };
          await observability.runInSpan('late-root', 'business.refresh', (
            s,
          ) async {
            seen['lateTraceParent'] = observability.currentTraceParent;
          });
          leaked.complete(seen);
        });
      });
      final seen = await leaked.future.timeout(const Duration(seconds: 2));

      expect(seen['traceParent'], isNull);
      expect(seen['span'], isA<NoopObservabilitySpan>());
      final late = seen['lateTraceParent'] as String?;
      expect(late, isNotNull);
      expect(late, isNot(_zeroTraceParent));
      final lateTraceId = late!.split('-')[1];
      expect(lateTraceId, isNot('0' * 32));
      expect(lateTraceId, isNot(rootTraceId));

      await pump();
      expect(
        transactions.map((t) => t.transaction),
        containsAll(['root', 'late-root']),
        reason: 'the late root must be a real, delivered transaction',
      );
    });

    test('a finished child span is not ambient for later work', () async {
      const observability = SentryObservability();
      final leaked = Completer<String?>();

      await observability.runInSpan('root', 'business.refresh', (span) async {
        late final Zone childZone;
        await observability.runInSpan('child', 'db.query', (s) async {
          childZone = Zone.current;
        });
        // Runs in the (finished) child's zone while the root is alive.
        childZone.run(
          () => Timer(Duration.zero, () {
            leaked.complete(observability.currentTraceParent);
          }),
        );
        expect(await leaked.future, isNull);
      });
    });

    test('currentTraceParent is never an all-zero traceparent', () async {
      const observability = SentryObservability();
      final seen = <String?>[];
      final done = Completer<void>();

      await observability.runInSpan('root', 'business.refresh', (span) async {
        seen.add(observability.currentTraceParent);
        Timer(Duration.zero, () async {
          seen.add(observability.currentTraceParent);
          await observability.runInSpan('late', 'db.query', (s) async {
            seen.add(observability.currentTraceParent);
          });
          done.complete();
        });
      });
      await done.future.timeout(const Duration(seconds: 2));

      expect(seen, isNotEmpty);
      for (final header in seen.whereType<String>()) {
        expect(header, isNot(_zeroTraceParent));
        expect(header.split('-')[1], isNot('0' * 32));
        expect(header.split('-')[2], isNot('0' * 16));
      }
    });

    test('currentTraceParent is null when Sentry is not initialised', () async {
      await Sentry.close();
      const observability = SentryObservability();
      String? header;

      await observability.runInSpan('root', 'business.refresh', (span) async {
        header = observability.currentTraceParent;
      });

      expect(header, isNull);
    });
  });

  group('telemetry delivery is off the critical path', () {
    test('a hung transport does not delay runInSpan', () async {
      const observability = SentryObservability();
      transport.gate = Completer<void>();

      final result = await observability
          .runInSpan('root', 'business.refresh', (span) async => 42)
          .timeout(const Duration(seconds: 2));

      expect(result, 42);
      // The send was (or will be) attempted, and is still pending.
      await transport.firstSend.future.timeout(const Duration(seconds: 2));
      expect(transport.gate!.isCompleted, isFalse);
    });

    test('a failing transport surfaces no error from runInSpan', () async {
      const observability = SentryObservability();
      transport.failWith = StateError('transport down');
      final uncaught = <Object>[];
      Object? result;

      await runZonedGuarded(() async {
        result = await observability.runInSpan(
          'root',
          'business.refresh',
          (span) async => 'value',
        );
        await pump();
      }, (error, stack) => uncaught.add(error));

      expect(result, 'value');
      expect(uncaught, isEmpty);
    });

    test('a throwing finish never becomes an uncaught error', () async {
      const observability = SentryObservability();
      transport.failWith = StateError('transport down');
      final uncaught = <Object>[];
      final error = Exception('body failed');
      Object? caught;

      await runZonedGuarded(() async {
        try {
          await observability.runInSpan('root', 'business.refresh', (
            span,
          ) async {
            throw error;
          });
        } catch (e) {
          caught = e;
        }
        await pump();
      }, (e, stack) => uncaught.add(e));

      expect(caught, same(error), reason: 'body error rethrown unmodified');
      expect(uncaught, isEmpty);
    });

    test('async and sync body throws finish the span exactly once', () async {
      const observability = SentryObservability();

      await expectLater(
        observability.runInSpan('sync', 'business.refresh', (span) {
          throw StateError('sync throw');
        }),
        throwsStateError,
      );
      await expectLater(
        observability.runInSpan('async', 'business.refresh', (span) async {
          await Future<void>.delayed(Duration.zero);
          throw StateError('async throw');
        }),
        throwsStateError,
      );
      await pump();

      expect(transactions.map((t) => t.transaction), ['sync', 'async']);
    });
  });

  test('tests are offline: no HTTP request is attempted', () async {
    const observability = SentryObservability();

    await observability.runInSpan('root', 'business.refresh', (span) async {
      await observability.runInSpan('child', 'db.query', (s) async {});
    });
    await pump();

    expect(httpAttempts, isEmpty);
    expect(transport.envelopes, isNotEmpty);
  });

  test('addBreadcrumb does not throw', () {
    const observability = SentryObservability();

    expect(
      () =>
          observability.addBreadcrumb('did a thing', category: 'song_catalog'),
      returnsNormally,
    );
  });

  test('setUserContext and clearUserContext do not throw', () async {
    const observability = SentryObservability();

    observability.setUserContext(userId: 'u1', organizationId: 'o1');
    observability.clearUserContext();
  });

  test(
    'captureException does not throw and does not require an active span',
    () {
      const observability = SentryObservability();

      expect(
        () => observability.captureException(
          Exception('handled'),
          StackTrace.current,
        ),
        returnsNormally,
      );
    },
  );

  test('captureException inside a span does not throw', () async {
    const observability = SentryObservability();

    await observability.runInSpan('root', 'business.refresh', (span) async {
      observability.captureException(Exception('handled'), StackTrace.current);
    });
  });
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

  /// Names of every `HttpClient` member touched.
  final List<String> attempted;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    attempted.add(invocation.memberName.toString());
    throw StateError('network attempted in offline test');
  }
}
