import 'dart:collection';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/infrastructure/observability/sentry_pii_scrub.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthChangeEvent, AuthState, Session, User;

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

  test('a fragment after a query is dropped together with it (everything '
      'after the first ? goes)', () {
    final result = scrubPii({'url': 'https://x.com/path?a=1#frag'});

    expect(result, {'url': 'https://x.com/path'});
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
    // Just under the 64 KB scrub cap, so the whole run is scanned.
    final hostile = 'eyJ' * 20000;
    final stopwatch = Stopwatch()..start();
    final result = scrubPii({'v': hostile, 'small': 'eyJ' * 2000});
    stopwatch.stop();

    expect(result!['small'], 'eyJ' * 2000);
    expect(result['v'], startsWith('eyJeyJ'));
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

      // `d` and `e` are not host-shaped as a whole (`url=`, `(`), so only the
      // credential key/value rule (C) fires: the value is redacted, the
      // `key=value` shape stays. Documented residual: an unknown key in that
      // position (`url=abc.co?foo=SECRET`) is not caught.
      expect(result, {
        'a': 'abc.supabase.co',
        'b': 'x.co',
        'c': 'x.co:8080',
        'd': 'url=abc.supabase.co?apikey=[redacted]',
        'e': '(x.co?token=[redacted])',
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

    test('a version-like host with a key=value query is stripped '
        '(deliberately ambiguous)', () {
      expect(scrubPii({'v': 'v1.2?x=1'}), {'v': 'v1.2'});
    });
  });

  group('userinfo removal', () {
    test('userinfo containing a raw ?, / or # does not leak', () {
      final result = scrubPii({
        'q': 'https://u:p?ss@host/x',
        's': 'https://u:p/ss@host/x',
        'h': 'https://u:p#ss@host/x',
      });

      // A `?`, `/` or `#` in the userinfo puts an `@` after the first
      // delimiter: ambiguous, so the whole rest of the token is dropped.
      expect(result, {
        'q': 'https://[redacted]',
        's': 'https://[redacted]',
        'h': 'https://[redacted]',
      });
    });

    test('URL rules run before credential key/value text: a key=value inside '
        'a userinfo cannot eat the @ that marks it', () {
      expect(
        scrubPii({
          'a': 'https://u:token=abc,SECRET@host/x',
          'b': 'https://SECRET{token=%40@',
        }),
        {'a': 'https://host/x', 'b': 'https://'},
      );
    });

    test('an @ inside the password itself does not leak the tail', () {
      expect(scrubPii({'u': 'https://user:p@ss@host/x'}), {
        'u': 'https://host/x',
      });
    });

    test('a token without :// keeps its @ (mailto), query still stripped', () {
      expect(scrubPii({'m': 'mailto:a@b?x=1'}), {'m': 'mailto:a@b'});
    });

    test('an @ inside the query or fragment never swallows the ? and leaks '
        'later params', () {
      final result = scrubPii({
        'rest':
            'https://abc.supabase.co/rest/v1/profiles?email=eq.bob@x.com&apikey=SECRET',
        'path': 'https://h/p?email=a@b.c&token=SECRET',
        'nopath': 'https://h?email=a@b.c&token=S',
        'both': 'https://u:p@h/x?email=a@b.c&token=S',
        'frag': 'https://h/p#email=a@b.c&token=S',
        'two': 'https://h/p?a=x@y@z&token=S',
      });

      // Ambiguous `@` after the first delimiter: never guessed, the rest of
      // the token is dropped (over-redacts an `@` in a query, by design).
      expect(result, {
        'rest': 'https://[redacted]',
        'path': 'https://[redacted]',
        'nopath': 'https://[redacted]',
        'both': 'https://[redacted]',
        'frag': 'https://[redacted]',
        'two': 'https://[redacted]',
      });
    });

    test('an @ in the path (before any ?) over-redacts, documented '
        'trade-off', () {
      expect(scrubPii({'path': 'https://host/a@b'}), {
        'path': 'https://[redacted]',
      });
    });

    test('a userinfo that is not host-shaped and holds ?/# is redacted '
        'whole, not read as host + query', () {
      final result = scrubPii({
        'q': 'https://u:p?ss@host/x',
        'h': 'https://u:p#ss@host/x',
        'sq': 'https://u:p/ss?x@host/x',
      });

      expect(result, {
        'q': 'https://[redacted]',
        'h': 'https://[redacted]',
        'sq': 'https://[redacted]',
      });
    });

    test('a URL with an @ after its first delimiter is redacted whatever '
        'follows the host', () {
      expect(scrubPii({'x': 'https://localhost:abc?email=a@b&token=S'}), {
        'x': 'https://[redacted]',
      });
    });

    test('a later URL in the same token cannot smuggle userinfo or a query '
        'past the first URL', () {
      expect(
        scrubPii({
          'j': '{"a":"https://x/y?k=1","b":"https://u:p@h/z"}',
          'k': 'https://a/x;https://u:p@b/y',
          'l': 'https://a/x,https://b/y?token=S',
        }),
        {
          // the second URL's `@` is after the first URL's first delimiter:
          // ambiguous, so the rest of the token goes (accepted trade-off)
          'j': '{"a":"https://[redacted]',
          'k': 'https://[redacted]',
          'l': 'https://a/x,https://b/y',
        },
      );
    });
  });

  group('everything after the first ? of a URL goes, to the end of the '
      'token', () {
    test('drops the remainder of a JSON-embedded URL in the same token', () {
      expect(scrubPii({'j': '{"url":"https://x/y?a=1","code":401}'}), {
        'j': '{"url":"https://x/y',
      });
    });

    test('drops the closer and rest for parenthesized, angle-bracketed and '
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
        'p': '(https://x/y',
        'a': '<https://x/y',
        'd': '"https://x/y',
        's': "'https://x/y",
        'b': '[https://x/y',
        'c': '{https://x/y',
        'f': '(https://x/y',
      });
    });

    test('handles several URLs in one token', () {
      expect(scrubPii({'j': '{"a":"https://x/y?k=1","b":"https://z/w#t=2"}'}), {
        'j': '{"a":"https://x/y',
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

    test(
      'an empty query is cut too (simplest rule, nothing to tell apart)',
      () {
        expect(scrubPii({'e': '(https://x/y?)'}), {'e': '(https://x/y'});
      },
    );

    test('a plain fragment without a query is kept, a key=value one goes', () {
      expect(
        scrubPii({
          'plain': 'https://x/y#frag',
          'kv': 'https://x/y#access_token=S',
          'kvAfterPlain': 'https://x/y#frag,a=b',
        }),
        {
          'plain': 'https://x/y#frag',
          'kv': 'https://x/y',
          'kvAfterPlain': 'https://x/y',
        },
      );
    });

    test('a key=value fragment is cut even when a ? follows it', () {
      expect(scrubPii({'a': 'https://h/cb#access_token=SECRET?x'}), {
        'a': 'https://h/cb',
      });
    });
  });

  group('quotes and closers inside a query never end the drop early', () {
    test('a quote, angle bracket or unbalanced closer inside a query value '
        'does not leak later params', () {
      final result = scrubPii({
        'apos': "https://h/x?q='a'&token=S",
        'quote': 'https://h/x?q="a"&token=S',
        'angle': 'https://h/x?q=<a>&token=S',
        'paren': 'https://h/x?k=a)b&token=S',
        'bracket': 'https://h/x?a=1]secret=S',
        'brace': 'https://h/x?a=1}secret=S',
        'real': "https://h/rest/v1/songs?title=eq.Don't&apikey=S",
      });

      expect(result, {
        'apos': 'https://h/x',
        'quote': 'https://h/x',
        'angle': 'https://h/x',
        'paren': 'https://h/x',
        'bracket': 'https://h/x',
        'brace': 'https://h/x',
        'real': 'https://h/rest/v1/songs',
      });
    });

    test('wrapped URLs lose their closer and tail too', () {
      final result = scrubPii({
        'p': '(https://h/x?f(a)=1&t=S)tail',
        'q': '"https://h/x?a=1"tail',
        'a': '<https://h/x?a=1>tail',
        'j': '{"url":"https://x/y?a=1","code":401}',
      });

      expect(result, {
        'p': '(https://h/x',
        'q': '"https://h/x',
        'a': '<https://h/x',
        'j': '{"url":"https://x/y',
      });
    });
  });

  group('a scheme URL after a non-URL ? in one token is still cut, plain '
      '?s stay', () {
    test('a URL after a non-URL question mark in the same token is '
        'stripped', () {
      final result = scrubPii({
        'a': 'why?https://h/x?token=S',
        'b': 'err?url=https://h/x?token=S',
        'c': 'u1?a=1,https://x?b=2',
        'd': '[C]Hello?https://abc.supabase.co/rest?apikey=S',
        'e': 'https://h/a=b?token=S',
        'f': 'why?https://h/x?flag',
      });

      expect(result, {
        'a': 'why?https://h/x',
        'b': 'err?url=https://h/x',
        'c': 'u1?a=1,https://x',
        'd': '[C]Hello?https://abc.supabase.co/rest',
        'e': 'https://h/a=b',
        'f': 'why?https://h/x',
      });
    });

    test('non-URL question marks stay untouched next to each other', () {
      final input = {
        'a': 'why?what?how',
        'b': 'a?b,c?d',
        'c': '[C]Hello?[G]World?[Am]x',
      };

      expect(scrubPii(input), input);
    });
  });

  group('slash-only (schemeless) tokens and ChordPro', () {
    test('a slash chord followed by a question mark is not mangled', () {
      final input = {
        'a': '[C/G]Why?[Am]Because',
        'b': 'a/b?x',
        'c': '[D/F#]Why?[G]x',
      };

      expect(scrubPii(input), input);
    });

    test('schemeless slash URLs with a key=value query are stripped', () {
      final result = scrubPii({
        'host': 'example.supabase.co/rest/v1/songs?apikey=SECRET',
        'abs': '/rest/v1/songs?apikey=S',
        'rel': 'rest/v1/songs?apikey=S',
        'frag': 'rest/v1/songs#access_token=T',
      });

      expect(result, {
        'host': 'example.supabase.co/rest/v1/songs',
        'abs': '/rest/v1/songs',
        'rel': 'rest/v1/songs',
        'frag': 'rest/v1/songs',
      });
    });
  });

  group('map keys are scrubbed like string values', () {
    test('a key holding a URL query, userinfo or JWT is scrubbed', () {
      const jwt =
          'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1c2VyIn0.dGVzdC1zaWduYXR1cmU';
      final result = scrubPii({
        'https://h/x?token=S': 1,
        'https://u:p@h/y': 2,
        jwt: 3,
        'plain_key': 4,
      });

      expect(result, {
        'https://h/x': 1,
        'https://h/y': 2,
        '[redacted]': 3,
        'plain_key': 4,
      });
    });

    test('keys that collide after scrubbing do not throw, the later wins', () {
      final result = scrubPii({
        'https://h/x?a=1': 'first',
        'https://h/x?b=2': 'second',
      });

      expect(result, {'https://h/x': 'second'});
    });

    test('a sensitive key is still dropped before its value is looked at', () {
      expect(scrubPii({'token': 'https://h/x?a=1', 'ok': 1}), {'ok': 1});
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

    test('drops credential-like keys added in revision 3', () {
      final result = scrubPii({
        'passwd': 1,
        'db_passwd': 1,
        'pwd': 1,
        'passphrase': 1,
        'ssh_passphrase': 1,
        'otp': 1,
        'totp': 1,
        'email_otp': 1,
        'csrf': 1,
        'xsrf': 1,
        'sig': 1,
        'signature': 1,
        'auth': 1,
        'auth_header': 1,
        'creds': 1,
        'token_hash': 1,
        'authcode': 1,
        'auth_code': 1,
        'authorization_code': 1,
        'mfa_code': 1,
        'recovery_code': 1,
        'recovery_codes': 1,
        'service_role_key': 1,
        'supabase_key': 1,
        'nonce': 1,
        'password_hash': 1,
        'private_key_id': 1,
        'jwts': 1,
        'access_jwt': 1,
        'secrets': 1,
        'client_secrets': 1,
        'passwords': 1,
        'cookies': 1,
        'apikeys': 1,
        'safe': 'kept',
      });

      expect(result, {'safe': 'kept'});
    });

    test('keeps generic short names that are ordinary data in this app', () {
      final input = {
        'code': 401,
        'status_code': 500,
        'time_signature': '4/4',
        'key_signature': 'G',
        'author': 'Anon',
        'authority': 'x',
        'authored_at': 't',
        'pinned': true,
        'pinned_count': 3,
        'session_id': 's-1',
        'sessionid': 's-2',
        'signal': 1,
        'sigma': 2,
        'nonces_seen': 3,
        'total_tokens': 4,
        'max_tokens': 5,
      };

      expect(scrubPii(input), input);
    });

    test('drops pin, passcode, bearer and otp/verification code keys '
        '(revision 4)', () {
      final result = scrubPii({
        'pin': '1234',
        'PIN': '1234',
        'passcode': '5678',
        'bearer': 'abc',
        'otp_code': '111',
        'otpcode': '111',
        'email_otp_code': '111',
        'verification_code': '222',
        'verificationcode': '222',
        'sms_verification_code': '222',
        'safe': 'kept',
      });

      expect(result, {'safe': 'kept'});
    });

    test('keeps near-miss names of the revision 4 keys', () {
      final input = {
        'pinned': 1,
        'pin_count': 2,
        'passcodes_seen': 3,
        'bearer_count': 4,
        'code': 401,
        'session_id': 'abc',
        'sessionid': 'abc',
        'correlation_id': 'abc',
      };

      expect(scrubPii(input), input);
    });

    test('a bool value is never a secret, so a bool-valued key is kept', () {
      final input = {
        'has_password': true,
        'show_password': false,
        'is_secret': true,
        'reset_password': false,
        'has_token': true,
      };

      expect(scrubPii(input), input);
    });

    test('the same keys with a non-bool value are still dropped', () {
      final result = scrubPii({
        'has_password': 'yes',
        'reset_password': 'hunter2',
        'is_secret': 1,
        'ok': true,
      });

      expect(result, {'ok': true});
    });

    test('pagination and cancellation cursors are kept', () {
      final input = {
        'page_token': 'abc',
        'next_page_token': 'def',
        'prev_page_token': 'ghi',
        'cancel_token': 'jkl',
        'sync_token': 'mno',
      };

      expect(scrubPii(input), input);
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

    // 60 000 is just under the 64 KB scrub cap, so the whole token really
    // is scanned (a whitespace-free 1 MB token is cut to nothing by the
    // cap and would exercise nothing); 1 MB proves the cap keeps that cheap.
    for (final size in [60000, 1 << 20]) {
      test('hostile delimiter runs of $size chars stay fast', () {
        final inputs = <String, String>{
          'question': '?' * size,
          'hash': '#' * size,
          'at': '@' * size,
          'scheme': '://' * (size ~/ 3),
          'comma': ',' * size,
          'equals': '=' * size,
          'host_question': 'x.co${'?' * size}',
          'slash_question': 'a/b${'?' * size}',
          'alt_question': 'a?' * (size ~/ 2),
          'host_alt': 'abc.def?' * (size ~/ 8),
          'url_at': 'https://${'@' * size}',
          'url_at_query': 'https://h/${'?a@' * (size ~/ 3)}',
          'scheme_at': 'https://a@' * (size ~/ 10),
          'scheme_hash_q': 'https://x${'?#' * (size ~/ 2)}',
          'comma_url': ',https://x/y?a=1' * (size ~/ 16),
          'equals_url': '=https://x/y' * (size ~/ 12),
          'urls_at_q': 'https://h?@' * (size ~/ 11),
          'paren': '(https://x/y?a=(' * (size ~/ 16),
          'slash_q_hash': 'a/b?#' * (size ~/ 5),
          'after_q_scheme': '?ab://' * (size ~/ 6),
        };

        for (final entry in inputs.entries) {
          final stopwatch = Stopwatch()..start();
          final result = scrubPii({'v': entry.value});
          stopwatch.stop();

          expect(result, isNotNull, reason: entry.key);
          expect(
            result!.containsKey('scrub_error'),
            isFalse,
            reason: entry.key,
          );
          expect(
            stopwatch.elapsedMilliseconds,
            lessThan(300),
            reason: '${entry.key} took ${stopwatch.elapsedMilliseconds} ms',
          );
        }
      });
    }
  });

  group('size caps', () {
    test('a 10 MB string is scrubbed on a bounded prefix and stays under the '
        'output cap, fast', () {
      final huge = 'did it work? yes it did ' * (10 * 1024 * 1024 ~/ 24);
      final stopwatch = Stopwatch()..start();

      final result = scrubPii({'v': huge});

      stopwatch.stop();
      final value = result!['v'] as String;
      expect(value.length, lessThanOrEqualTo(8 * 1024 + 16));
      expect(value, endsWith('…[truncated]'));
      expect(value, startsWith('did it work? yes it did'));
      expect(stopwatch.elapsedMilliseconds, lessThan(300));
    });

    test('a single 6M-char token neither overflows the stack nor yields a '
        'scrub_error', () {
      final token = 'a' * 6000000;

      final result = scrubPii({'v': token});

      expect(result!.containsKey('scrub_error'), isFalse);
      expect(result['v'], isA<String>());
      expect((result['v'] as String).length, lessThan(100));
    });

    test('a string within the caps is returned untouched, no marker', () {
      final result = scrubPii({'v': 'x' * 8000});

      expect(result, {'v': 'x' * 8000});
    });

    test('a redacted result never contains an unscrubbed tail of a truncated '
        'input', () {
      // Each JWT (~700 chars) collapses to `[redacted]`, so the scrubbed
      // 64 KB prefix is far below the output cap and the cut-off boundary
      // shows up in the output. A JWT straddling it must not survive.
      final jwt =
          'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1c2VyIn0${'A' * 655}.dGVzdC1zaWduYXR1cmU';
      final input = '$jwt ' * 200;

      final value = scrubPii({'v': input})!['v'] as String;

      expect(value, isNot(contains('eyJ')));
      expect(value, contains('[redacted]'));
      expect(value, endsWith('…[truncated]'));
    });

    test('a wide self-referencing map produces a bounded encoded size', () {
      final cyclic = <String, Object?>{};
      for (var i = 0; i < 256; i++) {
        cyclic['key_number_$i'] = cyclic;
      }

      final result = scrubPii(cyclic);

      expect(jsonEncode(result).length, lessThan(100 * 1024));
    });

    test('a wide structure of long strings is bounded by a total string '
        'budget, later values become [truncated]', () {
      final long = 'w' * 8000;
      final result = scrubPii({
        'list': List<String>.filled(200, long),
        'more': {for (var i = 0; i < 200; i++) 'k$i': long},
      });

      expect(jsonEncode(result).length, lessThan(100 * 1024));
      expect((result!['list'] as List).last, '[truncated]');
    });

    test('a huge key is capped too', () {
      final key = 'k' * 100000;

      final result = scrubPii({key: 1});

      expect(result!.keys.single.length, lessThanOrEqualTo(8 * 1024 + 16));
    });
  });

  group('credential key/value text in strings (rule C)', () {
    test('opaque refresh tokens do not pass through prose or JSON strings', () {
      final result = scrubPii({
        'a': 'refresh_token=abcdEFGHijkl',
        'b': '{"refresh_token":"abcdEFGHijkl"}',
        'c': "{'access_token':'abcdEFGHijkl'}",
        'd': 'failed: refresh_token: abcdEFGHijkl and retry',
        'e': 'grant failed, id_token=abcdEFGHijkl&next=1',
        'f': 'x-api-key: K3Y, y',
        'g': 'PASSWORD=hunter2;',
        'h': '{"provider_refresh_token": "abcdEFGHijkl", "ok": 1}',
        'i': '{"client_secret":"abcd","apikey":"k","passwd":"p","secret":"s"}',
      });

      expect(result, {
        'a': 'refresh_token=[redacted]',
        'b': '{"refresh_token":"[redacted]"}',
        'c': "{'access_token':'[redacted]'}",
        'd': 'failed: refresh_token: [redacted] and retry',
        'e': 'grant failed, id_token=[redacted]&next=1',
        'f': 'x-api-key: [redacted], y',
        'g': 'PASSWORD=[redacted];',
        'h': '{"provider_refresh_token": "[redacted]", "ok": 1}',
        'i':
            '{"client_secret":"[redacted]","apikey":"[redacted]",'
            '"passwd":"[redacted]","secret":"[redacted]"}',
      });
    });

    test('authorization also consumes a Bearer/Basic scheme word', () {
      final result = scrubPii({
        'a': 'Authorization: Bearer abc.def-ghi',
        'b': 'authorization=Basic dXNlcjpwYXNz next',
        'c': '{"authorization":"Bearer abc"}',
        'd': 'authorization: abc',
      });

      expect(result, {
        'a': 'Authorization: Bearer [redacted]',
        'b': 'authorization=Basic [redacted] next',
        'c': '{"authorization":"Bearer [redacted]"}',
        'd': 'authorization: [redacted]',
      });
    });

    test('is anchored at a word boundary and matches whole keys only', () {
      final input = {
        'a': 'mytoken=abc',
        'b': 'token_count=3',
        'c': 'tokens=3 max_tokens=5',
        'd': 'the token was empty',
        'e': 'token=',
        'f': 'secretary: Ann',
      };

      expect(scrubPii(input), input);
    });

    test('is idempotent and leaves an already redacted value alone', () {
      final once = scrubPii({'a': 'token=abc, refresh_token: xyz'})!;

      expect(once, {'a': 'token=[redacted], refresh_token: [redacted]'});
      expect(scrubPii(once), once);
    });

    test('is linear-time on adversarial 64 KB inputs', () {
      final inputs = <String, String>{
        'token_eq': 'token=' * 10000,
        'token_json': '"token":"' * 5000,
        'token_sp': 'token ' * 10000,
        'token_colon_sp': 'token: ' * 8000,
        'auth_bearer': 'authorization: bearer ' * 2900,
        'underscores': '_' * 64000,
        'letters': 'a' * 64000,
        'token_run': 'token' * 12000,
        'refresh_run': 'refresh_' * 8000,
        'quotes': '"\'' * 30000,
        'key_spaces': 'password${' ' * 60000}',
      };

      for (final entry in inputs.entries) {
        final stopwatch = Stopwatch()..start();
        final result = scrubPii({'v': entry.value});
        stopwatch.stop();

        expect(result!.containsKey('scrub_error'), isFalse, reason: entry.key);
        expect(
          stopwatch.elapsedMilliseconds,
          lessThan(300),
          reason: '${entry.key} took ${stopwatch.elapsedMilliseconds} ms',
        );
      }
    });
  });

  group('non-String objects are stringified and scrubbed', () {
    test('an exception object holding a URL query does not leak', () {
      final result = scrubPii({
        'e': const FormatException('bad https://h/x?token=S'),
        'nested': [StateError('boom https://h/y?apikey=K')],
      });

      expect(result, {
        'e': 'FormatException: bad https://h/x',
        'nested': ['Bad state: boom https://h/y'],
      });
    });

    test('an arbitrary object with a JWT in toString is redacted', () {
      const jwt =
          'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1c2VyIn0.dGVzdC1zaWduYXR1cmU';

      expect(scrubPii({'o': _Stringy('bearer $jwt')}), {
        'o': 'bearer [redacted]',
      });
    });

    test('null, num and bool pass through untouched, enums become their '
        'scrubbed name', () {
      expect(
        scrubPii({'n': null, 'i': 1, 'd': 2.5, 'b': true, 'e': _Color.red}),
        {'n': null, 'i': 1, 'd': 2.5, 'b': true, 'e': '_Color.red'},
      );
    });

    test('a toString that throws becomes [unprintable], never an error', () {
      expect(scrubPii({'o': _ThrowingToString()}), {'o': '[unprintable]'});
    });

    test('an object with a huge toString is capped like any string', () {
      final value = scrubPii({'o': _Stringy('x ' * 50000)})!['o'] as String;

      expect(value.length, 8 * 1024 + '…[truncated]'.length);
    });
  });

  group('URL rule set, verified probes', () {
    Object? one(String input) => scrubPii({'v': input})!['v'];

    test('scheme URL: @ after the first delimiter drops the rest', () {
      expect(
        one('https://h/u/a@b,c?next=https://app/x&token=S'),
        'https://[redacted]',
      );
      expect(
        one(
          'https://h/files/me@x.com+1.png?redirect_to=https://app/cb&token=S',
        ),
        'https://[redacted]',
      );
      expect(
        one('https://bücher.de/?email=a@b.c&redirect_to=https://app&token=S'),
        'https://[redacted]',
      );
      expect(
        one('https://h/a@b,c#r=https://z&access_token=S'),
        'https://[redacted]',
      );
      expect(
        one('https://admin:2024#x@db.host:5432/app'),
        'https://[redacted]',
      );
      expect(one('https://user:1234?rest@host/x'), 'https://[redacted]');
      expect(one('https://user:p@ss:1?x@host/'), 'https://[redacted]');
      expect(one('https://host.com/a@b'), 'https://[redacted]');
    });

    test(
      'scheme URL: userinfo in the authority is dropped up to the last @',
      () {
        expect(one('https://user:pass@host.com/path'), 'https://host.com/path');
        expect(one('https://u:p@ss@host/x'), 'https://host/x');
        expect(one('https://u%40x:p@host:5432/db'), 'https://host:5432/db');
      },
    );

    test('scheme URL: everything from the first ? on is dropped', () {
      expect(one('(https://h/x?q=a)&token=S)'), '(https://h/x');
      expect(one('<https://h/x?q=a>&token=S>'), '<https://h/x');
      expect(one('[https://h?id=a]b&token=S]'), '[https://h');
      expect(one("https://h/it's?token=S"), "https://h/it's");
      expect(
        one("https://h/.../Don't%20Stop.pdf?token=S"),
        "https://h/.../Don't%20Stop.pdf",
      );
      expect(one('a/b?x,https://h/y?SECRET'), 'a/b?x,https://h/y');
      expect(one('`https://h/x?SECRET'), '`https://h/x');
      expect(one('!https://h/x?SECRET'), '!https://h/x');
      expect(
        one('https://h/x#frag,https://h2/y?SECRET'),
        'https://h/x#frag,https://h2/y',
      );
    });

    test('more than 8 URLs in one token: the rest is dropped', () {
      final token = '${List.filled(12, 'https://h/x').join(',')}?SECRET';

      final result = one(token) as String;

      expect(result, isNot(contains('SECRET')));
      expect(result, endsWith('https://[redacted]'));
      expect('https://'.allMatches(result).length, 9);
    });

    test('no scheme URL: schemeless URL-shaped tokens with = are cut', () {
      expect(one('?apikey=S'), '?apikey=[redacted]');
      expect(one('localhost?apikey=S'), 'localhost?apikey=[redacted]');
      expect(
        one('example.supabase.co/rest/v1/songs?apikey=SECRET'),
        'example.supabase.co/rest/v1/songs',
      );
      expect(one('/rest/v1/songs?apikey=S'), '/rest/v1/songs');
      expect(one('abc.supabase.co?apikey=S'), 'abc.supabase.co');
      expect(one('abc.supabase.co?foo=S'), 'abc.supabase.co');
      expect(one('/rest/v1/songs?foo=S'), '/rest/v1/songs');
      expect(one('abc.supabase.co:8080#foo=S'), 'abc.supabase.co:8080');
    });

    test('no scheme URL: non-hierarchical scheme URIs are cut at the ?', () {
      expect(one('mailto:foo@bar.com?subject=hi'), 'mailto:foo@bar.com');
      expect(one('mailto:a@b?SECRET'), 'mailto:a@b');
      expect(one('tel:+1555?x=1#y=2'), 'tel:+1555');
      expect(one(r'C:\Users\john\file?.txt'), r'C:\Users\john\file?.txt');
    });

    test('benign text is untouched', () {
      final input = {
        'a': '[C/G]Why?[Am]Because',
        'b': 'a?b',
        'c': '[C]Hello?[G]World',
        'd': 'a/b?x',
        'e': 'and/or?',
        'f': 'user@example.com wrote',
        'g': '/usr/bin/x?y',
        'h': '1/2?',
        'i': 'C#m7 Am/G 10:30',
        'j': '?SECRET',
      };

      expect(scrubPii(input), input);
    });

    test('documented residuals: not caught, cannot be told from prose', () {
      // Only the FIRST ?/# of a scheme-less token is classified, so a
      // schemeless URL after an earlier non-URL `?` slips through unless its
      // key is a credential name (rule C).
      expect(one('why?/p?k=SECRETVALUE'), 'why?/p?k=SECRETVALUE');
      expect(one('why?/p?apikey=SECRETVALUE'), 'why?/p?apikey=[redacted]');
      // An unknown key after a `=`/`,`-glued host, and a bare `?SECRET`.
      expect(one('url=abc.co?foo=SECRETVALUE'), 'url=abc.co?foo=SECRETVALUE');
      expect(one('?SECRETVALUE'), '?SECRETVALUE');
      // A quoted value with spaces: only its first word is a credential run.
      expect(
        one('{"password": "hunter two"}'),
        '{"password": "[redacted] two"}',
      );
    });

    test('a one-character prefix is not a scheme (a://, a drive letter)', () {
      // `a://` is not a scheme URL, so rule B judges the token: a key=value
      // query after a `/` is cut, a bare `?SECRET` is the documented residual.
      expect(one('a://h/x?k=SECRET'), 'a://h/x');
      expect(one('a://h/x?SECRET'), 'a://h/x?SECRET');
      expect(one(r'C:\x?y=1'), r'C:\x?y=1');
    });

    test('redacting a credential value can change how the rest of the token '
        'is classified: the result is still a fixed point', () {
      const inputs = [
        'token=?{]">x[SECRETVALUE"xp/?=',
        "(!token=SECRETVALUE?'/#!=.",
        ">'token=SECRETVALUE#co&hk&a://#=https://",
      ];
      final outputs = [for (final input in inputs) one(input)];

      expect(outputs, [
        'token=[redacted]">x[SECRETVALUE"xp/',
        "(!token=[redacted]'/",
        ">'token=[redacted]&hk&a://",
      ]);
      expect([for (final output in outputs) one(output as String)], outputs);
    });

    test('a schemeless URL before a scheme URL in one token is cut too', () {
      expect(one('/rest/v1/x?k=SECRETVALUE,https://h/y'), '/rest/v1/x');
      expect(one('x.co#k=SECRETVALUE;https://h/y'), 'x.co');
      expect(one('a/b?x,https://h/y'), 'a/b?x,https://h/y');
    });

    test('documented benign mangling of look-alikes', () {
      expect(one('Dr.Who?name=x'), 'Dr.Who');
      expect(one('1.5?x=2'), '1.5');
      expect(one('[G/B]Love?[C]=joy'), '[G/B]Love');
      expect(one('v1.2?x=1'), 'v1.2');
      expect(one('foo.bar?baz=qux'), 'foo.bar');
    });
  });

  group('review round 5: rule C names, cross-token pairs, JWT scan, cap', () {
    Object? one(String input) => scrubPii({'v': input})!['v'];

    test('rule C matches camelCase and _-prefixed credential names', () {
      expect(
        {
          for (final input in [
            'accessToken=S',
            'refreshToken: S',
            'idToken=S',
            'providerToken: S',
            'providerRefreshToken=S',
            'clientSecret=S',
            'apiKey=S',
            'my_token=S',
            'sb_access_token=S',
            'new_password=S',
            '_secret=S',
            'x_authorization=S',
            '{"refreshToken":"S"}',
          ])
            input: one(input),
        },
        {
          'accessToken=S': 'accessToken=[redacted]',
          'refreshToken: S': 'refreshToken: [redacted]',
          'idToken=S': 'idToken=[redacted]',
          'providerToken: S': 'providerToken: [redacted]',
          'providerRefreshToken=S': 'providerRefreshToken=[redacted]',
          'clientSecret=S': 'clientSecret=[redacted]',
          'apiKey=S': 'apiKey=[redacted]',
          'my_token=S': 'my_token=[redacted]',
          'sb_access_token=S': 'sb_access_token=[redacted]',
          'new_password=S': 'new_password=[redacted]',
          '_secret=S': '_secret=[redacted]',
          'x_authorization=S': 'x_authorization=[redacted]',
          '{"refreshToken":"S"}': '{"refreshToken":"[redacted]"}',
        },
      );
    });

    test('a key that merely starts with a credential name is untouched', () {
      final input = {
        'a': 'token_count=3',
        'b': 'tokenizer: x',
        'c': 'password_reset_flow: on',
        'd': 'secret_santa=2024',
        'e': 'mytoken=abc',
        'f': 'myToken=S',
        'g': 'tokenType: bearer',
        'h': 'expiresIn: 3600',
      };

      expect(scrubPii(input), input);
    });

    Session realSession() => Session(
      accessToken: 'opaqueAccessValue',
      tokenType: 'bearer',
      refreshToken: 'v1rTkSECRETVALUE',
      providerToken: 'ya29.SECRETX',
      providerRefreshToken: '1//SECRETY',
      user: const User(
        id: 'user-id-1',
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: '2026-01-01T00:00:00Z',
      ),
    );

    test('a real gotrue Session and AuthState never leak their tokens through '
        'the toString scrub', () {
      final session = realSession();
      final result = scrubPii({
        'session': session,
        'state': AuthState(AuthChangeEvent.signedIn, session),
        'list': [session],
      })!;
      final text = result.toString();

      expect(text, isNot(contains('SECRETVALUE')));
      expect(text, isNot(contains('SECRETX')));
      expect(text, isNot(contains('SECRETY')));
      expect(text, isNot(contains('opaqueAccessValue')));
      expect(text, contains('refreshToken: [redacted]'));
      expect(text, contains('providerToken: [redacted]'));
    });

    test('a credential key whose value is in the next whitespace token is not '
        'eaten by the URL pass', () {
      expect(one('x.co?a=1,token: SECRETVALUE'), 'x.co [redacted]');
      expect(one('https://h/p?x=1,"token": S'), 'https://h/p [redacted]');
      expect(one('ab:?APIKEY = S'), 'ab: = [redacted]');
      expect(
        one('https://h/p?x=1,authorization: Bearer S'),
        'https://h/p Bearer [redacted]',
      );
      // Ordering stays: a `token=` inside userinfo must not eat its `@`.
      expect(one('https://SECRET{token=%40@'), 'https://');
      for (final output in [
        one('x.co?a=1,token: SECRETVALUE'),
        one('https://h/p?x=1,"token": S'),
        one('ab:?APIKEY = S'),
      ]) {
        expect(one(output as String), output);
      }
    });

    const jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1c2VyIn0.dGVzdC1zaWduYXR1cmU';

    test('a JWT after an eyJ-containing dotted prefix is redacted whole', () {
      expect(one('surveyJson.v1.$jwt'), 'surv[redacted]');
      expect(one('eyJx.y.$jwt'), '[redacted]');
      // A real JWT's own payload starts with `eyJ` too, so it marks the two
      // parts after it: a dotted word glued to a JWT goes with it (accepted
      // over-redaction, never a leak).
      expect(one('a.eyJb.c.$jwt.tail'), 'a.[redacted]');
      expect(one('$jwt.tail'), '[redacted]');
      expect(one('$jwt tail.x'), '[redacted] tail.x');
    });

    test('JWT scan stays exact for the plain shapes', () {
      expect(one('eyJa.b.c'), '[redacted]');
      expect(one('x-eyJa.b.c.d'), 'x-[redacted].d');
      expect(one('eyJa.b.'), '[redacted]');
      expect(one('eyJa..c'), 'eyJa..c');
      expect(one('$jwt.$jwt'), '[redacted]');
      expect(one('$jwt $jwt'), '[redacted] [redacted]');
    });

    test('JWT scan is linear on dot-heavy hostile input', () {
      final inputs = [
        'eyJ.a.' * 9000,
        '.' * 60000,
        'eyJ' * 20000,
        'eyJa.b.' * 8000,
        'a.eyJa.' * 8000,
      ];
      for (final input in inputs) {
        final stopwatch = Stopwatch()..start();
        final result = scrubPii({'v': input})!;
        stopwatch.stop();

        expect(result.containsKey('scrub_error'), isFalse);
        expect(stopwatch.elapsedMilliseconds, lessThan(300));
      }
    });

    test('userinfo is cut at the LAST @ of the authority, however many', () {
      expect(one('https://a@b@c@host/x?k=S'), 'https://host/x');
      expect(one('https://a@b@c@d@host?k=S'), 'https://host');
      expect(one('https://u:p@x@host/x'), 'https://host/x');
    });

    test(
      'truncation is idempotent, including at a surrogate-pair boundary',
      () {
        final input = '${'a' * 8191}😀${'b' * 100}';

        final once = one(input) as String;

        expect(once, '${'a' * 8191}…[truncated]');
        expect(one(once), once);
        final exact = one('x' * 9000) as String;
        expect(exact, '${'x' * 8192}…[truncated]');
        expect(one(exact), exact);
        // Already-marked output at exactly one marker over the limit is kept
        // as is, not cut again (pins the guard's boundary).
        final marked = '${'a' * 8191}\uD83D…[truncated]';
        expect(one(marked), marked);
      },
    );

    test('documented residual: a schemeless URL after any non-whitespace '
        'prefix keeps an unknown-key query', () {
      expect(one('x=abc.co?foo=SECRETVALUE'), 'x=abc.co?foo=SECRETVALUE');
      expect(
        one('{"url":"x.co:8080?k=SECRETVALUE"}'),
        '{"url":"x.co:8080?k=SECRETVALUE"}',
      );
      expect(one('("abc.co?k=SECRETVALUE")'), '("abc.co?k=SECRETVALUE")');
      // A credential name glued to a preceding letter is not matched either.
      expect(one('authToken=SECRETVALUE'), 'authToken=SECRETVALUE');
      expect(one('sessionToken: SECRETVALUE'), 'sessionToken: SECRETVALUE');
      // ...but a credential-named key in the same position is rule C's.
      expect(one('("abc.co?token=S")'), '("abc.co?token=[redacted]")');
    });
  });

  group('exact size-cap boundaries', () {
    test('output: 8192 characters are kept whole, 8193 are cut with the '
        'marker', () {
      expect(scrubPii({'v': 'x' * 8192})!['v'], 'x' * 8192);
      expect(scrubPii({'v': 'x' * 8193})!['v'], '${'x' * 8192}…[truncated]');
    });

    // Each chunk is 512 chars and collapses to `[redacted] ` (11 chars), so
    // the scrubbed prefix stays far below the 8 KB output cap and the
    // input-cap boundary itself is visible in the result.
    final chunk = 'sb_secret_${'a' * 501} ';

    test('input: exactly 64 KB is scrubbed whole, no marker', () {
      final input = chunk * 128;
      expect(input.length, 65536);

      final value = scrubPii({'v': input})!['v'] as String;

      expect(value, '[redacted] ' * 128);
    });

    test('input: 64 KB + 1 is cut, the unscrubbed tail is never emitted', () {
      final input = '${chunk * 128}x';
      expect(input.length, 65537);

      final value = scrubPii({'v': input})!['v'] as String;

      expect(value, '${'[redacted] ' * 127}[redacted]…[truncated]');
      expect(value, isNot(contains('x')));
    });
  });

  test('returns null for null input', () {
    expect(scrubPii(null), isNull);
  });
}

enum _Color { red }

class _Stringy {
  _Stringy(this.text);
  final String text;

  @override
  String toString() => text;
}

class _ThrowingToString {
  @override
  String toString() => throw StateError('no string for you');
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
