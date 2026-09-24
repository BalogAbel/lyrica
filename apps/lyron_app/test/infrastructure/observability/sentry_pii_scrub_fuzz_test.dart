import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/infrastructure/observability/sentry_pii_scrub.dart';

/// Seeded property fuzzer for the PII scrub (ADR-036 point 7, "Revision 4").
///
/// Four rounds of review each found a new leak class in a heuristic URL state
/// machine that example tests could not cover. The scrub is now a small
/// conservative rule set, and this test is its safety net: it generates
/// combinations of URL parts, wrappers and separators that nobody would write
/// by hand and asserts four properties:
///
/// 1. a secret planted in the userinfo, query or `key=value` fragment of a
///    scheme URL, or in credential key/value text, never survives;
/// 2. a benign corpus (prose, ChordPro, lyrics, paths, times, ...) comes back
///    UNCHANGED, alone and in random space-joined combinations;
/// 3. the output is idempotent (`scrub(scrub(x)) == scrub(x)`);
/// 4. it never throws and never yields a `scrub_error`.
///
/// The PRNG is a fixed-seed xorshift32, so a run is fully deterministic and
/// independent of the Dart `Random` implementation. Failures print the minimal
/// (shortest) offending inputs. The case count is 100 000 by default (about
/// 1 s); run a much larger sweep locally with
/// `flutter test test/infrastructure/observability/sentry_pii_scrub_fuzz_test.dart
///  --dart-define=SCRUB_FUZZ_CASES=2000000` (opt-in, ~15 s).
const _cases = int.fromEnvironment('SCRUB_FUZZ_CASES', defaultValue: 100000);
const _seed = 0x5C4B7E11;
const _secret = 'SECRETVALUE';

class _Rng {
  _Rng(this._state);
  int _state;

  int nextInt(int max) {
    _state ^= (_state << 13) & 0xFFFFFFFF;
    _state ^= _state >> 17;
    _state ^= (_state << 5) & 0xFFFFFFFF;
    return _state % max;
  }

  T pick<T>(List<T> items) => items[nextInt(items.length)];

  bool chance(int percent) => nextInt(100) < percent;
}

String _scrub(String input) => scrubPii({'v': input})!['v'] as String;

const _schemes = ['https', 'http', 'ftp', 'postgres', 'lyron'];

// Userinfo variants that hold the secret before the terminating `@`.
List<String> _secretUserinfos() => [
  'u:$_secret',
  _secret,
  'u:p@$_secret',
  'u:$_secret@x',
  'u:p?$_secret',
  'u:p#$_secret',
  'u:p/$_secret',
  'u:p%40$_secret',
  'a@b:$_secret',
  'u:p?x=1&k=$_secret',
  'u:p/x?y#$_secret',
  '$_secret:u',
  'u:token=x&$_secret',
  'token=x,$_secret',
  'u:password=1;$_secret',
];

const _hosts = [
  'example.com',
  'localhost',
  'h',
  '[::1]',
  'db.host:5432',
  'bücher.de',
  '10.0.0.1:8080',
  'x.supabase.co',
];

const _paths = [
  '',
  '/',
  '/a/b',
  '/rest/v1/songs',
  '/a=b',
  '/x:y',
  '/it\'s',
  '/a%20b.pdf',
];

// Paths holding a raw `@`; they must not stop later secrets from being cut.
const _atPaths = ['/a@b', '/u/a@b,c', '/files/me@x.com+1.png'];

List<String> _secretQueries() => [
  '?k=$_secret',
  '?$_secret',
  '?a=1&k=$_secret',
  '?k=$_secret&e=a@b.c',
  '?e=a@b.c&k=$_secret',
  "?q=Don't&t=$_secret",
  '?f(a)=1&t=$_secret',
  '?a="x"&t=$_secret',
  '?a=[1,2]&t=$_secret',
  '?a=%3F&t=$_secret',
  '?next=https://app/x&t=$_secret',
  '?a=1,2;3&t=$_secret',
  '?a=<x>&t=$_secret',
  '?a=)&t=$_secret',
];

