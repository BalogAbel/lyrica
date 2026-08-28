import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/observability/observability.dart';

void main() {
  group('NoopObservability', () {
    const observability = NoopObservability();

    test(
      'runInSpan runs body with a NoopObservabilitySpan and returns its result',
      () async {
        final result = await observability.runInSpan('name', 'operation', (
          span,
        ) async {
          expect(span, isA<NoopObservabilitySpan>());
          return 42;
        });

        expect(result, 42);
      },
    );

    test('currentSpan is a NoopObservabilitySpan, never null', () {
      expect(observability.currentSpan, isA<NoopObservabilitySpan>());
    });

    test('currentTraceParent is null', () {
      expect(observability.currentTraceParent, isNull);
    });

    test(
      'captureException, addBreadcrumb, setUserContext, clearUserContext are safe no-ops',
      () {
        expect(
          () => observability.captureException(
            Exception('x'),
            StackTrace.current,
          ),
          returnsNormally,
        );
        expect(
          () => observability.addBreadcrumb('msg', category: 'cat'),
          returnsNormally,
        );
        expect(
          () =>
              observability.setUserContext(userId: 'u1', organizationId: 'o1'),
          returnsNormally,
        );
        expect(() => observability.clearUserContext(), returnsNormally);
      },
    );

    test('runInSpan propagates a thrown error from body', () async {
      await expectLater(
        observability.runInSpan(
          'n',
          'o',
          (span) async => throw Exception('boom'),
        ),
        throwsException,
      );
    });
  });

  group('NoopObservabilitySpan', () {
    const span = NoopObservabilitySpan();

    test('startChild returns another NoopObservabilitySpan', () {
      expect(span.startChild('op'), isA<NoopObservabilitySpan>());
    });

    test('setData, setStatus, finish are safe no-ops', () async {
      expect(() => span.setData('k', 'v'), returnsNormally);
      expect(() => span.setStatus(ObservabilitySpanStatus.ok), returnsNormally);
      await expectLater(span.finish(), completes);
    });
  });
}
