import 'package:http/http.dart' as http;

import 'tracing_http_base_client_stub.dart'
    if (dart.library.html) 'tracing_http_base_client_web.dart'
    if (dart.library.io) 'tracing_http_base_client_io.dart'
    as platform;

/// Builds the platform-appropriate base [http.Client] for [TracingHttpClient]
/// (see tracing_http_client.dart) to wrap: on native platforms, a `dart:io`
/// [HttpClient] with a 10s connect timeout wrapped as an `IOClient`; on web,
/// a plain client (no connect-timeout knob exists on `BrowserClient`). See
/// docs/architecture/decisions/ADR-037-local-first-catalog-visibility.md,
/// "Amendment: two-tier HTTP timeout".
http.Client createTracingBaseHttpClient() => platform.createBaseHttpClient();