const _plainQueries = ['', '?a=1', '?a=1&b=2', '?', '?x', '?a=1,2'];

List<String> _secretFragments() => [
  '#access_token=$_secret',
  '#a=b&access_token=$_secret',
  '#refresh_token=$_secret&type=x',
  '#k=$_secret',
];

const _plainFragments = ['', '#frag', '#a/b'];

const _wrappers = [
  ['', ''],
  ['"', '"'],
  ["'", "'"],
  ['(', ')'],
  ['<', '>'],
  ['[', ']'],
  ['{', '}'],
  ['{"url":"', '","code":401}'],
  ['uri=', ''],
  ['why?', ''],
  ['`', ''],
  ['!', ''],
  ['(', ')&t=x)'],
  ['[', ']b&t=x]'],
  ['<', '>&t=x>'],
];

// A schemeless URL-shaped prefix holding the secret, in front of a scheme URL
// in the same token. Its `?`/`#` must be the FIRST one of the token: a
// schemeless URL after an earlier non-URL `?` (`why?/p?k=S,...`) is a
// documented residual, asserted in sentry_pii_scrub_test.dart.
const _secretPrefixes = [
  'x.co?k=$_secret,',
  '/rest/v1/x?a=$_secret;',
  'a/b#k=$_secret,',
  'x.co:8080#$_secret=1=',
];

const _separators = [',', ';', '=', ',,', '=,'];

enum _Plant { userinfo, query, fragment }

String _url(_Rng rng, {_Plant? plant}) {
  final scheme = rng.pick(_schemes);
  final userinfo = plant == _Plant.userinfo
      ? '${rng.pick(_secretUserinfos())}@'
      : rng.chance(20)
      ? 'u:p@'
      : '';
  final host = rng.pick(_hosts);
  final path = rng.chance(15) ? rng.pick(_atPaths) : rng.pick(_paths);
  final query = plant == _Plant.query
      ? rng.pick(_secretQueries())
      : rng.pick(_plainQueries);
  final fragment = plant == _Plant.fragment
      ? rng.pick(_secretFragments())
      : rng.pick(_plainFragments);
  // A secret fragment after a query is the common shape; also try it alone.
  final tailQuery = plant == _Plant.fragment && rng.chance(50)
      ? rng.pick(_plainQueries)
      : query;
  return '$scheme://$userinfo$host$path$tailQuery$fragment';
}

/// One whitespace-free token holding one to three URLs (one carries the
/// planted secret), wrapped and joined with URL-ish separators.
String _secretToken(_Rng rng) {
  final plant = rng.pick(_Plant.values);
  final urls = 1 + rng.nextInt(3);
  final planted = rng.nextInt(urls);
  final out = StringBuffer();
  if (rng.chance(15)) out.write(rng.pick(_secretPrefixes));
  for (var i = 0; i < urls; i++) {
    if (i > 0) out.write(rng.pick(_separators));
    final wrapper = rng.pick(_wrappers);
    out
      ..write(wrapper[0])
      ..write(_url(rng, plant: i == planted ? plant : null))
      ..write(wrapper[1]);
  }
  return out.toString();
}

const _prose = [
  'the',
  'sync',
  'failed',
  'while',
  'refreshing',
  'error:',
  'ClientException',
  'with',
  'message',
];

String _withProse(_Rng rng, String token) {
  final before = List.generate(
    rng.nextInt(3),
    (_) => rng.pick(_prose),
  ).join(rng.pick([' ', '  ', '\t', '\n']));
  final after = List.generate(
    rng.nextInt(3),
    (_) => rng.pick(_prose),
  ).join(' ');
  return [
    if (before.isNotEmpty) before,
    token,
    if (after.isNotEmpty) after,
  ].join(rng.pick([' ', '  ', '\n']));
}

