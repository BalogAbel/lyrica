/// Normalized keys (see [_normalizeKey]) dropped by exact match.
///
/// Plurals of a metric-like word (`tokens`, and its `access`/`refresh`/`id`
/// compounds) are exact only, never a suffix: `max_tokens`, `prompt_tokens`
/// and `total_tokens` are ordinary metrics. The singular forms are covered by
/// the `token` suffix. Short, generic names (`otp`, `sig`, `auth`, `nonce`,
/// `signature`, `pin`, `passcode`, `bearer`, ...) are exact only too, so
/// `time_signature`, `author`, `pinned` or `nonces_seen` are kept. Bare
/// `code` (HTTP status codes are ordinary data) and `session_id` /
/// `sessionid` (generic correlation ids, not credentials in this app) are
/// deliberately absent; only the credential-specific `authcode`, `mfacode`,
/// `otpcode`, `verificationcode`, ... forms are dropped.
const _piiExactKeys = {
  'jwts',
  'codeverifier',
  'tokens',
  'accesstokens',
  'refreshtokens',
  'idtokens',
  'tokenhash',
  'otp',
  'totp',
  'emailotp',
  'smsotp',
  'csrf',
  'xsrf',
  'sig',
  'signature',
  'auth',
  'authheader',
  'creds',
  'nonce',
  'pwd',
  'pin',
  'passcode',
  'bearer',
};

/// Normalized keys ending in one of these are dropped (`refresh_token`,
/// `x-api-key`, `client_secret`, `set-cookie`, `id_token`, `Proxy-Authorization`,
/// `private_key`, `aws_access_key`, `db_credentials`, `db_passwd`,
/// `recovery_codes`, ...). A suffix match rather than a substring match on
/// purpose: `token_count`, `tokenizer` and `tokens_used` are ordinary
/// metrics, not credentials.
const _piiKeySuffixes = [
  'token',
  'jwt',
  'secret',
  'secrets',
  'password',
  'passwords',
  'passwd',
  'passphrase',
  'cookie',
  'cookies',
  'apikey',
  'apikeys',
  'authorization',
  'privatekey',
  'privatekeyid',
  'secretkey',
  'accesskey',
  'servicerolekey',
  'supabasekey',
  'credential',
  'credentials',
  'passwordhash',
  'authcode',
  'authorizationcode',
  'mfacode',
  'otpcode',
  'verificationcode',
  'recoverycode',
  'recoverycodes',
];

/// Pagination and cancellation cursors: they end in `token` but are opaque
/// cursors, not credentials, so they are kept.
const _benignTokenKeys = {
  'pagetoken',
  'nextpagetoken',
  'prevpagetoken',
  'previouspagetoken',
  'canceltoken',
  'synctoken',
};

final _keyIgnoredCharsPattern = RegExp(r'[-_.\s]');

/// Lower-cases and strips `-`, `_`, `.` and whitespace, so header-style keys
/// (`Access-Token`, `X-Api-Key`, `api key`, `access.token`) normalize to the
/// same form as this codebase's snake_case keys (`access_token`).
String _normalizeKey(String key) =>
    key.toLowerCase().replaceAll(_keyIgnoredCharsPattern, '');

bool _isSensitiveKey(String key) {
  final normalized = _normalizeKey(key);
  if (_benignTokenKeys.contains(normalized)) return false;
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
  final out = <String>[];
  // Last part index already swallowed by a redaction; -1 when none.
  var coveredUntil = -1;
  for (var index = 0; index < parts.length; index++) {
    final part = parts[index];
    final start = part.indexOf(_jwtPrefix);
    // header needs >= 1 char after `eyJ`, payload >= 1 char, signature part
    // must exist (it may be empty, e.g. unsigned JWTs).
    final isJwtStart =
        start >= 0 &&
        start + _jwtPrefix.length < part.length &&
        index + 2 < parts.length &&
        parts[index + 1].isNotEmpty;
    if (isJwtStart) {
      // Every candidate marks its own three parts, advancing by one part (not
      // three) and merging overlaps: an `eyJ`-containing prefix part
      // (`surveyJson.v1.<JWT>`, `eyJx.y.<JWT>`) must not misalign the scan and
      // leave the real payload and signature behind.
      if (index > coveredUntil) {
        out.add('${part.substring(0, start)}$_redacted');
      }
      coveredUntil = index + 2;
    } else if (index > coveredUntil) {
      out.add(part);
    }
  }
  return out.join('.');
}

