/// Normalized keys (see [_normalizeKey]) dropped by exact match.
///
/// Plurals of a metric-like word (`tokens`, and its `access`/`refresh`/`id`
/// compounds) are exact only, never a suffix: `max_tokens`, `prompt_tokens`
/// and `total_tokens` are ordinary metrics. The singular forms are covered by
/// the `token` suffix. Short, generic names (`otp`, `sig`, `auth`, `nonce`,
/// `signature`, ...) are exact only too, so `time_signature`, `author` or
/// `nonces_seen` are kept; bare `code` is deliberately absent (HTTP status
/// codes are ordinary data), only the credential-specific `authcode`,
/// `mfacode`, ... forms are dropped.
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
const _at = 0x40;
const _slash = 0x2F;
const _colon = 0x3A;
const _equals = 0x3D;
const _comma = 0x2C;
const _semicolon = 0x3B;

bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

bool _isAlpha(int c) => (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);

/// `[A-Za-z0-9+.-]`, the characters allowed after the first letter of a URI
/// scheme.
bool _isSchemeChar(int c) =>
    _isAlpha(c) || _isDigit(c) || c == 0x2B || c == 0x2E || c == 0x2D;

/// Characters a host (optionally with `:port` or an IPv6 literal) is made of.
/// Deliberately excludes `& = , ; @` and quotes, so text such as
/// `b.c&token=S` (the tail of an `@` inside a query) is not host-shaped.
bool _isHostChar(int c) =>
    _isAlpha(c) ||
    _isDigit(c) ||
    c == 0x2E || // .
    c == 0x2D || // -
    c == 0x5F || // _
    c == 0x7E || // ~
    c == 0x25 || // %
    c == _colon ||
    c == _openBracket ||
    c == _closeBracket;

bool _isUrlTerminator(int c) =>
    c == _slash ||
    c == _question ||
    c == _hash ||
    c == _quote ||
    c == _apostrophe ||
    c == _lessThan ||
    c == _greaterThan;

/// True when `[from, to)` up to the first URL terminator is empty or made of
/// host characters only (see [_isHostChar]).
bool _isHostShapedAuthority(String token, int from, int to) {
  for (var i = from; i < to; i++) {
    final c = token.codeUnitAt(i);
    if (_isUrlTerminator(c)) return true;
    if (!_isHostChar(c)) return false;
  }
  return true;
}

/// True when the authority of `[from, to)` (up to its first `/`) is a
/// plausible `host[:port]` (numeric port): a non-empty run of host
/// characters with at most digits after the first `:`, or an empty one that
/// is followed by a `/` (`file:///x`).
bool _isPlainHostAuthority(String token, int from, int to) {
  var end = from;
  var colon = -1;
  while (end < to && token.codeUnitAt(end) != _slash) {
    final c = token.codeUnitAt(end);
    if (!_isHostChar(c)) return false;
    if (c == _colon && colon < 0) {
      colon = end;
    } else if (colon >= 0 && !_isDigit(c)) {
      return false;
    }
    end++;
  }
  if (end == from) return end < to;
  return true;
}

/// Where the userinfo of the URL whose host starts at [hostStart] ends, as
/// the index of its terminating `@`; `-1` when there is no userinfo to drop
/// and `-2` when the URL must be cut to its scheme. See [_dropUserInfo].
int _userInfoEnd(String token, int hostStart, int regionEnd) {
  var at = -1;
  for (var i = regionEnd - 1; i >= hostStart; i--) {
    if (token.codeUnitAt(i) == _at) {
      at = i;
      break;
    }
  }
  if (at < 0) return -1;
  var delimiter = -1;
  for (var i = hostStart; i < at; i++) {
    final c = token.codeUnitAt(i);
    if (c == _question || c == _hash) {
      delimiter = i;
      break;
    }
  }
  var cut = at;
  if (delimiter >= 0) {
    // The query/fragment starts before the last `@`. Either that `@` is
    // query content (`?email=a@b.c`) or the userinfo itself holds a raw
    // `?`/`#` (`u:p?ss@host`).
    var before = -1;
    for (var i = delimiter - 1; i >= hostStart; i--) {
      if (token.codeUnitAt(i) == _at) {
        before = i;
        break;
      }
    }
    if (before >= 0) {
      cut = before; // a real userinfo ended before the query
    } else if (_isPlainHostAuthority(token, hostStart, delimiter)) {
      return -1; // host[:port] + query; the `@` is query content
    }
  }
  return _isHostShapedAuthority(token, cut + 1, regionEnd) ? cut : -2;
}

