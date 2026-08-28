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

  test('redacts JWT-shaped string values regardless of key', () {
    const jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1c2VyIn0.dGVzdC1zaWduYXR1cmU';
    final result = scrubPii({'unlisted_key': jwt});

    expect(result, {'unlisted_key': '[redacted]'});
  });

  test('passes through ordinary non-URL, non-JWT string values unchanged', () {
    final result = scrubPii({'reason': 'refresh failed'});

    expect(result, {'reason': 'refresh failed'});
  });

  test('returns null for null input', () {
    expect(scrubPii(null), isNull);
  });
}