/// Credential key/value text (rule C): `KEY=VALUE`, `KEY: VALUE`, JSON.
String _secretPair(_Rng rng) {
  const keys = [
    'refresh_token',
    'access_token',
    'id_token',
    'provider_token',
    'provider_refresh_token',
    'token',
    'apikey',
    'api_key',
    'x-api-key',
    'password',
    'passwd',
    'secret',
    'client_secret',
    'authorization',
    'Authorization',
    'TOKEN',
  ];
  final key = rng.pick(keys);
  final value = rng.pick([
    _secret,
    'abcdEFGHijkl$_secret',
    '$_secret.tail',
    '${_secret}_x-y',
  ]);
  final pair = rng.pick([
    '$key=$value',
    '$key: $value',
    '$key:$value',
    '"$key":"$value"',
    "'$key':'$value'",
    '{"$key": "$value", "ok": 1}',
    '$key=$value&next=1',
    '$key=$value;',
    '($key=$value)',
  ]);
  return _withProse(rng, pair);
}

// Individually unchanged by the scrub. `foo.bar?baz=qux` and look-alikes are
// deliberately NOT here: they are documented benign mangling.
const _benign = [
  'did it work? yes it did',
  'Why?',
  'What? Really? Yes.',
  '[C/G]Why?[Am]Because',
  '[C]Hello?[G]World',
  '[D/F#]Why?[G]x',
  '{title: Amazing Grace}',
  '{comment: Chorus?}',
  'Amazing grace, how sweet the sound',
  'Am/G',
  'C#m7',
  'F#m/A',
  'a@b.com',
  'mail me at user@example.com please',
  'user.name+tag@example.co.uk',
  '10:30',
  '12:45:30',
  'v1.2',
  '1.2.3',
  'version 2.0-beta',
  r'C:\x\y?.txt',
  r'C:\Users\john\file?.txt',
  '/usr/bin/x?y',
  'a/b?x',
  'and/or?',
  '1/2?',
  '3/4 time?',
  'a?b',
  'a?b,c?d',
  'e.g?',
  'foo.bar?',
  '#hashtag',
  'song #12',
  'C#',
  '100%',
  'x=1',
  'a=b, c=d',
  'why?what?how',
  '?SECRET-bare-is-a-documented-residual',
  'token_count=3',
  'max_tokens: 5',
  'tokens=3',
  'the token was empty',
];

String _benignText(_Rng rng) {
  final count = 1 + rng.nextInt(4);
  return List.generate(
    count,
    (_) => rng.pick(_benign),
  ).join(rng.pick([' ', '  ', '\n', '\t']));
}

const _garbageAlphabet =
    ':/?#@=&,;"\'()[]{}<> a.-%_bcdefghijklmnopqrstuvwxyz0123456789'
    'ABCTS\n\t+~!`\\|*^\$'
    'é😀';

String _garbage(_Rng rng) {
  final length = rng.nextInt(48);
  final out = StringBuffer();
  for (var i = 0; i < length; i++) {
    out.write(_garbageAlphabet[rng.nextInt(_garbageAlphabet.length)]);
  }
  // Salt with structured fragments so scheme URLs and credential pairs
  // actually show up (a credential value swallowing a `?` changes how the
  // rest of its token is classified: that is what the idempotency property
  // watches).
  if (rng.chance(40)) {
    out
      ..write(
        rng.pick([
          'https://',
          'a://',
          'x.co?',
          '/p?',
          'mailto:',
          '://',
          'token=',
          'password: ',
          '"secret":"',
        ]),
      )
      ..write(out.length % 2 == 0 ? '@' : 'h')
      ..write(
        rng.pick(['?k=v', '#a=b', '', '?', '@u', '/', '?token=x', '/x?']),
      );
  }
  return out.toString();
}

class _Failures {
  final byProperty = <String, List<String>>{};

  void add(String property, String input, String detail) {
    (byProperty[property] ??= []).add('$input  ->  $detail');
  }

