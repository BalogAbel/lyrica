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

  test('returns null for null input', () {
    expect(scrubPii(null), isNull);
  });
}
