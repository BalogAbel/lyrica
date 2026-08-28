const _piiKeyDenylist = {
  'authorization',
  'apikey',
  'access_token',
  'refresh_token',
  'token',
};

final _jwtPattern = RegExp(
  r'^eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*$',
);

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
    if (_piiKeyDenylist.contains(entry.key.toLowerCase())) {
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
  if (_jwtPattern.hasMatch(value)) {
    return '[redacted]';
  }
  final uri = Uri.tryParse(value);
  if (uri != null && uri.hasScheme && uri.query.isNotEmpty) {
    return Uri(
      scheme: uri.scheme,
      userInfo: uri.userInfo.isEmpty ? null : uri.userInfo,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
      fragment: uri.fragment.isEmpty ? null : uri.fragment,
    ).toString();
  }
  return value;
}
