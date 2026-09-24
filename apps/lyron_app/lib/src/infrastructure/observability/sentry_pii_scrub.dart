/// Normalized keys (see [_normalizeKey]) dropped by exact match.
///
/// The plural `tokens` (and its `access`/`refresh`/`id` compounds) is exact
/// only, never a suffix: `max_tokens`, `prompt_tokens` and `total_tokens` are
/// ordinary metrics. The singular forms are covered by the `token` suffix.
const _piiExactKeys = {
  'jwt',
  'codeverifier',
  'tokens',
  'accesstokens',
  'refreshtokens',
  'idtokens',
};

/// Normalized keys ending in one of these are dropped (`refresh_token`,
/// `x-api-key`, `client_secret`, `set-cookie`, `id_token`, `Proxy-Authorization`,
/// `private_key`, `aws_access_key`, `db_credentials`, ...). A suffix
/// match rather than a substring match on purpose: `token_count`,
/// `tokenizer` and `tokens_used` are ordinary metrics, not credentials.
const _piiKeySuffixes = [
  'token',
  'secret',
  'password',
  'cookie',
  'apikey',
  'authorization',
  'privatekey',
  'secretkey',
  'accesskey',
  'credential',
  'credentials',
];

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

/// A leading URI scheme of at least two characters, so a Windows drive
/// letter (`C:\...`) is not mistaken for one.
final _schemePattern = RegExp(r'^[A-Za-z][A-Za-z0-9+.\-]+:');

/// A bare host (`abc.supabase.co`, `x.co:8080`, and also `v1.2`).
final _hostShapePattern = RegExp(r'^[\w-]+(\.[\w-]+)+(:\d+)?$');

const _quote = 0x22; // "
const _apostrophe = 0x27; // '
const _lessThan = 0x3C; // <
const _greaterThan = 0x3E; // >
const _openParen = 0x28;
const _closeParen = 0x29;
const _openBracket = 0x5B;
const _closeBracket = 0x5D;
const _openBrace = 0x7B;
const _closeBrace = 0x7D;
const _hash = 0x23;
const _question = 0x3F;

/// Drops `user:password@` from the first `://` up to the LAST `@` of the
/// token, so a raw `?`, `/` or `#` inside the userinfo (`https://u:p?ss@h/x`,
/// `https://u:p/ss@h/x`) cannot end the authority early and leak the tail.
///
/// Trade-off (deliberate, over-redacts rather than leaks): an `@` that is
/// really in the path or query (`https://host/a@b`,
/// `https://host/p?email=a@b.c`) also swallows everything before it, giving
/// `https://b` / `https://b.c`. A token without `://` (`mailto:a@b`) is left
/// alone. Uses `lastIndexOf` rather than a backtracking regex so hostile
/// input stays linear.
String _dropUserInfo(String token) {
  final scheme = token.indexOf('://');
  if (scheme < 0) return token;
  final at = token.lastIndexOf('@');
  if (at < scheme + 3) return token;
  return '${token.substring(0, scheme + 3)}${token.substring(at + 1)}';
}

/// End (exclusive) of the query/fragment region that starts at [from].
///
/// The region stops at a quote, `<` or `>` (a URL embedded in JSON or angle
/// brackets), at an UNBALANCED closer `)`, `]` or `}` (a URL wrapped in
/// brackets; balanced pairs such as `?a[0]=1` stay inside), and, for a query
/// ([stopAtHash]), at `#`. `,` `;` and `.` are deliberately NOT terminators:
/// commas are legal in query values (`ids=1,2`) and ending there would leak
/// the remainder. Consequence: an apostrophe or quote inside a query value
/// (legal but rare) ends the region early and the rest of that value is
/// kept.
int _regionEnd(String token, int from, {required bool stopAtHash}) {
  var parens = 0;
  var brackets = 0;
  var braces = 0;
  for (var i = from; i < token.length; i++) {
    final c = token.codeUnitAt(i);
    if (c == _quote ||
        c == _apostrophe ||
        c == _lessThan ||
        c == _greaterThan) {
      return i;
    }
    if (c == _hash && stopAtHash) return i;
    if (c == _openParen) {
      parens++;
    } else if (c == _closeParen) {
      if (parens == 0) return i;
      parens--;
    } else if (c == _openBracket) {
      brackets++;
    } else if (c == _closeBracket) {
      if (brackets == 0) return i;
      brackets--;
    } else if (c == _openBrace) {
      braces++;
    } else if (c == _closeBrace) {
      if (braces == 0) return i;
      braces--;
    }
  }
  return token.length;
}

