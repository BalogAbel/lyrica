import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
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
}
