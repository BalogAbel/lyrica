import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/app_auth_state.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/auth/app_auth_status.dart';

void main() {
  test('two states differing only in lastKnownSession are not equal', () {
    const a = AppAuthState(status: AppAuthStatus.sessionExpired);
    const b = AppAuthState(
      status: AppAuthStatus.sessionExpired,
      lastKnownSession: AppAuthSession(
        userId: 'u1',
        email: 'e@x',
        linkedProviders: [],
      ),
    );
    const c = AppAuthState(
      status: AppAuthStatus.sessionExpired,
      lastKnownSession: AppAuthSession(
        userId: 'u1',
        email: 'e@x',
        linkedProviders: [],
      ),
    );

    expect(a == b, isFalse);
    expect(b.hashCode, c.hashCode);
    expect(b.lastKnownSession?.userId, 'u1');
  });

  group('currentUserId', () {
    const session = AppAuthSession(userId: 'live', email: 'live@x');
    const lastKnown = AppAuthSession(userId: 'cached', email: 'cached@x');

    test('is the live session user when signed in', () {
      const state = AppAuthState(
        status: AppAuthStatus.signedIn,
        session: session,
      );
      expect(state.currentUserId, 'live');
    });

    test('is the last known session user when the session expired', () {
      const state = AppAuthState(
        status: AppAuthStatus.sessionExpired,
        lastKnownSession: lastKnown,
      );
      expect(state.currentUserId, 'cached');
    });

    test('is null while initializing or signed out', () {
      expect(
        const AppAuthState(status: AppAuthStatus.initializing).currentUserId,
        isNull,
      );
      expect(
        const AppAuthState(
          status: AppAuthStatus.signedOut,
          lastKnownSession: lastKnown,
        ).currentUserId,
        isNull,
      );
    });
  });
}
