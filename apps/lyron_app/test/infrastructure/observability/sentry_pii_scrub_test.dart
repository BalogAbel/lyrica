import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/infrastructure/observability/sentry_pii_scrub.dart';

void main() {
  test('drops denylisted keys case-insensitively', () {
    final result = scrubPii({
      'Authorization': 'Bearer xyz',
      'apikey': 'k',
      'access_token': 't',
      'refresh_token': 'r',
      'token': 't2',
      'safe': 'kept',
      // ChordPro content and lyrics are deliberately NOT denylisted --
      // per explicit product direction they are not sensitive and may
      // aid debugging. Confirmed by the next test.
    });

    expect(result, {'safe': 'kept'});
  });

  test(
    'does not scrub ChordPro content or lyrics -- not sensitive by product direction',
    () {
      final result = scrubPii({
        'chordpro_source': '{title: Amazing Grace}\n[G]Amazing [C]grace',
        'lyrics': 'Amazing grace, how sweet the sound',
      });

      expect(result, {
        'chordpro_source': '{title: Amazing Grace}\n[G]Amazing [C]grace',
        'lyrics': 'Amazing grace, how sweet the sound',
      });
    },
  );

  test('recurses into nested maps and lists', () {
    final result = scrubPii({
      'outer': {
        'authorization': 'Bearer xyz',
        'list': [
          {'token': 't'},
          {'safe': 'kept'},
        ],
      },
    });

    expect(result, {
      'outer': {
        'list': [
          <String, Object?>{},
          {'safe': 'kept'},
        ],
      },
    });
  });

  test('strips the query string from URL-shaped string values', () {
    final result = scrubPii({
      'url':
          'https://example.supabase.co/rest/v1/songs?slug=eq.some-song&select=*',
    });

    expect(result, {'url': 'https://example.supabase.co/rest/v1/songs'});
  });

  test('strips the query string but keeps the fragment on URLs with both', () {
    final result = scrubPii({'url': 'https://x.com/path?a=1#frag'});

    expect(result, {'url': 'https://x.com/path#frag'});
  });

  test(
    'strips the query string from host-less URLs without adding a stray //',
    () {
      final result = scrubPii({'url': 'mailto:foo@bar.com?subject=hi'});

      expect(result, {'url': 'mailto:foo@bar.com'});
    },
  );

  test('redacts JWT-shaped string values regardless of key', () {
    const jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1c2VyIn0.dGVzdC1zaWduYXR1cmU';
    final result = scrubPii({'unlisted_key': jwt});

    expect(result, {'unlisted_key': '[redacted]'});
  });

  test(
    'redacts a JWT embedded in a larger string, not just an exact match',
    () {
      const jwt =
          'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1c2VyIn0.dGVzdC1zaWduYXR1cmU';
      final result = scrubPii({'header': 'Bearer $jwt'});

      expect(result, {'header': 'Bearer [redacted]'});
    },
  );

  test('passes through ordinary non-URL, non-JWT string values unchanged', () {
    final result = scrubPii({'reason': 'refresh failed'});

    expect(result, {'reason': 'refresh failed'});
  });

  test(
    'does not mangle ordinary prose containing a question mark and spaces',
    () {
      final result = scrubPii({
        'reason': 'did it work? yes it did',
        'note': 'user cancelled during confirm? or timeout',
      });

      expect(result, {
        'reason': 'did it work? yes it did',
        'note': 'user cancelled during confirm? or timeout',
      });
    },
  );

  test('strips the query string from a schemeless URL-shaped value', () {
    final result = scrubPii({
      'url': 'example.supabase.co/rest/v1/songs?apikey=SECRET',
    });

    expect(result, {'url': 'example.supabase.co/rest/v1/songs'});
  });

  test('drops userInfo credentials from a URL, never preserves them', () {
    final result = scrubPii({
      'url': 'https://apikey:SECRET@host.example/path?x=1',
    });

    expect(result, {'url': 'https://host.example/path'});
  });

  test('drops denylisted keys regardless of separator style', () {
    final result = scrubPii({
      'Access-Token': 'secret',
      'Api-Key': 'k2',
      'safe': 'kept',
    });

    expect(result, {'safe': 'kept'});
  });

  test('drops userInfo from a URL that has no query string', () {
    final result = scrubPii({'url': 'https://user:pass@host.com/path'});

    expect(result, {'url': 'https://host.com/path'});
  });

  test('drops a key=value fragment (implicit-flow tokens) from a URL', () {
    final result = scrubPii({
      'url': 'https://app/cb#access_token=A&refresh_token=R',
      'plain': 'https://app/cb#frag',
    });

    expect(result, {'url': 'https://app/cb', 'plain': 'https://app/cb#frag'});
  });

  test('scrubs URLs embedded in whitespace-separated text per token', () {
    final result = scrubPii({
      'error':
          'ClientException with message uri=https://x.supabase.co/rest/v1/songs?apikey=SECRET',
      'spaced': 'failed   at\thttps://user:pw@x.co/a?b=1#t=2  done',
    });

    expect(result, {
      'error':
          'ClientException with message uri=https://x.supabase.co/rest/v1/songs',
      'spaced': 'failed   at\thttps://x.co/a  done',
    });
  });

  test('does not mangle legitimate values containing a question mark', () {
    final result = scrubPii({
      'chordpro': '[C]Hello?[G]World',
      'windows': r'C:\Users\john\file?.txt',
      'short': 'a?b',
    });

    expect(result, {
      'chordpro': '[C]Hello?[G]World',
      'windows': r'C:\Users\john\file?.txt',
      'short': 'a?b',
    });
  });

  test('traverses non-String-keyed maps, sets, iterables and Uri values', () {
    final result = scrubPii({
      'dynamic': <dynamic, dynamic>{'token': 'SECRET', 'ok': 1, 5: 'five'},
      'set': {'https://x.com/p?apikey=S'},
      'iterable': Iterable<Object?>.generate(1, (_) => {'password': 'p'}),
      'uri': Uri.parse('https://x.com/p?apikey=S'),
    });

    expect(result, {
      'dynamic': {'ok': 1, '5': 'five'},
      'set': ['https://x.com/p'],
      'iterable': [<String, Object?>{}],
      'uri': 'https://x.com/p',
    });
  });

  test('drops credential-shaped keys across naming styles', () {
    final result = scrubPii({
      'x-api-key': '1',
      'secret': '2',
      'client_secret': '3',
      'password': '4',
      'cookie': '5',
      'set-cookie': '6',
      'id_token': '7',
      'provider_token': '8',
      'provider_refresh_token': '9',
      'code_verifier': '10',
      'jwt': '11',
      'Auth-Token': '12',
      'access.token': '13',
      'api key': '14',
      'Authorization': '15',
      'safe': 'kept',
    });

    expect(result, {'safe': 'kept'});
  });

  test('keeps keys that merely contain "token" but are not credentials', () {
    final result = scrubPii({
      'token_count': 3,
      'tokenizer': 'whitespace',
      'tokens_used': 9,
    });

    expect(result, {
      'token_count': 3,
      'tokenizer': 'whitespace',
      'tokens_used': 9,
    });
  });

  test('redacts JWT scanning in linear time on pathological input', () {
    final hostile = 'eyJ' * 33334; // ~100 KB
    final stopwatch = Stopwatch()..start();
    final result = scrubPii({'v': hostile});
    stopwatch.stop();

    expect(result, {'v': hostile});
    expect(stopwatch.elapsedMilliseconds, lessThan(1000));
  });

  test('redacts multiple and adjacent JWTs and JWTs glued to other text', () {
    const jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1c2VyIn0.dGVzdC1zaWduYXR1cmU';
    final result = scrubPii({'two': '$jwt $jwt', 'glued': 'token=$jwt;next'});

    expect(result, {
      'two': '[redacted] [redacted]',
      'glued': 'token=[redacted];next',
    });
  });

  test('redacts Supabase secret API keys', () {
    final result = scrubPii({
      'key': 'sb_secret_AbC-123_x',
      'text': 'using sb_secret_abc123 now',
    });

    expect(result, {'key': '[redacted]', 'text': 'using [redacted] now'});
  });

  group('schemeless host-shaped URLs (host with query/fragment, no path)', () {
    test('strips a `key=value` query from a bare host', () {
      final result = scrubPii({
        'a': 'abc.supabase.co?apikey=S',
        'b': 'x.co?token=T#y',
        'c': 'x.co:8080?token=T',
        'd': 'url=abc.supabase.co?apikey=S',
        'e': '(x.co?token=T)',
      });

      expect(result, {
        'a': 'abc.supabase.co',
        'b': 'x.co#y',
        'c': 'x.co:8080',
        'd': 'url=abc.supabase.co',
        'e': '(x.co)',
      });
    });

    test('strips a `key=value` fragment from a bare host', () {
      expect(scrubPii({'a': 'x.co#access_token=T', 'b': 'x.co#frag'}), {
        'a': 'x.co',
        'b': 'x.co#frag',
      });
    });

    test('does not mangle non-URL text with a question mark', () {
      final input = {
        'a': 'a?b',
        'b': '[C]Hello?[G]World',
        'c': r'C:\x\y?.txt',
        'd': 'e.g?',
        'e': 'e.g?x',
        'f': 'foo.bar?',
        'g': '[C]see.me?[G]x',
      };

      expect(scrubPii(input), input);
    });

    test('a version-like host with a key=value query is stripped (fail-safe, '
        'deliberately ambiguous)', () {
      expect(scrubPii({'v': 'v1.2?x=1'}), {'v': 'v1.2'});
    });
  });

  group('userinfo removal is greedy to the last @ of the token', () {
    test('userinfo containing a raw ?, / or # does not leak', () {
      final result = scrubPii({
        'q': 'https://u:p?ss@host/x',
        's': 'https://u:p/ss@host/x',
        'h': 'https://u:p#ss@host/x',
      });

      expect(result, {
        'q': 'https://host/x',
        's': 'https://host/x',
        'h': 'https://host/x',
      });
    });

    test('an @ inside the password itself does not leak the tail', () {
      expect(scrubPii({'u': 'https://user:p@ss@host/x'}), {
        'u': 'https://host/x',
      });
    });

    test('a token without :// keeps its @ (mailto), query still stripped', () {
      expect(scrubPii({'m': 'mailto:a@b?x=1'}), {'m': 'mailto:a@b'});
    });

    test('over-redacts an @ in the query or path (documented trade-off, '
        'bias is leak-free)', () {
      final result = scrubPii({
        'query': 'https://host/path?email=a@b.c',
        'path': 'https://host/a@b',
      });

      expect(result, {'query': 'https://b.c', 'path': 'https://b'});
    });
  });

  group('query/fragment region ends at a closing delimiter', () {
    test('keeps the remainder of a JSON-embedded URL', () {
      expect(scrubPii({'j': '{"url":"https://x/y?a=1","code":401}'}), {
        'j': '{"url":"https://x/y","code":401}',
      });
    });

    test('keeps the closer and rest for parenthesized, angle-bracketed and '
        'quoted URLs', () {
      final result = scrubPii({
        'p': '(https://x/y?apikey=S)',
        'a': '<https://x/y?apikey=S>',
        'd': '"https://x/y?apikey=S"',
        's': "'https://x/y?apikey=S'",
        'b': '[https://x/y?apikey=S]',
        'c': '{https://x/y?apikey=S}',
        'f': '(https://x/y?a=1#f=2)',
      });

      expect(result, {
        'p': '(https://x/y)',
        'a': '<https://x/y>',
        'd': '"https://x/y"',
        's': "'https://x/y'",
        'b': '[https://x/y]',
        'c': '{https://x/y}',
        'f': '(https://x/y)',
      });
    });

    test('handles several URLs in one token', () {
      expect(scrubPii({'j': '{"a":"https://x/y?k=1","b":"https://z/w#t=2"}'}), {
        'j': '{"a":"https://x/y","b":"https://z/w"}',
      });
    });

    test(
      'commas and brackets balanced inside the query never end it early',
      () {
        final result = scrubPii({
          'ids': 'https://x/y?ids=1,2',
          'arr': 'https://x/y?a[0]=1&b=2',
          'sep': 'https://x/y?a=1;b=2',
        });

        expect(result, {
          'ids': 'https://x/y',
          'arr': 'https://x/y',
          'sep': 'https://x/y',
        });
      },
    );

    test('an empty query is left alone', () {
      expect(scrubPii({'e': '(https://x/y?)'}), {'e': '(https://x/y?)'});
    });
  });

  group('key denylist gaps', () {
    test('drops authorization-suffixed, key-material and credential keys', () {
      final result = scrubPii({
        'Proxy-Authorization': '1',
        'x-authorization': '2',
        'private_key': '3',
        'privateKey': '4',
        'secret_key': '5',
        'secretkey': '6',
        'access_key': '7',
        'accessKey': '8',
        'credentials': '9',
        'credential': '10',
        'access_tokens': '11',
        'accesstokens': '12',
        'refresh_tokens': '13',
        'tokens': '14',
        'Tokens': '15',
        'safe': 'kept',
      });

      expect(result, {'safe': 'kept'});
    });

    test('still keeps plural-token metrics and near-miss keys', () {
      final input = {
        'token_count': 3,
        'tokenizer': 'ws',
        'tokens_used': 9,
        'authorizations_count': 1,
        'key_count': 2,
        'credential_count': 4,
      };

      expect(scrubPii(input), input);
    });
  });

  group('bounded traversal, never throws', () {
    test('a self-referencing map terminates with a truncation marker', () {
      final cyclic = <String, Object?>{'ok': 1};
      cyclic['self'] = cyclic;

      final result = scrubPii(cyclic);

      expect(result, isNotNull);
      expect(result!['ok'], 1);
      expect(result.toString(), contains('[truncated]'));
    });

    test('a self-referencing list terminates', () {
      final cyclic = <Object?>[];
      cyclic.add(cyclic);

      final result = scrubPii({'l': cyclic});

      expect(result, isNotNull);
      expect(result.toString(), contains('[truncated]'));
    });

    test(
      'nesting deeper than 16 levels is replaced by a truncation marker',
      () {
        Object? nested = 'leaf';
        for (var i = 0; i < 20; i++) {
          nested = <String, Object?>{'n': nested};
        }
        Object? shallow = 'leaf';
        for (var i = 0; i < 14; i++) {
          shallow = <String, Object?>{'n': shallow};
        }

        final result = scrubPii({'deep': nested, 'shallow': shallow});

        expect(result!['deep'].toString(), contains('[truncated]'));
        expect(result['deep'].toString(), isNot(contains('leaf')));
        expect(result['shallow'].toString(), contains('leaf'));
      },
    );

    test('very deep nesting does not overflow the stack', () {
      Object? deep = 'leaf';
      for (var i = 0; i < 100000; i++) {
        deep = <String, Object?>{'n': deep};
      }

      final result = scrubPii({'deep': deep});

      expect(result, isNotNull);
      expect(result.toString(), contains('[truncated]'));
      expect(result.toString(), isNot(contains('leaf')));
    });

    test('an infinite lazy iterable is cut by the element cap', () {
      final infinite = Iterable<int>.generate(1 << 30, (i) => i);

      final result = scrubPii({'inf': infinite});

      expect((result!['inf'] as List), hasLength(256));
    });

    test('collections beyond 256 elements are cut, smaller ones kept', () {
      final result = scrubPii({
        'big': List<int>.generate(1000, (i) => i),
        'map': {for (var i = 0; i < 1000; i++) 'k$i': i},
        'small': List<int>.generate(256, (i) => i),
      });

      expect((result!['big'] as List), hasLength(256));
      expect((result['map'] as Map), hasLength(256));
      expect((result['small'] as List), hasLength(256));
    });

    test('a wide self-referencing map is bounded by a total node budget', () {
      final cyclic = <String, Object?>{};
      for (var i = 0; i < 256; i++) {
        cyclic['k$i'] = cyclic;
      }
      final stopwatch = Stopwatch()..start();

      final result = scrubPii(cyclic);

      stopwatch.stop();
      expect(result, isNotNull);
      expect(stopwatch.elapsedMilliseconds, lessThan(1000));
    });

    test('a data structure that throws while being read yields a safe '
        'marker map, no data', () {
      final result = scrubPii({'ok': 1, 'bad': _ThrowingMap()});

      expect(result, {'scrub_error': true});
    });

    test('an iterable that throws mid-iteration is contained', () {
      Iterable<int> broken() sync* {
        yield 1;
        throw StateError('boom');
      }

      expect(scrubPii({'x': broken()}), {'scrub_error': true});
    });

    test('hostile query/hash runs stay linear', () {
      final stopwatch = Stopwatch()..start();
      final result = scrubPii({
        'q': '?' * 100000,
        'h': 'x.co${'?' * 100000}',
        'f': '#' * 100000,
        'u': '://' * 30000,
        'a': 'https://${'@' * 100000}',
      });
      stopwatch.stop();

      expect(result, isNotNull);
      expect(stopwatch.elapsedMilliseconds, lessThan(2000));
    });
  });

  test('returns null for null input', () {
    expect(scrubPii(null), isNull);
  });
}

class _ThrowingMap extends MapBase<String, Object?> {
  @override
  Object? operator [](Object? key) => throw StateError('boom');

  @override
  void operator []=(String key, Object? value) {}

  @override
  void clear() {}

  @override
  Iterable<String> get keys => throw StateError('boom');

  @override
  Object? remove(Object? key) => null;
}
