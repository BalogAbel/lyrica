import 'package:http/http.dart' as http;

/// Fallback base client for platforms that are neither `dart:io` nor
/// `dart:html`/`dart:js_interop`. Same no-connect-timeout behavior as web.
http.Client createBaseHttpClient() => http.Client();
