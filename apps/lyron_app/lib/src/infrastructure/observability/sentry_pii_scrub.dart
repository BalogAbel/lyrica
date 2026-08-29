const _piiKeyDenylist = {
  'authorization',
  'apikey',
  'accesstoken',
  'refreshtoken',
  'token',
};

final _keySeparatorPattern = RegExp(r'[-_]');

/// Denylist matching ignores case and `-`/`_` separators, so header-style
/// keys (`Access-Token`, `Api-Key`) are caught the same as this codebase's
/// own snake_case keys (`access_token`) -- both normalize to the same
/// entry (`accesstoken`, `apikey`).
String _normalizeKey(String key) =>
    key.toLowerCase().replaceAll(_keySeparatorPattern, '');

/// Unanchored so a JWT embedded in a larger string (e.g. `"Bearer eyJ..."`)
/// is still redacted, not just a value that is *entirely* a JWT.
final _jwtPattern = RegExp(
  r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*',
);

final _whitespacePattern = RegExp(r'\s');

/// Recursively scrubs a data map before it reaches the Sentry SDK.
/// Defense-in-depth only -- call sites must never pass a raw
/// token/credential or a personal identifier (email, display name) as
/// span/breadcrumb data in the first place. ChordPro content, lyrics, and
/// other business/domain content are deliberately NOT scrubbed -- per
/// explicit product direction, only credentials and personal identifiers
/// are treated as sensitive here. See
/// docs/architecture/decisions/ADR-036-observability-sentry-adapter.md
/// point 7 for the full policy.
Map<String, Object?>? scrubPii(Map<String, Object?>? data) {
  if (data == null) return null;
  return _scrubMap(data);
}

Map<String, Object?> _scrubMap(Map<String, Object?> data) {
  final result = <String, Object?>{};
  for (final entry in data.entries) {
    if (_piiKeyDenylist.contains(_normalizeKey(entry.key))) {
      continue;
    }
    result[entry.key] = _scrubValue(entry.value);
  }
  return result;
}

Object? _scrubValue(Object? value) {
  if (value is Map<String, Object?>) {
    return _scrubMap(value);
  }
  if (value is List) {
    return value.map(_scrubValue).toList(growable: false);
  }
  if (value is String) {
    return _scrubString(value);
  }
  return value;
}

String _scrubString(String value) {
  final withoutJwt = value.replaceAll(_jwtPattern, '[redacted]');

  // Ordinary prose (error messages, breadcrumb text) can legitimately
  // contain a '?' and parse as a schemeless URI with a non-empty query
  // (e.g. "did it work? yes it did" -> path "did it work", query "yes it
  // did") -- real URLs never contain raw whitespace, so this guard is what
  // keeps the schemeless-URL handling below from mangling ordinary text.
  if (withoutJwt.contains(_whitespacePattern)) {
    return withoutJwt;
  }

  final uri = Uri.tryParse(withoutJwt);
  if (uri != null && uri.query.isNotEmpty) {
    // No `hasScheme` requirement: a schemeless "host/path?query" value
    // (e.g. a Supabase URL missing its "https://" prefix) still carries a
    // secret in its query string and must still be stripped. `userInfo` is
    // dropped unconditionally, never preserved -- `user:password@host`
    // syntax is inherently a credential, not merely PII-adjacent context
    // worth keeping.
    return Uri(
      scheme: uri.scheme.isEmpty ? null : uri.scheme,
      host: uri.host.isEmpty ? null : uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
      fragment: uri.fragment.isEmpty ? null : uri.fragment,
    ).toString();
  }
  return withoutJwt;
}
