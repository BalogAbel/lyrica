/// Normalized keys (see [_normalizeKey]) dropped by exact match.
const _piiExactKeys = {'authorization', 'jwt', 'codeverifier'};

/// Normalized keys ending in one of these are dropped (`refresh_token`,
/// `x-api-key`, `client_secret`, `set-cookie`, `id_token`, ...). A suffix
/// match rather than a substring match on purpose: `token_count`,
/// `tokenizer` and `tokens_used` are ordinary metrics, not credentials.
const _piiKeySuffixes = ['token', 'secret', 'password', 'cookie', 'apikey'];

final _keyIgnoredCharsPattern = RegExp(r'[-_.\s]');

/// Lower-cases and strips `-`, `_`, `.` and whitespace, so header-style keys
/// (`Access-Token`, `X-Api-Key`, `api key`, `access.token`) normalize to the
/// same form as this codebase's snake_case keys (`access_token`).
String _normalizeKey(String key) =>
    key.toLowerCase().replaceAll(_keyIgnoredCharsPattern, '');

bool _isSensitiveKey(String key) {
  final normalized = _normalizeKey(key);
  if (_piiExactKeys.contains(normalized)) return true;
  for (final suffix in _piiKeySuffixes) {
    if (normalized.endsWith(suffix)) return true;
  }
  return false;
}

/// Supabase secret API keys (`sb_secret_...`). Linear: the literal prefix
/// must match before the character class is consumed.
final _supabaseSecretKeyPattern = RegExp(r'sb_secret_[A-Za-z0-9_-]+');

/// A maximal run of characters that can occur inside a JWT.
final _jwtCharRunPattern = RegExp(r'[A-Za-z0-9_.-]+');

const _jwtPrefix = 'eyJ';
const _redacted = '[redacted]';

/// Redacts JWTs (`eyJ<seg>.<seg>.<seg>`) anywhere in [value], including when
/// embedded in a larger string (`"Bearer eyJ..."`) or glued to other text.
///
/// Deliberately not one regex: the unanchored `eyJ[A-Za-z0-9_-]+\.…` form is
/// quadratic on hostile input such as `'eyJ' * 30000` (every `eyJ` start
/// scans to the end of the run before failing), which blocks the main
/// isolate. Instead the string is cut into maximal JWT-character runs (one
/// linear pass), each run is split on `.`, and matches are found by looking
/// at whole dot-delimited parts, so every character is visited a constant
/// number of times.
String _redactJwts(String value) {
  if (!value.contains(_jwtPrefix)) return value;
  return value.replaceAllMapped(
    _jwtCharRunPattern,
    (match) => _redactJwtsInRun(match[0]!),
  );
}

String _redactJwtsInRun(String run) {
  if (!run.contains(_jwtPrefix) || !run.contains('.')) return run;
  final parts = run.split('.');
  final out = StringBuffer();
  var index = 0;
  while (index < parts.length) {
    final part = parts[index];
    final start = part.indexOf(_jwtPrefix);
    // header needs >= 1 char after `eyJ`, payload >= 1 char, signature part
    // must exist (it may be empty, e.g. unsigned JWTs).
    final isJwt =
        start >= 0 &&
        start + _jwtPrefix.length < part.length &&
        index + 2 < parts.length &&
        parts[index + 1].isNotEmpty;
    if (isJwt) {
      out
        ..write(part.substring(0, start))
        ..write(_redacted);
      index += 3;
    } else {
      out.write(part);
      index += 1;
    }
    if (index < parts.length) out.write('.');
  }
  return out.toString();
}

final _whitespaceDelimitedTokenPattern = RegExp(r'\S+');

/// `://` followed by userinfo up to the last `@` of the authority.
final _userInfoPattern = RegExp(r'://[^/?#]*@');

/// A leading URI scheme of at least two characters, so a Windows drive
/// letter (`C:\...`) is not mistaken for one.
final _schemePattern = RegExp(r'^[A-Za-z][A-Za-z0-9+.\-]+:');

/// Whether [beforeDelimiter] (the part of a token in front of a `?` or `#`)
/// looks like a URL: it either has a real scheme (`https:`, `mailto:`) or a
/// schemeless `host/path` shape. Anything else (`[C]Hello?[G]World`,
/// `C:\Users\john\file?.txt`, `a?b`) is ordinary content and is left alone.
bool _looksLikeUrl(String beforeDelimiter) =>
    _schemePattern.hasMatch(beforeDelimiter) || beforeDelimiter.contains('/');

