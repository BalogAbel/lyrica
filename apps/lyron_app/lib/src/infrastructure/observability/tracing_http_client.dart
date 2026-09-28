import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:lyron_app/src/application/observability/observability.dart';

/// Injects a W3C `traceparent` header (built from the current span, if
/// any) into every outgoing request, so a Sentry trace's `trace_id` is
/// correlatable with the corresponding Supabase Cloud request log.
///
/// The header is never sent on web ([isWeb] defaults to [kIsWeb]):
/// `traceparent` is not a CORS-safelisted header, and injecting it
/// unconditionally would break web requests outright if Supabase's CORS
/// configuration does not explicitly allow it. See
/// docs/specs/2026-08-28-w3c-traceparent-correlation-spike.md for the web
/// verification runbook required before this gate can be lifted.
///
/// Wraps every request with a configurable timeout to bound the socket-layer
/// hang window on poor/no connectivity, per
/// docs/specs/2026-09-28-offline-catalog-local-first-visibility.md Step 1.2.
class TracingHttpClient extends http.BaseClient {
  TracingHttpClient(
    this._inner,
    this._observability, {
    Duration timeout = const Duration(seconds: 15),
    this._isWeb = kIsWeb,
  }) : _timeout = timeout;

  final http.Client _inner;
  final Observability _observability;
  final Duration _timeout;
  final bool _isWeb;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (!_isWeb) {
      final traceParent = _observability.currentTraceParent;
      if (traceParent != null) {
        request.headers['traceparent'] = traceParent;
      }
    }
    return _inner.send(request).timeout(_timeout);
  }

  @override
  void close() {
    _inner.close();
  }
}
