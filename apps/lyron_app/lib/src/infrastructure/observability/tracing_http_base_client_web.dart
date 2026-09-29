import 'package:http/http.dart' as http;

/// Web base client: plain [http.Client] (resolves to `BrowserClient`).
/// `BrowserClient` exposes no connect-timeout knob, so web keeps relying on
/// the browser's own TCP/TLS timeout, unchanged from before the two-tier
/// timeout amendment. See
/// docs/architecture/decisions/ADR-037-local-first-catalog-visibility.md,
/// "Amendment: two-tier HTTP timeout".
http.Client createBaseHttpClient() => http.Client();