/// Recursively scrubs a data map before it reaches the Sentry SDK.
///
/// Defense-in-depth only -- call sites must never pass a raw
/// token/credential or a personal identifier (email, display name) as
/// span/breadcrumb data in the first place. ChordPro content, lyrics, and
/// other business/domain content are deliberately NOT scrubbed -- per
/// explicit product direction, only credentials and personal identifiers
/// are treated as sensitive here. See
/// docs/architecture/decisions/ADR-036-observability-sentry-adapter.md
/// point 7 for the full policy.
///
/// What is scrubbed:
///
/// * Keys: normalized (lower-cased, `-`/`_`/`.`/whitespace removed) and
///   dropped when equal to `authorization`, `jwt` or `codeverifier`, or when
///   they end in `token`, `secret`, `password`, `cookie` or `apikey`
///   (`refresh_token`, `x-api-key`, `client_secret`, `set-cookie`, ...).
///   Suffix, not substring: `token_count` and `tokenizer` are kept.
/// * Values: maps (any key type, keys stringified), iterables (returned as
///   fixed-length lists) and [Uri]s (stringified, then scrubbed as strings)
///   are traversed recursively.
/// * Strings: JWTs and `sb_secret_...` Supabase secret keys are replaced
///   with `[redacted]` anywhere in the string (JWT scanning is linear-time).
///   The string is then scrubbed per whitespace-delimited token, preserving
///   the original whitespace, so a URL inside an error message is handled
///   while ordinary prose (`did it work? yes it did`) is untouched. Within a
///   URL-shaped token the userinfo (`user:pass@`) is dropped, the query
///   string is dropped, and a `key=value` fragment (implicit-flow
///   `#access_token=...`) is dropped; a plain fragment (`#frag`) is kept. A
///   token counts as URL-shaped only with a scheme of two or more characters
///   or a `/` before the delimiter, so `[C]Hello?[G]World`, `a?b` and
///   `C:\dir\file?.txt` are never mangled.
///
/// Documented non-goal: email addresses are NOT redacted (call sites must
/// not pass them; `mailto:foo@bar.com?subject=hi` keeps the address).
Map<String, Object?>? scrubPii(Map<String, Object?>? data) {
  if (data == null) return null;
  return _scrubMap(data);
}

Map<String, Object?> _scrubMap(Map<Object?, Object?> data) {
  final result = <String, Object?>{};
  for (final entry in data.entries) {
    final key = entry.key.toString();
    if (_isSensitiveKey(key)) {
      continue;
    }
    result[key] = _scrubValue(entry.value);
  }
  return result;
}

Object? _scrubValue(Object? value) {
  if (value is Map) {
    return _scrubMap(value);
  }
  if (value is Iterable) {
    return value.map(_scrubValue).toList(growable: false);
  }
  if (value is Uri) {
    return _scrubString(value.toString());
  }
  if (value is String) {
    return _scrubString(value);
  }
  return value;
}

String _scrubString(String value) {
  final redacted = _redactJwts(
    value,
  ).replaceAll(_supabaseSecretKeyPattern, _redacted);
  return redacted.replaceAllMapped(
    _whitespaceDelimitedTokenPattern,
    (match) => _scrubToken(match[0]!),
  );
}

String _scrubToken(String token) {
  if (!token.contains('?') && !token.contains('#') && !token.contains('@')) {
    return token;
  }

  // userInfo is dropped unconditionally, never preserved --
  // `user:password@host` syntax is inherently a credential.
  var rest = token.replaceFirstMapped(_userInfoPattern, (_) => '://');

  var fragment = '';
  final hash = rest.indexOf('#');
  if (hash >= 0) {
    fragment = rest.substring(hash);
    rest = rest.substring(0, hash);
    // `#access_token=A&refresh_token=R` (implicit-flow deep links) carries
    // credentials; a plain `#frag` anchor does not.
    if (fragment.contains('=') && _looksLikeUrl(rest)) fragment = '';
  }

  final question = rest.indexOf('?');
  if (question >= 0 &&
      question < rest.length - 1 &&
      _looksLikeUrl(rest.substring(0, question))) {
    rest = rest.substring(0, question);
  }
  return '$rest$fragment';
}
