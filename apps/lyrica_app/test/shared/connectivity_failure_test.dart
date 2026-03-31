import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyrica_app/src/shared/connectivity_failure.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('isConnectivityFailure', () {
    test('returns true for low-level connectivity exceptions', () {
      expect(isConnectivityFailure(const SocketException('offline')), isTrue);
      expect(
        isConnectivityFailure(TimeoutException('request timed out')),
        isTrue,
      );
      expect(
        isConnectivityFailure(const HttpException('Service unavailable')),
        isTrue,
      );
    });

    test('returns true for retryable auth fetch failures', () {
      expect(
        isConnectivityFailure(
          AuthRetryableFetchException(message: 'ClientException: offline'),
        ),
        isTrue,
      );
    });

    test('returns true for retryable postgrest backend failures', () {
      expect(
        isConnectivityFailure(
          const PostgrestException(
            message: 'Service unavailable',
            code: '503',
            details: 'upstream connect error',
          ),
        ),
        isTrue,
      );
      expect(
        isConnectivityFailure(
          const PostgrestException(
            message: 'ClientException: Failed host lookup',
            code: '500',
          ),
        ),
        isTrue,
      );
    });

    test('returns false for authorization failures', () {
      expect(
        isConnectivityFailure(
          const PostgrestException(message: 'permission denied', code: '403'),
        ),
        isFalse,
      );
      expect(
        isConnectivityFailure(
          const AuthException('Invalid login credentials', statusCode: '400'),
        ),
        isFalse,
      );
    });
  });
}