bool _regionHasEquals(String token, int from, int to) {
  for (var i = from; i < to; i++) {
    if (token.codeUnitAt(i) == 0x3D) return true;
  }
  return false;
}

/// Classification of the URL-ish text in front of the first `?`/`#` of a
/// segment: [urlLike] when it has a real scheme or a `/` (`https:`,
/// `mailto:`, `host/path`); [hostShaped] when it is a bare host. A bare host
/// is only treated as a URL when its query/fragment contains `=` (see
/// [_stripQueryAndFragment]). Anything else (`[C]Hello?[G]World`,
/// `C:\Users\john\file?.txt`, `a?b`) is ordinary content and left alone.
class _Base {
  _Base(String base) {
    // Text after the last opener/assignment/separator, so `url=x.co`,
    // `(x.co` and `a,x.co` classify by the URL part only.
    var start = 0;
    for (var i = 0; i < base.length; i++) {
      final c = base.codeUnitAt(i);
      if (c == _openParen ||
          c == _openBracket ||
          c == _openBrace ||
          c == 0x3D || // =
          c == 0x2C || // ,
          c == 0x3B) {
        // ;
        start = i + 1;
      }
    }
    final candidate = base.substring(start);
    urlLike = base.contains('/') || _schemePattern.hasMatch(candidate);
    hostShaped = _hostShapePattern.hasMatch(candidate);
  }

  late final bool urlLike;
  late final bool hostShaped;
}

