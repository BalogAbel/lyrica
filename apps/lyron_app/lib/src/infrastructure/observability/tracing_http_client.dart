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
/// Wraps every request with a three-tier timeout, per
/// docs/specs/2026-09-28-offline-catalog-local-first-visibility.md Step 1.2
/// and its "Review follow-ups R1-R3" amendment (further corrected by I1,
/// see below):
///
/// 1. A connect timeout (10s, native only), applied to [_inner] itself
///    before it ever reaches this class -- see
///    tracing_http_base_client.dart / tracing_http_base_client_io.dart.
/// 2. A response backstop ([_timeout], default 60s) applied here, in
///    [send], to bound how long the app waits for a response once
///    connected.
/// 3. A LONGER response backstop ([_tokenRefreshTimeout], default 120s)
///    applied instead of tier 2 for `/auth/v1/token` (gotrue token
///    refresh/exchange) requests. `/auth/v1/token` used to be fully
///    exempted from any response backstop (R1's original shape), on the
///    theory that abandoning that request client-side after the
///    connection is established risks discarding a refresh token the
///    server already rotated. That exemption was itself a regression
///    (I1): `dart:io`'s connect timeout only covers connect+TLS, not a
///    stall after the request is written, so a dead socket (NAT drop,
///    wifi-to-cellular handoff, no keepalive) on the token endpoint would
///    hang forever. Worse, gotrue's `GoTrueClient._callRefreshToken`
///    de-dupes concurrent refreshes for the same token into one shared
///    `Completer`, which `SupabaseClient._getAccessToken` awaits *before*
///    any REST/RPC call reaches this client at all -- so one hung refresh
///    could block every subsequent call in the app, for every identity,
///    forever. Tier 3 keeps the original intent (don't abandon a refresh
///    moments before/after the server rotates the token on an ordinary
///    slow-but-alive connection) while still bounding the dead-socket
///    case, by using a bound well above tier 2 and above any plausible
///    upstream gateway timeout, instead of no bound at all. See
///    docs/architecture/decisions/ADR-037-local-first-catalog-visibility.md,
///    "Amendment: two-tier HTTP timeout", and
///    docs/deferred/2026-09-28-client-abandoned-committed-write-lf-t5b.md
///    for the residual risk this does not eliminate for write RPCs.
class TracingHttpClient extends http.BaseClient {
  TracingHttpClient(
    this._inner,
    this._observability, {
    this._timeout = const Duration(seconds: 60),
    this._tokenRefreshTimeout = const Duration(seconds: 120),
    this._isWeb = kIsWeb,
  });

  final http.Client _inner;
  final Observability _observability;
  final Duration _timeout;
  final Duration _tokenRefreshTimeout;
  final bool _isWeb;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (!_isWeb) {
      final traceParent = _observability.currentTraceParent;
      if (traceParent != null) {
        request.headers['traceparent'] = traceParent;
      }
    }
    if (_isTokenRefreshRequest(request.url)) {
      // Longer, but still finite, response backstop (tier 3, I1): bounds
      // a dead-socket/hung-forever refresh without abandoning an
      // ordinary slow-but-alive token exchange moments too early.
      return _inner.send(request).timeout(_tokenRefreshTimeout);
    }
    return _inner.send(request).timeout(_timeout);
  }

  /// Path-matched (not full-URL, since `supabaseUrl` varies by
  /// environment) against gotrue's token endpoint,
  /// `$supabaseUrl/auth/v1/token`.
  static bool _isTokenRefreshRequest(Uri url) =>
      url.path.endsWith('/auth/v1/token');

  @override
  void close() {
    _inner.close();
  }
}
