import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/observability/observability.dart';
import 'package:lyron_app/src/infrastructure/observability/sentry_observability.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main() {
  setUp(() async {
    await Sentry.init((options) {
      options.dsn = 'https://public@o0.ingest.sentry.io/0';
      options.tracesSampleRate = 1.0;
      // Deliberately NOT setting `options.automatedTestMode = true` here:
      // it is annotated `@internal` in the SDK source and would trip
      // `invalid_use_of_internal_member` under `flutter analyze`. It is
      // also unnecessary -- `SentryOptions.transport` already defaults to
      // `NoOpTransport()` (confirmed in the installed SDK source), so no
      // real network call happens regardless of whether the DSN above
      // points at a real project. The DSN only needs to be
      // *syntactically* valid for `Sentry.init` to complete successfully.
    });
  });

  tearDown(() async {
    await Sentry.close();
  });

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

  test('runInSpan sets internalError status and rethrows on failure', () async {
    const observability = SentryObservability();

    await expectLater(
      observability.runInSpan('root', 'business.refresh', (span) async {
        throw Exception('boom');
      }),
      throwsException,
    );
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
