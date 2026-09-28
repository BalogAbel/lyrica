import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' as io_client;

/// Connect-timeout bound applied to the native `dart:io` [HttpClient] that
/// backs [createBaseHttpClient] on native platforms. See
/// docs/architecture/decisions/ADR-037-local-first-catalog-visibility.md,
/// "Amendment: two-tier HTTP timeout".
const connectTimeout = Duration(seconds: 10);

/// Builds the `dart:io` [HttpClient] with [connectTimeout] applied.
///
/// Split out from [createBaseHttpClient] so a test can construct one
/// directly and assert `connectionTimeout` without needing to drive a real
/// hung TCP connect through the wrapped [io_client.IOClient].
HttpClient createConnectTimeoutHttpClient() {
  return HttpClient()..connectionTimeout = connectTimeout;
}

/// Native base client: a `dart:io` [HttpClient] with a 10s connect timeout,
/// wrapped as an [http.Client] via [io_client.IOClient].
http.Client createBaseHttpClient() {
  return io_client.IOClient(createConnectTimeoutHttpClient());
}