/// Drops `user:password@` from every `://` URL of the token.
///
/// A URL's region runs from its `://` to the next `://` (or the token end).
/// Within a region the userinfo ends at the LAST `@` that precedes the first
/// `?`/`#`, so a raw `/` in the password (`https://u:p/ss@h/x`) or an `@` in
/// the password (`https://u:p@ss@h/x`) cannot leak the tail. When the only
/// `@`s come after the first `?`/`#`:
///
/// * the text before it is a plain `host[:port]` (`https://h/p?email=a@b.c`)
///   => the `@` is query content, nothing is dropped here and the query
///   strip removes it (`https://h/p`);
/// * anything else (`https://u:p?ss@host/x`) => the `?`/`#` is part of the
///   userinfo, which is dropped up to the last `@`.
///
/// If what remains after a drop does not start with a host-shaped authority
/// (`b.c&token=S`), the whole region is cut to `scheme://` (fail-safe).
///
/// Trade-offs (deliberate): an `@` in a path before any `?`
/// (`https://host/a@b`) over-redacts to `https://b`; a userinfo that is a
/// single host-shaped word holding a raw `?`/`#` and no `:`
/// (`https://secret?x@host`) is read as host + query, so that word is kept
/// (a real password after a `:` never is). A token without `://`
/// (`mailto:a@b`) keeps its `@`. Manual scans, not a backtracking regex, so
/// hostile input stays linear.
String _dropUserInfo(String token) {
  var scheme = token.indexOf('://');
  if (scheme < 0) return token;
  final out = StringBuffer();
  var copyFrom = 0;
  while (scheme >= 0) {
    final hostStart = scheme + 3;
    final next = token.indexOf('://', hostStart);
    final regionEnd = next < 0 ? token.length : next;
    final end = _userInfoEnd(token, hostStart, regionEnd);
    if (end != -1) {
      out.write(token.substring(copyFrom, hostStart));
      copyFrom = end == -2 ? regionEnd : end + 1;
    }
    scheme = next;
  }
  if (copyFrom == 0) return token;
  out.write(token.substring(copyFrom));
  return out.toString();
}

/// The character that closes a URL opened by [opener], or -1 when the URL is
/// not wrapped.
int _closerFor(int opener) {
  switch (opener) {
    case _quote:
      return _quote;
    case _apostrophe:
      return _apostrophe;
    case _lessThan:
      return _greaterThan;
    case _openParen:
      return _closeParen;
    case _openBracket:
      return _closeBracket;
    case _openBrace:
      return _closeBrace;
    default:
      return -1;
  }
}

/// End (exclusive) of the query/fragment region that starts at [from].
///
/// [opener] is the character immediately before the URL (`"`, `'`, `<`, `(`,
/// `[` or `{`, or -1). A wrapped URL ends at the matching closer (for
/// brackets, the first UNBALANCED one, so `?f(a)=1` stays inside); an
/// unwrapped URL runs to the end of the token, so a quote, angle bracket or
/// unbalanced closer INSIDE a query value (`?title=eq.Don't&apikey=S`,
/// `?k=a)b`) cannot end it early and leak the rest. For a query
/// ([stopAtHash]) a `#` always ends the region (the fragment is handled on
/// its own). `,` `;` and `.` never end it: they are legal in query values.
int _regionEnd(
  String token,
  int from, {
  required bool stopAtHash,
  required int opener,
}) {
  final closer = _closerFor(opener);
  final nests =
      opener == _openParen || opener == _openBracket || opener == _openBrace;
  var depth = 0;
  for (var i = from; i < token.length; i++) {
    final c = token.codeUnitAt(i);
    if (c == _hash && stopAtHash) return i;
    if (closer < 0) continue;
    if (c == closer) {
      if (depth == 0) return i;
      depth--;
    } else if (nests && c == opener) {
      depth++;
    }
  }
  return token.length;
}

bool _regionHasEquals(String token, int from, int to) {
  for (var i = from; i < to; i++) {
    if (token.codeUnitAt(i) == _equals) return true;
  }
  return false;
}

/// True when a URI scheme (a letter, then at least one of `[A-Za-z0-9+.-]`,
/// then `:`) starts at [pos]; with [needSlashes] it must be followed by `//`.
/// The two-character minimum keeps a Windows drive letter (`C:\`) from
/// counting. Linear: it only walks scheme characters, which never include
/// the boundary characters the caller advances over.
bool _schemeAt(String token, int pos, {required bool needSlashes}) {
  if (pos >= token.length || !_isAlpha(token.codeUnitAt(pos))) return false;
  var i = pos + 1;
  while (i < token.length && _isSchemeChar(token.codeUnitAt(i))) {
    i++;
  }
  if (i - pos < 2 || i >= token.length || token.codeUnitAt(i) != _colon) {
    return false;
  }
  return !needSlashes ||
      (i + 2 < token.length &&
          token.codeUnitAt(i + 1) == _slash &&
          token.codeUnitAt(i + 2) == _slash);
}

