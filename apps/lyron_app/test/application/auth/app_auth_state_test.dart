import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/app_auth_state.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/auth/app_auth_status.dart';

void main() {
  test(
    'two states differing only in lastKnownSession are not equal',
    () {
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
    },
  );
}