/// Credential names whose `KEY=VALUE`, `KEY: VALUE`, `"KEY":"VALUE"` and
/// `'KEY':'VALUE'` text has its value redacted (rule C, see [scrubPii]).
const _credentialTextKeys =
    'refresh_token|access_token|id_token|provider_token|'
    'provider_refresh_token|refreshtoken|accesstoken|idtoken|providertoken|'
    'providerrefreshtoken|token|apikey|api_key|x-api-key|password|passwd|'
    'secret|client_secret|clientsecret';

/// Start of a credential key: not directly after a letter or digit. A
/// negative lookbehind, not `\b`: `\b` does not fire between `_` and a letter,
/// so `my_token=S` and `sb_access_token=S` were missed. `mytoken=S` and
/// `myToken=S` (a letter before) are still not credential keys here.
const _keyStart = r'(?<![A-Za-z0-9])';

/// What ends a credential value: whitespace, a quote, or `& , ; } )`.
const _credentialValue = '''[^\\s"'&,;})]+''';

/// `KEY` + separator kept verbatim (`$1`), value replaced. Linear: the key is
/// a literal alternation behind a one-character lookbehind (no leading
/// wildcard, which would be quadratic), the value a single character-class
/// run.
final _credentialPairPattern = RegExp(
  '''$_keyStart((?:$_credentialTextKeys)["']?\\s*[:=]\\s*["']?)'''
  '$_credentialValue',
  caseSensitive: false,
);

/// `authorization` additionally consumes a `Bearer `/`Basic ` scheme word,
/// which stays visible (`Authorization: Bearer [redacted]`).
final _authorizationPairPattern = RegExp(
  '''$_keyStart(authorization["']?\\s*[:=]\\s*["']?(?:(?:bearer|basic)\\s+)?)'''
  '$_credentialValue',
  caseSensitive: false,
);

String _redactCredentialPairs(String value) => value
    .replaceAllMapped(_authorizationPairPattern, (m) => '${m[1]}$_redacted')
    .replaceAllMapped(_credentialPairPattern, (m) => '${m[1]}$_redacted');

final _whitespacePattern = RegExp(r'\s');

/// Pre-pass for a credential pair whose key and value sit in DIFFERENT
/// whitespace tokens (`x.co?a=1,token: S`, `?APIKEY = S`, `authorization:
/// Bearer S`): the URL rules cut from a `?` to the end of the token, which
/// would delete the key (`token:`) and leave its value (`S`) behind as a bare
/// word. The value is redacted here, only when the matched key + separator
/// part (`$1`) contains whitespace, i.e. the pair really spans tokens. A pair
/// inside one token is left to rule C after the URL rules (see [_scrubText]).
String _redactCrossTokenPairs(String value) => value
    .replaceAllMapped(_authorizationPairPattern, _redactIfSpansWhitespace)
    .replaceAllMapped(_credentialPairPattern, _redactIfSpansWhitespace);

String _redactIfSpansWhitespace(Match m) =>
    m[1]!.contains(_whitespacePattern) ? '${m[1]}$_redacted' : m[0]!;

final _whitespaceDelimitedTokenPattern = RegExp(r'\S+');

/// A bare host (`abc.supabase.co`, `x.co:8080`, and also `v1.2`).
final _hostShapePattern = RegExp(r'^[\w-]+(\.[\w-]+)+(:\d+)?$');

/// URLs handled in one whitespace-free token; the rest of it is dropped.
const _maxUrlsPerToken = 8;

bool _isAlpha(int c) => (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);

/// `[A-Za-z0-9+.-]`, the characters allowed in a URI scheme.
bool _isSchemeChar(int c) =>
    _isAlpha(c) ||
    (c >= 0x30 && c <= 0x39) ||
    c == 0x2B ||
    c == 0x2E ||
    c == 0x2D;

/// Index of the `:` of the first `://` in [s] that is preceded by a URI
/// scheme (a letter, then at least one more scheme character), or -1. A
/// one-character prefix (`a://`, a Windows drive) is not a scheme.
int _schemeUrlColon(String s) {
  var from = 0;
  while (true) {
    final colon = s.indexOf('://', from);
    if (colon < 0) return -1;
    var start = colon;
    while (start > 0 && _isSchemeChar(s.codeUnitAt(start - 1))) {
      start--;
    }
    while (start < colon && !_isAlpha(s.codeUnitAt(start))) {
      start++;
    }
    if (colon - start >= 2) return colon;
    from = colon + 3;
  }
}

