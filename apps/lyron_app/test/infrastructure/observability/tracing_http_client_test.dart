import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gotrue/gotrue.dart';
import 'package:http/http.dart' as http;
import 'package:lyron_app/src/application/observability/observability.dart';
import 'package:lyron_app/src/infrastructure/observability/tracing_http_client.dart';

class _RecordingInnerClient extends http.BaseClient {
  http.BaseRequest? lastRequest;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastRequest = request;
    return http.StreamedResponse(const Stream.empty(), 200);
  }
}

class _NeverCompletingInnerClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    // Never completes — simulates a hung network call.
    return Completer<http.StreamedResponse>().future;
  }
}

class _FakeObservability extends NoopObservability {
  const _FakeObservability(this._traceParent);

  final String? _traceParent;

  @override
  String? get currentTraceParent => _traceParent;
}

const _sampleTraceParent =
    '00-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-bbbbbbbbbbbbbbbb-01';

void main() {
  test('injects the traceparent header when a span is active', () async {
    final inner = _RecordingInnerClient();
    // `_FakeObservability` is instantiated non-const here: `'a' * 32` (String
    // repetition) is not a const-evaluable expression in Dart, so `const
    // _FakeObservability('00-${'a' * 32}-...')` would fail to compile. Use
    // the plain literal `_sampleTraceParent` above instead of repetition —
    // it is defined as a `const` top-level string precisely so it can be
    // reused across the two tests below without re-typing 48 hex characters.
    final client = TracingHttpClient(
      inner,
      _FakeObservability(_sampleTraceParent),
      isWeb: false,
    );

    await client.get(Uri.parse('https://example.supabase.co/rest/v1/songs'));

    expect(inner.lastRequest!.headers['traceparent'], _sampleTraceParent);
  });

  test('omits the header when there is no active span', () async {
    final inner = _RecordingInnerClient();
    final client = TracingHttpClient(
      inner,
      const _FakeObservability(null),
      isWeb: false,
    );

    await client.get(Uri.parse('https://example.supabase.co/rest/v1/songs'));

    expect(inner.lastRequest!.headers.containsKey('traceparent'), isFalse);
  });

  test('omits the header on web even when a span is active', () async {
    final inner = _RecordingInnerClient();
    final client = TracingHttpClient(
      inner,
      _FakeObservability(_sampleTraceParent),
      isWeb: true,
    );

    await client.get(Uri.parse('https://example.supabase.co/rest/v1/songs'));

    expect(inner.lastRequest!.headers.containsKey('traceparent'), isFalse);
  });

  test(
    'throws TimeoutException for a non-token request once the response '
    'backstop elapses (tier 2, R1)',
    () async {
      final inner = _NeverCompletingInnerClient();
      final client = TracingHttpClient(
        inner,
        const _FakeObservability(null),
        timeout: const Duration(milliseconds: 100),
        isWeb: false,
      );

      final request = http.Request('GET', Uri.parse('https://example.com/'));

      expect(client.send(request), throwsA(isA<TimeoutException>()));
    },
  );

  test(
    'does NOT apply the general response backstop to a /auth/v1/token '
    'request (tier 2 is skipped for it) -- guarded: the identical setup '
    'on a non-token URL above DOES throw within the same short backstop, '
    'proving this is a real behavior difference, not a no-op',
    () async {
      final inner = _NeverCompletingInnerClient();
      final client = TracingHttpClient(
        inner,
        const _FakeObservability(null),
        // Deliberately the SAME short duration used by the non-token test
        // above, which throws within it. The token-refresh path is no
        // longer exempted from any timeout (I1) -- it uses the longer,
        // separate `tokenRefreshTimeout` instead -- so it must NOT throw
        // within this short *general* backstop duration.
        timeout: const Duration(milliseconds: 100),
        tokenRefreshTimeout: const Duration(seconds: 10),
        isWeb: false,
      );

      final request = http.Request(
        'POST',
        Uri.parse('https://example.supabase.co/auth/v1/token?grant_type=refresh_token'),
      );

      await expectLater(
        client
            .send(request)
            .timeout(
              const Duration(milliseconds: 300),
              onTimeout: () =>
                  throw StateError('did not time out (expected)'),
            ),
        throwsA(isA<StateError>()),
      );
    },
  );

  test(
    'throws TimeoutException for a /auth/v1/token request once the '
    'longer token-refresh backstop elapses (tier 3, I1) -- proves the '
    'token-refresh path is bounded, not hung forever',
    () async {
      final inner = _NeverCompletingInnerClient();
      final client = TracingHttpClient(
        inner,
        const _FakeObservability(null),
        // General backstop is intentionally long here so only the
        // token-refresh backstop below can be the one that fires.
        timeout: const Duration(seconds: 10),
        tokenRefreshTimeout: const Duration(milliseconds: 100),
        isWeb: false,
      );

      final request = http.Request(
        'POST',
        Uri.parse('https://example.supabase.co/auth/v1/token?grant_type=refresh_token'),
      );

      await expectLater(
        // Bounded outer guard (distinct exception type) so a regression
        // back to "no timeout at all" fails this test promptly -- with a
        // clear mismatch (StateError, not TimeoutException) -- instead of
        // hanging the suite or accidentally matching via the outer bound.
        client
            .send(request)
            .timeout(
              const Duration(seconds: 5),
              onTimeout: () =>
                  throw StateError('did not time out within the '
                      'token-refresh backstop (regression to unbounded)'),
            ),
        throwsA(isA<TimeoutException>()),
      );
    },
  );

  test('a TracingHttpClient timeout surfaces as AuthRetryableFetchException '
      'when driven through a real gotrue GoTrueClient (gotrue-2.27.2, pinned '
      'via supabase_flutter)', () async {
    // Real characterization test, not a source citation: a genuine
    // GoTrueClient is constructed with a TracingHttpClient (wrapping an
    // inner http.Client that never completes, with a short test-only
    // timeout) as its httpClient, and a real gotrue method is called.
    // gotrue's GotrueFetch._handleRequest wraps ANY exception the injected
    // http.Client throws -- including our TimeoutException -- as
    // AuthRetryableFetchException. This exercises that live, not merely
    // asserting it from reading gotrue-2.27.2/lib/src/fetch.dart.
    final inner = _NeverCompletingInnerClient();
    final tracingClient = TracingHttpClient(
      inner,
      const _FakeObservability(null),
      timeout: const Duration(milliseconds: 50),
      isWeb: false,
    );

    final client = GoTrueClient(
      url: 'https://example.supabase.co/auth/v1',
      httpClient: tracingClient,
      // No token to auto-refresh in this test, and startAutoRefresh()
      // would otherwise leave a periodic Timer running past the test.
      autoRefreshToken: false,
    );

    await expectLater(
      client.getUser('a-fake-jwt-for-this-test-only'),
      throwsA(isA<AuthRetryableFetchException>()),
    );
  });
}
