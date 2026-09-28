import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/infrastructure/observability/tracing_http_base_client_io.dart';

void main() {
  test('createConnectTimeoutHttpClient wires a 10s connect timeout onto the '
      'native dart:io HttpClient', () {
    // This test runs on the VM (flutter test's default native target), so
    // dart:io is directly importable here without going through the
    // conditional-import seam that selects this file on native platforms.
    //
    // A true end-to-end connect-timeout test (an unroutable address that
    // genuinely hangs the TCP handshake for 10s) is not something a fast,
    // hermetic unit test can exercise without an actual socket -- per the
    // task's own allowance, this instead asserts the CONSTRUCTION/wiring
    // of the connect timeout onto the underlying dart:io HttpClient that
    // the platform-aware base client (tracing_http_base_client.dart)
    // ultimately wraps as the IOClient TracingHttpClient's `_inner`
    // becomes on native.
    final client = createConnectTimeoutHttpClient();
    addTearDown(client.close);

    expect(client, isA<HttpClient>());
    expect(client.connectionTimeout, const Duration(seconds: 10));
    expect(connectTimeout, const Duration(seconds: 10));
  });
}