/// True when [s] starts with a URI scheme of two or more characters followed
/// by `:` (`mailto:`, `tel:`), so not a Windows drive (`C:\`).
bool _startsWithScheme(String s) {
  var i = 0;
  while (i < s.length && _isSchemeChar(s.codeUnitAt(i))) {
    i++;
  }
  return i >= 2 &&
      i < s.length &&
      s.codeUnitAt(i) == 0x3A &&
      _isAlpha(s.codeUnitAt(0));
}

/// Where the query/fragment of [s] starts: the first `?`, or an earlier `#`
/// whose fragment (everything after it) holds a `=` (`#access_token=...`).
/// A plain fragment (`#frag`) is not cut. [s].length when there is none.
int _queryStart(String s) {
  final question = s.indexOf('?');
  var cut = question < 0 ? s.length : question;
  final hash = s.indexOf('#');
  if (hash >= 0 && hash < cut && s.indexOf('=', hash) >= 0) cut = hash;
  return cut;
}

/// Rule A (see [scrubPii]) for a token whose first scheme URL has its `://`
/// at [colon]. Everything before the scheme is kept verbatim. Linear: each
/// level runs a few `indexOf` passes and there are at most
/// [_maxUrlsPerToken] levels.
String _scrubSchemeUrl(String token, int colon, int count) {
  final head = token.substring(0, colon + 3);
  if (count >= _maxUrlsPerToken) return '$head$_redacted';
  final after = token.substring(colon + 3);
  var delimiter = 0;
  while (delimiter < after.length) {
    final c = after.codeUnitAt(delimiter);
    if (c == 0x2F || c == 0x3F || c == 0x23) break; // / ? #
    delimiter++;
  }
  // An `@` after the first `/ ? #` is either a path/query character or
  // userinfo holding one of those: not told apart, the rest goes.
  if (delimiter < after.length && after.indexOf('@', delimiter) >= 0) {
    return '$head$_redacted';
  }
  final userinfoEnd = delimiter > 0
      ? after.lastIndexOf('@', delimiter - 1)
      : -1;
  final hostAndRest = userinfoEnd < 0
      ? after
      : after.substring(userinfoEnd + 1);
  final kept = hostAndRest.substring(0, _queryStart(hostAndRest));
  final next = _schemeUrlColon(kept);
  return next < 0
      ? '$head$kept'
      : '$head${_scrubSchemeUrl(kept, next, count + 1)}';
}

