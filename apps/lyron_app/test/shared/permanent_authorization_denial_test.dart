import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/shared/permanent_authorization_denial.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('isPermanentAuthorizationDenial', () {
    test('returns true for PostgreSQL code 42501', () {
      expect(
        isPermanentAuthorizationDenial(
          const PostgrestException(message: 'nope', code: '42501'),
        ),
        isTrue,
      );
    });

    test('returns true for HTTP code 403', () {
      expect(
        isPermanentAuthorizationDenial(
          const PostgrestException(message: 'nope', code: '403'),
        ),
        isTrue,
      );
    });

    test('returns true for the full "permission denied for ..." phrase with '
        'no structured code', () {
      expect(
        isPermanentAuthorizationDenial(
          const PostgrestException(
            message: 'permission denied for table songs',
          ),
        ),
        isTrue,
      );
    });

    test('does NOT match a bare "permission denied" substring quoted inside an '
        'unrelated message', () {
      expect(
        isPermanentAuthorizationDenial(
          const PostgrestException(
            message: 'custom check failed: permission denied elsewhere',
            code: 'P0001',
          ),
        ),
        isFalse,
      );
    });

    test('does NOT classify a bare 401 as a permanent denial', () {
      expect(
        isPermanentAuthorizationDenial(
          const PostgrestException(message: 'unauthorized', code: '401'),
        ),
        isFalse,
      );
    });
  });
}
