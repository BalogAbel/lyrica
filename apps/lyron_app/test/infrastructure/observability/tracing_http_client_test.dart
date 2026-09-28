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

class _TimeoutThrowingInnerClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw TimeoutException('Timeout thrown directly by http.Client', null);
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

  test('throws TimeoutException when inner client never completes', () async {
    final inner = _NeverCompletingInnerClient();
    final client = TracingHttpClient(
      inner,
      const _FakeObservability(null),
      timeout: const Duration(milliseconds: 100),
      isWeb: false,
    );

    final request = http.Request('GET', Uri.parse('https://example.com/'));

    expect(
      client.send(request),
      throwsA(isA<TimeoutException>()),
    );
  });

  test(
    'a TracingHttpClient timeout surfaces as AuthRetryableFetchException '
    'when driven through a real gotrue GoTrueClient (gotrue-2.27.2, pinned '
    'via supabase_flutter)',
    () async {
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
    },
  );
}