/// Rule B (see [scrubPii]) for a token without a scheme URL.
String _scrubSchemeless(String token) {
  if (_startsWithScheme(token)) {
    return token.substring(0, _queryStart(token));
  }
  var start = 0;
  while (start < token.length) {
    final c = token.codeUnitAt(start);
    if (c == 0x3F || c == 0x23) break; // ? #
    start++;
  }
  if (start == token.length || token.indexOf('=', start + 1) < 0) return token;
  final head = token.substring(0, start);
  return head.contains('/') || _hostShapePattern.hasMatch(head) ? head : token;
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
///   dropped when equal to one of a small exact set (`jwts`, `tokens`,
///   `accesstokens`, `refreshtokens`, `idtokens`, `codeverifier`,
///   `tokenhash`, `otp`, `totp`, `emailotp`, `smsotp`, `csrf`, `xsrf`, `sig`,
///   `signature`, `auth`, `authheader`, `creds`, `nonce`, `pwd`, `pin`,
///   `passcode`, `bearer`) or when they end in one of `token`, `jwt`,
///   `secret`, `secrets`, `password`, `passwords`, `passwd`, `passphrase`,
///   `cookie`, `cookies`, `apikey`, `apikeys`, `authorization`, `privatekey`,
///   `privatekeyid`, `secretkey`, `accesskey`, `servicerolekey`,
///   `supabasekey`, `credential`, `credentials`, `passwordhash`, `authcode`,
///   `authorizationcode`, `mfacode`, `otpcode`, `verificationcode`,
///   `recoverycode` or `recoverycodes` (`refresh_token`, `x-api-key`,
///   `Proxy-Authorization`, `service_role_key`, `set-cookie`, ...). Suffix,
///   not substring, and short generic names are exact only: `token_count`,
///   `tokenizer`, `tokens_used`, `max_tokens`, `time_signature`, `author`
///   and bare `code` (an HTTP status) are kept. Two exceptions keep an
///   otherwise matching key: a `bool` value is never a secret (`has_password:
///   true`), and opaque pagination/cancellation cursors (`page_token`,
///   `next_page_token`, `prev_page_token`, `previous_page_token`,
///   `cancel_token`, `sync_token`) are allowlisted. Kept keys are themselves
///   run through the string scrub below (a key holding a URL or JWT); keys
///   that collide afterwards overwrite each other, the later entry wins.
/// * Values: maps (any key type, keys stringified) and iterables (returned
///   as fixed-length lists) are traversed recursively, bounded: containers
///   nested 16 levels deep or beyond, and containers past a total budget of
///   2048 per call (a wide self-referencing structure), are replaced by the
///   string `[truncated]`; each map/iterable keeps at most its first 256
///   elements (an infinite lazy iterable is cut, the rest is dropped
///   silently), and all containers together at most 2048 elements per call.
///   `null`, numbers and bools pass through. EVERYTHING else (a [String], a
///   [Uri], an exception, an enum, any object) is scrubbed as its
///   `toString()` -- the SDK's JSON serialization falls back to exactly that,
///   so an object holding a URL or token must not bypass the string scrub. A
///   `toString()` that throws yields `[unprintable]`.
/// * Size caps (strings): only the first 64 KB of a string is scrubbed (an
///   input cut there is first trimmed back to its last whitespace, so a
///   token straddling the cut is never emitted half-redacted) and the RESULT
///   is cut to 8 KB plus the marker `…[truncated]`; an unscrubbed tail is
///   never emitted. A result that already ends in the marker and is at most
///   one marker over the limit (our own earlier output) is not cut again, so
///   the scrub stays idempotent at a surrogate-pair cut. A total budget of 64 KB of key and string characters per
///   call applies; past it strings become `[truncated]` and remaining
///   entries are dropped. This bounds both time (a 10 MB string is
///   processed in ~15 ms) and the encoded size of what reaches Sentry.
/// * Strings: a small, conservative rule set (ADR-036 point 7, "Revision 4",
///   amended by "Revision 5"). It errs towards dropping, never towards
///   guessing. In order:
///   * JWTs and `sb_secret_...` Supabase secret keys are replaced with
///     `[redacted]` anywhere in the string (JWT scanning is linear-time).
///     Every dot-separated part holding `eyJ` marks itself and the two parts
///     after it, overlaps merged, so an `eyJ`-containing dotted prefix
///     (`surveyJson.v1.<JWT>`, `eyJx.y.<JWT>`) cannot misalign the scan and
///     leave the payload and signature behind. A JWT's own payload starts with
///     `eyJ` too, so a dotted word glued after a JWT (`<JWT>.tail`) is
///     redacted with it (accepted over-redaction).
///   * Credential pairs whose key and value sit in DIFFERENT whitespace
///     tokens (`x.co?a=1,token: S`, `?APIKEY = S`) have the value redacted
///     first (rule C's patterns, applied only when the key + separator part
///     contains whitespace): the URL rules below cut a token from its `?` to
///     its end and would delete the key while leaving the value behind.
///   * The string is cut into whitespace-delimited tokens (whitespace is
///     preserved), so ordinary prose (`did it work? yes it did`) is
///     untouched. A token without `?`, `#` and `@` is left alone.
///   * A. A token holding a scheme URL -- the first `://` preceded by a
///     scheme of two or more characters (`https`, `postgres`, not `a://`) --
///     is handled from that URL on; what precedes the scheme is kept
///     verbatim. If an `@` follows the first `/`, `?` or `#` after `://` it
///     is ambiguous (an `@` in a path/query, or userinfo holding one of
///     those) and everything after `://` is replaced by `[redacted]`.
///     Otherwise userinfo (up to the last `@` of the authority) is dropped,
///     then everything from the first `?` -- or from an earlier `#` whose
///     fragment holds a `=` (`#access_token=...`) -- to the END OF THE TOKEN
///     is dropped, closers, wrappers and further URLs included. A plain
///     fragment (`#frag`) with no query is kept. A kept remainder that
///     itself holds a scheme URL is handled the same way, at most 8 URLs per
///     token (the rest is `[redacted]`).
///   * B. Tokens with no scheme URL: a token starting with a scheme of two or
///     more characters and `:` (`mailto:a@b?subject=hi`; not a one-letter
///     Windows drive) is cut at the first `?` (or `#` with a `=`); any other
///     token is cut at its first `?` or `#` when the text before it is
///     host-shaped (`abc.supabase.co`, `x.co:8080`) or contains a `/`, AND
///     the text after it contains a `=` (`example.co/rest?apikey=S`,
///     `/rest?a=1`). B also runs on what A kept. `[C/G]Why?[Am]Because`,
///     `a/b?x`, `[C]Hello?[G]World`, `a?b` and `C:\dir\file?.txt` are left
///     alone.
///   * C. Credential key/value text: the value is replaced with `[redacted]`
///     in `KEY=VALUE`, `KEY: VALUE`, `"KEY":"VALUE"` and `'KEY':'VALUE'` for
///     `refresh_token`, `access_token`, `id_token`, `provider_token`,
///     `provider_refresh_token`, `refreshToken`, `accessToken`, `idToken`,
///     `providerToken`, `providerRefreshToken` (case-insensitive, so
///     `refreshtoken` too), `token`, `apikey` (so `apiKey`), `api_key`,
///     `x-api-key`, `password`, `passwd`, `secret`, `client_secret`,
///     `clientSecret` and `authorization` (`authorization` also consumes a
///     `Bearer `/`Basic ` word). The key must not follow a letter or digit
///     directly (a lookbehind, not `\b`, so `my_token=S`, `sb_access_token=S`
///     and `new_password=S` match; `token_count=3`, `tokenizer:`,
///     `password_reset_flow:` and `secret_santa=2024` do not, the key must be
///     followed directly by the separator). A value runs to whitespace, a
///     quote or one of `& , ; } )`. It runs on the whole string AFTER the URL
///     rules (before, a `token=` inside userinfo could eat its `@`), and the
///     URL rules run once more after it, because redacting a value can move
///     a token's first `?` and change its classification.
///   Accepted trade-offs: text after a URL in the same whitespace-free token
///   (JSON, brackets, quotes) is dropped; an `@` in a path or query
///   over-redacts the URL to `scheme://[redacted]`; look-alikes with a `=`
///   after the `?` are cut (`foo.bar?baz=qux`, `Dr.Who?name=x`, `1.5?x=2`,
///   `[G/B]Love?[C]=joy`, `v1.2?x=1`); `Note:Why?` reads as a URI scheme.
///   Known residuals, not caught because they cannot be told from prose: a
///   bare `?SECRET` without `=`; a schemeless URL after an earlier non-URL
///   `?` in the same token (`why?/p?k=S`) or after ANY non-whitespace prefix
///   (`url=abc.co?k=S`, `{"url":"x.co:8080?k=S"}`, `("abc.co?k=S")`) unless
///   its key is a credential name (rule C); a credential name glued to a
///   preceding letter or digit (`myToken=S`, `authToken=S`, `mytoken=S`),
///   since rule C matches only the names above (with a leading `_`, `-` or
///   space allowed); the words after the first of a quoted credential value
///   (`"password": "a b"` redacts `a`). Exception messages handed to
///   `captureException` never go through this function at all.
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
const _maxEntries = 2048;
const _maxStringInputChars = 64 * 1024;
const _maxStringOutputChars = 8 * 1024;
const _maxTotalStringChars = 64 * 1024;
const _truncated = '[truncated]';
const _truncatedSuffix = '…[truncated]';

/// Total budget of one [scrubPii] call, so a wide self-referencing structure
/// (256 entries pointing back at the map, 16 levels deep) or a pile of large
/// strings cannot explode within the depth, element and per-string caps.
class _Budget {
  /// Containers still allowed.
  int nodes = _maxNodes;

  /// Map entries and list elements still allowed.
  int entries = _maxEntries;

  /// Key and string characters still allowed.
  int chars = _maxTotalStringChars;
}

Map<String, Object?> _scrubMap(
  Map<Object?, Object?> data,
  int depth,
  _Budget budget,
) {
  final result = <String, Object?>{};
  for (final entry in data.entries.take(_maxElements)) {
    if (budget.entries <= 0 || budget.chars <= 0) break;
    budget.entries--;
    final key = entry.key.toString();
    final value = entry.value;
    if (value is! bool && _isSensitiveKey(key)) {
      continue;
    }
    result[_scrubString(key, budget)] = _scrubValue(value, depth + 1, budget);
  }
  return result;
}

Object? _scrubValue(Object? value, int depth, _Budget budget) {
  if (value is Map || value is Iterable) {
    if (depth >= _maxDepth || --budget.nodes < 0) return _truncated;
    if (value is Map) return _scrubMap(value, depth, budget);
    final list = <Object?>[];
    for (final element in (value as Iterable).take(_maxElements)) {
      if (budget.entries <= 0) break;
      budget.entries--;
      list.add(_scrubValue(element, depth + 1, budget));
    }
    return list.toList(growable: false);
  }
  if (value == null || value is num || value is bool) return value;
  // Everything else (String, Uri, exceptions, enums, arbitrary objects) is
  // scrubbed as its `toString()`: the SDK's JSON serialization falls back to
  // exactly that, so an object holding a URL or token must not bypass the
  // string scrub.
  final String text;
  try {
    text = value.toString();
  } catch (_) {
    return '[unprintable]';
  }
  return _scrubString(text, budget);
}

bool _isWhitespaceUnit(int c) =>
    (c >= 0x09 && c <= 0x0D) ||
    c == 0x20 ||
    c == 0xA0 ||
    c == 0x1680 ||
    (c >= 0x2000 && c <= 0x200A) ||
    c == 0x2028 ||
    c == 0x2029 ||
    c == 0x202F ||
    c == 0x205F ||
    c == 0x3000 ||
    c == 0xFEFF;

/// Scrubs [value] within the size caps: at most [_maxStringInputChars] are
/// scrubbed (trimmed back to the last whitespace when cut, so a partial token
/// at the boundary is dropped rather than emitted), and the scrubbed result
/// is cut to [_maxStringOutputChars] (and to what is left of the call's
/// character budget) plus a marker. Order matters: the cut always happens on
/// the already-scrubbed text, never before, and nothing beyond the scrubbed
/// prefix is ever emitted.
String _scrubString(String value, _Budget budget) {
  if (budget.chars <= 0) return _truncated;
  var input = value;
  var cut = false;
  if (input.length > _maxStringInputChars) {
    cut = true;
    var end = _maxStringInputChars;
    if (!_isWhitespaceUnit(input.codeUnitAt(end))) {
      while (end > 0 && !_isWhitespaceUnit(input.codeUnitAt(end - 1))) {
        end--;
      }
      // `end` is now just after the last whitespace (or 0): drop that
      // whitespace as well.
      if (end > 0) end--;
    }
    input = input.substring(0, end);
  }
  var text = _scrubText(input);
  final limit = budget.chars < _maxStringOutputChars
      ? budget.chars
      : _maxStringOutputChars;
  if (text.length > limit &&
      !(text.length <= limit + _truncatedSuffix.length &&
          text.endsWith(_truncatedSuffix))) {
    // (The exception: a result that already ends in the marker and is at most
    // one marker over the limit is our own earlier output, e.g. cut short of
    // the limit at a surrogate pair. Cutting it again would make the scrub
    // non-idempotent.)
    var end = limit;
    // Never split a surrogate pair.
    if (end > 0 && (text.codeUnitAt(end - 1) & 0xFC00) == 0xD800) end--;
    text = '${text.substring(0, end)}$_truncatedSuffix';
  } else if (cut) {
    text = '$text$_truncatedSuffix';
  }
  budget.chars -= text.length;
  return text;
}

String _scrubText(String value) {
  final redacted = _redactJwts(
    value,
  ).replaceAll(_supabaseSecretKeyPattern, _redacted);
  // 1. Credential pairs whose key and value are in different whitespace
  //    tokens, before the URL rules: those cut a token from its `?` to its
  //    end and would delete the key while leaving the value behind.
  // 2. URLs, then credential key/value text. The other way round, a
  //    `token=...` inside a URL's userinfo would be rewritten before the URL
  //    rules see it, and could consume the `@` that marks it as userinfo. So
  //    rule C runs on the whole string only AFTER the URL rules (and the
  //    pre-pass above touches nothing without whitespace between key and
  //    value).
  // 3. The URL rules once more: redacting a value can remove the first `?`
  //    of a token and so change how its remainder is classified; the second
  //    pass makes the whole scrub idempotent.
  return _scrubTokens(
    _redactCredentialPairs(_scrubTokens(_redactCrossTokenPairs(redacted))),
  );
}

String _scrubTokens(String text) => text.replaceAllMapped(
  _whitespaceDelimitedTokenPattern,
  (match) => _scrubToken(match[0]!),
);

String _scrubToken(String token) {
  if (!token.contains('?') && !token.contains('#') && !token.contains('@')) {
    return token;
  }
  final colon = _schemeUrlColon(token);
  // Rule B also runs on what rule A keeps: the text before a scheme URL is
  // kept verbatim by A and may itself be a schemeless URL with a query
  // (`/rest/v1/x?k=S,https://h/y`).
  return _scrubSchemeless(colon < 0 ? token : _scrubSchemeUrl(token, colon, 0));
}