/// Drops the query string and any `key=value` fragment of every URL-shaped
/// part of [token] in a single linear pass, keeping everything after the
/// region verbatim (see [_regionEnd]).
///
/// Each `?`/`#` is classified on its own, from state tracked while scanning
/// (so a URL that follows a non-URL `?` in the same token, `why?https://h/x?token=S`,
/// is still stripped):
///
/// * scheme URL: a scheme of two or more characters (`https:`, `mailto:`)
///   starts the token, follows one of `, ; = ( [ { " ' < >`, or (then only
///   as `scheme://`) follows a `?`/`#`, and no quote, `<` or `>` came in
///   between. A non-empty query is stripped;
/// * slash URL: a `/` was seen since the last quote/`<`/`>`
///   (`example.co/rest/v1/songs?apikey=S`, `/rest?a=1`, `rest/v1/x?a=1`);
/// * bare host: the text since the last separator is a host
///   (`abc.supabase.co?apikey=S`, also the ambiguous `v1.2?x=1`).
///
/// Slash URLs and bare hosts are only stripped when the query/fragment
/// contains `=` (key=value shape), so ChordPro and prose such as
/// `[C/G]Why?[Am]Because`, `a/b?x`, `[C]Hello?[G]World`, `a?b`, `e.g?` and
/// `C:\dir\file?.txt` are never mangled. A fragment is only stripped when it
/// contains `=` (implicit-flow `#access_token=...`); a plain fragment
/// (`#frag`) and an empty query (`?` alone) are kept.
String _stripQueryAndFragment(String token) {
  final length = token.length;
  final out = StringBuffer();
  var copyFrom = 0;
  var candidateStart = 0; // after the last `, ; = ( [ { " ' < >`
  var delimiterInCandidate = false;
  var schemeStart = -1;
  var slashSeen = false;
  // Slash/host-shaped `?` regions without any `=` need no re-scan for later
  // `?` inside the same region (keeps hostile `x.co????...` linear).
  var noEqualsUntil = 0;
  if (_schemeAt(token, 0, needSlashes: false)) schemeStart = 0;
  var i = 0;
  while (i < length) {
    final c = token.codeUnitAt(i);
    if (c == _quote ||
        c == _apostrophe ||
        c == _lessThan ||
        c == _greaterThan) {
      schemeStart = -1;
      slashSeen = false;
      delimiterInCandidate = false;
      candidateStart = i + 1;
      if (_schemeAt(token, i + 1, needSlashes: false)) schemeStart = i + 1;
      i++;
      continue;
    }
    if (c == _openParen ||
        c == _openBracket ||
        c == _openBrace ||
        c == _equals ||
        c == _comma ||
        c == _semicolon) {
      candidateStart = i + 1;
      delimiterInCandidate = false;
      if (schemeStart < 0 && _schemeAt(token, i + 1, needSlashes: false)) {
        schemeStart = i + 1;
      }
      i++;
      continue;
    }
    if (c == _slash) {
      slashSeen = true;
      i++;
      continue;
    }
    if (c != _question && c != _hash) {
      i++;
      continue;
    }

    final isQuery = c == _question;
    final firstInCandidate = !delimiterInCandidate;
    delimiterInCandidate = true;
    final schemeUrl = schemeStart >= 0;
    final shaped =
        schemeUrl ||
        slashSeen ||
        (firstInCandidate &&
            _hostShapePattern.hasMatch(token.substring(candidateStart, i)));
    if (!shaped || (isQuery && i < noEqualsUntil)) {
      if (schemeStart < 0 && _schemeAt(token, i + 1, needSlashes: true)) {
        schemeStart = i + 1;
      }
      i++;
      continue;
    }

    final startPos = schemeUrl ? schemeStart : candidateStart;
    final opener = startPos > 0 ? token.codeUnitAt(startPos - 1) : -1;
    final end = _regionEnd(token, i + 1, stopAtHash: isQuery, opener: opener);
    final nonEmpty = end > i + 1;
    final hasEquals = _regionHasEquals(token, i + 1, end);
    final strip = isQuery ? nonEmpty && (schemeUrl || hasEquals) : hasEquals;
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
///   dropped when equal to one of a small exact set (`jwts`, `tokens`,
///   `accesstokens`, `refreshtokens`, `idtokens`, `codeverifier`,
///   `tokenhash`, `otp`, `totp`, `csrf`, `xsrf`, `sig`, `signature`, `auth`,
///   `authheader`, `creds`, `nonce`, `pwd`, ...) or when they end in `token`,
///   `jwt`, `secret(s)`, `password(s)`, `passwd`, `passphrase`,
///   `cookie(s)`, `apikey(s)`, `authorization`, `privatekey(id)`,
///   `secretkey`, `accesskey`, `servicerolekey`, `supabasekey`,
///   `credential(s)`, `passwordhash`, `authcode`, `authorizationcode`,
///   `mfacode` or `recoverycode(s)` (`refresh_token`, `x-api-key`,
///   `Proxy-Authorization`, `service_role_key`, `set-cookie`, ...). Suffix,
///   not substring, and short generic names are exact only: `token_count`,
///   `tokenizer`, `tokens_used`, `max_tokens`, `time_signature`, `author`
///   and bare `code` (an HTTP status) are kept. Two exceptions keep an
///   otherwise matching key: a `bool` value is never a secret (`has_password:
///   true`), and opaque pagination/cancellation cursors (`page_token`,
///   `next_page_token`, `prev_page_token`, `cancel_token`, `sync_token`) are
///   allowlisted. Kept keys are themselves run through the string scrub
///   below (a key holding a URL or JWT); keys that collide afterwards
///   overwrite each other, the later entry wins.
/// * Values: maps (any key type, keys stringified), iterables (returned as
///   fixed-length lists) and [Uri]s (stringified, then scrubbed as strings)
///   are traversed recursively, bounded: containers nested 16 levels deep
///   or beyond, and containers past a total budget of 2048 per call (a wide
///   self-referencing structure), are replaced by the string `[truncated]`;
///   each map/iterable keeps at most its first 256 elements (an infinite lazy
///   iterable is cut, the rest is dropped silently), and all containers
///   together at most 2048 elements per call.
/// * Size caps (strings): only the first 64 KB of a string is scrubbed (an
///   input cut there is first trimmed back to its last whitespace, so a
///   token straddling the cut is never emitted half-redacted) and the RESULT
///   is cut to 8 KB plus the marker `…[truncated]`; an unscrubbed tail is
///   never emitted. A total budget of 64 KB of key and string characters per
///   call applies; past it strings become `[truncated]` and remaining
///   entries are dropped. This bounds both time (a 10 MB string is
///   processed in ~15 ms) and the encoded size of what reaches Sentry.
/// * Strings: JWTs and `sb_secret_...` Supabase secret keys are replaced
///   with `[redacted]` anywhere in the string (JWT scanning is linear-time).
///   The string is then scrubbed per whitespace-delimited token, preserving
///   the original whitespace, so a URL inside an error message is handled
///   while ordinary prose (`did it work? yes it did`) is untouched. Within a
///   token, for each `://` URL: userinfo is dropped up to the last `@` that
///   precedes the first `?`/`#`; when the only `@`s come after it, the `@`
///   is read as query content (`https://h/p?email=a@b.c` becomes
///   `https://h/p`) unless the text before the `?`/`#` is not a plain
///   `host[:port]` (`https://u:p?ss@host/x`), in which case it is userinfo.
///   Trade-offs: an `@` in a path (`https://host/a@b`) over-redacts to
///   `https://b`; a single host-shaped word holding a raw `?`/`#` and no `:`
///   before the `@` is read as host + query. The query string and a
///   `key=value` fragment (implicit-flow `#access_token=...`) of a URL-shaped
///   part are then dropped: for a wrapped URL (`"`, `'`, `<`, `(`, `[` or `{`
///   immediately before it) up to its matching closer (kept verbatim from
///   there, so JSON- or bracket-wrapped URLs keep their surroundings), for an
///   unwrapped one to the end of the token, so a quote or closer inside a
///   query value cannot end it early; `,` `;` `.` never end a region. The
///   only remaining early end is a quote that is BOTH the wrapper and part of
///   a query value (`'https://h/x?q=Don't&t=S'`). A plain fragment (`#frag`)
///   and an empty query are kept. Each `?`/`#` is classified on its own
///   (`why?https://h/x?token=S` strips the URL). A part is URL-shaped with a
///   scheme of two or more characters, or -- only when its query/fragment
///   contains `=` -- a `/` (`example.co/rest?apikey=S`, `rest/v1/x?a=1`) or a
///   bare host (`abc.supabase.co?apikey=S`, also the ambiguous `v1.2?x=1`);
///   `[C/G]Why?[Am]Because`, `a/b?x`, `[C]Hello?[G]World`, `a?b`, `e.g?` and
///   `C:\dir\file?.txt` are never mangled.
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
  if (value is Uri) {
    return _scrubString(value.toString(), budget);
  }
  if (value is String) {
    return _scrubString(value, budget);
  }
  return value;
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
  if (text.length > limit) {
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