  /// The [count] shortest offending inputs of every property.
  String report({int count = 5}) {
    final buffer = StringBuffer();
    for (final entry in byProperty.entries) {
      final sorted = [...entry.value]
        ..sort((a, b) => a.length.compareTo(b.length));
      buffer.writeln('${entry.key}: ${entry.value.length} failure(s)');
      for (final line in sorted.take(count)) {
        buffer.writeln(
          '    ${line.replaceAll('\n', r'\n').replaceAll('\t', r'\t')}',
        );
      }
    }
    return buffer.toString();
  }
}

void main() {
  test('seeded property fuzz: $_cases cases, four properties', () {
    final rng = _Rng(_seed);
    final failures = _Failures();

    void checkNeverLeaks(String property, String input) {
      final String output;
      try {
        final result = scrubPii({'v': input});
        if (result == null || result.containsKey('scrub_error')) {
          failures.add('never-throws', input, 'scrub_error');
          return;
        }
        output = result['v'] as String;
      } catch (error) {
        failures.add('never-throws', input, 'threw $error');
        return;
      }
      if (output.contains(_secret)) {
        failures.add(property, input, output);
      }
      final again = _scrub(output);
      if (again != output) {
        failures.add('idempotent', input, '$output  =>  $again');
      }
    }

    for (var i = 0; i < _cases; i++) {
      switch (i % 5) {
        case 0:
        case 1:
          checkNeverLeaks('secret-in-url', _secretToken(rng));
        case 2:
          checkNeverLeaks(
            'secret-in-url-in-prose',
            _withProse(rng, _secretToken(rng)),
          );
        case 3:
          checkNeverLeaks('secret-in-pair', _secretPair(rng));
        case 4:
          final input = i % 10 == 4 ? _benignText(rng) : _garbage(rng);
          final result = scrubPii({'v': input});
          if (result == null || result.containsKey('scrub_error')) {
            failures.add('never-throws', input, 'scrub_error');
            break;
          }
          final output = result['v'] as String;
          if (i % 10 == 4 && output != input) {
            failures.add('benign-unchanged', input, output);
          }
          final again = _scrub(output);
          if (again != output) {
            failures.add('idempotent', input, '$output  =>  $again');
          }
      }
    }

    expect(failures.byProperty, isEmpty, reason: '\n${failures.report()}');
  });

  test('every benign corpus entry is returned unchanged on its own', () {
    for (final input in _benign) {
      expect(_scrub(input), input, reason: input);
    }
  });

  test('documented benign look-alike mangling stays exactly this', () {
    expect(
      {
        for (final input in [
          'foo.bar?baz=qux',
          'Dr.Who?name=x',
          '1.5?x=2',
          '[G/B]Love?[C]=joy',
          'v1.2?x=1',
        ])
          input: _scrub(input),
      },
      {
        'foo.bar?baz=qux': 'foo.bar',
        'Dr.Who?name=x': 'Dr.Who',
        '1.5?x=2': '1.5',
        '[G/B]Love?[C]=joy': '[G/B]Love',
        'v1.2?x=1': 'v1.2',
      },
    );
  });

  test('the generator really produces the shapes the properties rely on', () {
    // Guard against a generator drifting into producing only trivial input:
    // every plant kind must occur, and some cases must hold an `@` after the
    // first delimiter, a wrapper closer, and several URLs.
    final rng = _Rng(_seed);
    final tokens = List.generate(2000, (_) => _secretToken(rng));

    expect(tokens.every((t) => t.contains(_secret)), isTrue);
    expect(tokens.any((t) => t.contains('@$_secret')), isTrue);
    expect(tokens.any((t) => t.contains('?k=$_secret')), isTrue);
    expect(tokens.any((t) => t.contains('#access_token=$_secret')), isTrue);
    expect(tokens.any((t) => '://'.allMatches(t).length >= 3), isTrue);
    expect(tokens.any((t) => t.startsWith('{"url":"')), isTrue);
  });
}