/// Drops the query string and any `key=value` fragment of every URL-shaped
/// segment of [token] in a single linear pass, keeping everything after the
/// region verbatim (see [_regionEnd]). A segment restarts after a quote,
/// `<` or `>`, so several URLs in one token (a JSON blob) are handled
/// independently.
///
/// A plain fragment (`#frag`) and an empty query (`?` alone) are kept. A
/// bare host such as `abc.supabase.co?apikey=S` counts as a URL because its
/// query contains `=`; the same rule also strips a version-like
/// `v1.2?x=1` (host-shaped and ambiguous -- stripping is the fail-safe
/// choice).
String _stripQueryAndFragment(String token) {
  final out = StringBuffer();
  var copyFrom = 0;
  var segmentStart = 0;
  _Base? base;
  // Host-shaped `?` regions without any `=` need no re-scan for later `?`
  // inside the same region (keeps hostile `x.co????...` linear).
  var noEqualsUntil = 0;
  var i = 0;
  while (i < token.length) {
    final c = token.codeUnitAt(i);
    if (c == _quote ||
        c == _apostrophe ||
        c == _lessThan ||
        c == _greaterThan) {
      segmentStart = i + 1;
      base = null;
      i++;
      continue;
    }
    if (c != _question && c != _hash) {
      i++;
      continue;
    }
    final current = base ??= _Base(token.substring(segmentStart, i));
    final isQuery = c == _question;
    if (!current.urlLike && !current.hostShaped) {
      i++;
      continue;
    }
    if (isQuery && i < noEqualsUntil) {
      i++;
      continue;
    }
    final end = _regionEnd(token, i + 1, stopAtHash: isQuery);
    final nonEmpty = end > i + 1;
    final hasEquals = _regionHasEquals(token, i + 1, end);
    final strip = isQuery
        ? nonEmpty && (current.urlLike || hasEquals)
        : hasEquals;
    if (strip) {
      out.write(token.substring(copyFrom, i));
      copyFrom = end;
      i = end;
    } else if (isQuery) {
      if (!hasEquals) noEqualsUntil = end;
      i++;
    } else {
      i = end;
    }
  }
  out.write(token.substring(copyFrom));
  return out.toString();
}

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
///   dropped when equal to `jwt`, `codeverifier`, `tokens`, `accesstokens`,
///   `refreshtokens` or `idtokens`, or when they end in `token`, `secret`,
///   `password`, `cookie`, `apikey`, `authorization`, `privatekey`,
///   `secretkey`, `accesskey`, `credential` or `credentials`
///   (`refresh_token`, `x-api-key`, `Proxy-Authorization`, `private_key`,
///   `set-cookie`, ...). Suffix, not substring, and the plural `tokens` is
///   exact only: `token_count`, `tokenizer`, `tokens_used` and `max_tokens`
///   are kept.
/// * Values: maps (any key type, keys stringified), iterables (returned as
///   fixed-length lists) and [Uri]s (stringified, then scrubbed as strings)
///   are traversed recursively, bounded: containers nested 16 levels deep
///   or beyond, and containers past a total budget of 2048 per call (a wide
///   self-referencing structure), are replaced by the string `[truncated]`;
///   each map/iterable keeps at most its first 256 elements (an infinite lazy
///   iterable is cut, the rest is dropped silently).
/// * Strings: JWTs and `sb_secret_...` Supabase secret keys are replaced
///   with `[redacted]` anywhere in the string (JWT scanning is linear-time).
///   The string is then scrubbed per whitespace-delimited token, preserving
///   the original whitespace, so a URL inside an error message is handled
///   while ordinary prose (`did it work? yes it did`) is untouched. Within a
///   token: userinfo is dropped from the first `://` up to the LAST `@`
///   (greedy, so a raw `?`/`/`/`#` in the password cannot leak the tail; an
///   `@` in the path or query over-redacts, `https://host/a@b` becomes
///   `https://b`). The query string and a `key=value` fragment
///   (implicit-flow `#access_token=...`) of a URL-shaped segment are dropped
///   up to the first quote, `<`, `>` or unbalanced `)`/`]`/`}` (kept
///   verbatim from there, so JSON- or bracket-wrapped URLs keep their
///   surroundings; `,` `;` `.` do not end the region because `ids=1,2` is a
///   legal query value, and a raw quote inside a query value ends it early).
///   A plain fragment (`#frag`) and an empty query are kept. A segment is
///   URL-shaped with a scheme of two or more characters, a `/` before the
///   delimiter, or a bare host (`abc.supabase.co?apikey=S`, also the
///   ambiguous `v1.2?x=1`, stripped fail-safe) whose query/fragment contains
///   `=`; `[C]Hello?[G]World`, `a?b`, `e.g?` and `C:\dir\file?.txt` are never
///   mangled.
/// * Never throws: any failure while scrubbing (a throwing iterator, a
///   pathological structure) returns `{'scrub_error': true}` with no data.
///
/// Documented non-goal: email addresses are NOT redacted (call sites must
/// not pass them; `mailto:foo@bar.com?subject=hi` keeps the address).
Map<String, Object?>? scrubPii(Map<String, Object?>? data) {
  if (data == null) return null;
  try {
    return _scrubMap(data, 0, _Budget());
  } catch (_) {
    // Never let a hostile or broken value (throwing iterator, stack
    // exhaustion) escape into the instrumented operation. Return a marker
    // with no data instead of a partial, possibly unscrubbed, result.
    return {'scrub_error': true};
  }
}

const _maxDepth = 16;
const _maxElements = 256;
const _maxNodes = 2048;
const _truncated = '[truncated]';

/// Total container budget of one [scrubPii] call, so a wide self-referencing
/// structure (256 entries pointing back at the map, 16 levels deep) cannot
/// explode combinatorially within the depth and element caps.
class _Budget {
  int remaining = _maxNodes;
}

Map<String, Object?> _scrubMap(
  Map<Object?, Object?> data,
  int depth,
  _Budget budget,
) {
  final result = <String, Object?>{};
  for (final entry in data.entries.take(_maxElements)) {
    final key = entry.key.toString();
    if (_isSensitiveKey(key)) {
      continue;
    }
    result[key] = _scrubValue(entry.value, depth + 1, budget);
  }
  return result;
}

Object? _scrubValue(Object? value, int depth, _Budget budget) {
  if (value is Map || value is Iterable) {
    if (depth >= _maxDepth || --budget.remaining < 0) return _truncated;
    if (value is Map) return _scrubMap(value, depth, budget);
    return (value as Iterable)
        .take(_maxElements)
        .map((element) => _scrubValue(element, depth + 1, budget))
        .toList(growable: false);
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
  return _stripQueryAndFragment(_dropUserInfo(token));
}
