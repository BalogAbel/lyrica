import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/infrastructure/auth/supabase_auth_repository.dart';

void main() {
  test('restores the mapped current session', () async {
    final repository = SupabaseAuthRepository.testing(
      restoreSession: () async =>
          const AppAuthSession(userId: 'user-1', email: 'demo@lyron.local'),
      watchSession: () => const Stream.empty(),
      signIn: ({required email, required password}) async =>
          AppAuthSession(userId: 'user-2', email: email),
      signOut: () async {},
    );

    final session = await repository.restoreSession();

    expect(session?.userId, 'user-1');
    expect(session?.email, 'demo@lyron.local');
  });

  test('watches mapped auth session changes', () async {
    final controller = StreamController<AppAuthSession?>.broadcast();
    addTearDown(controller.close);
    final repository = SupabaseAuthRepository.testing(
      restoreSession: () async => null,
      watchSession: () => controller.stream,
      signIn: ({required email, required password}) async =>
          AppAuthSession(userId: 'user-2', email: email),
      signOut: () async {},
    );

    final events = <AppAuthSession?>[];
    final subscription = repository.watchSession().listen(events.add);
    addTearDown(subscription.cancel);

    controller.add(
      const AppAuthSession(userId: 'user-1', email: 'demo@lyron.local'),
    );
    controller.add(null);
    await Future<void>.delayed(Duration.zero);

    expect(events, hasLength(2));
    expect(events.first?.email, 'demo@lyron.local');
    expect(events.last, isNull);
  });

  test(
    'signs in with email and password through the auth client seam',
    () async {
      String? capturedEmail;
      String? capturedPassword;
      final repository = SupabaseAuthRepository.testing(
        restoreSession: () async => null,
        watchSession: () => const Stream.empty(),
        signIn: ({required email, required password}) async {
          capturedEmail = email;
          capturedPassword = password;
          return AppAuthSession(userId: 'user-2', email: email);
        },
        signOut: () async {},
      );

      final session = await repository.signIn(
        email: 'demo@lyron.local',
        password: 'LyronDemo123!',
      );

      expect(capturedEmail, 'demo@lyron.local');
      expect(capturedPassword, 'LyronDemo123!');
      expect(session.userId, 'user-2');
    },
  );

  test('signs out through the auth client seam', () async {
    var signOutCalls = 0;
    final repository = SupabaseAuthRepository.testing(
      restoreSession: () async => null,
      watchSession: () => const Stream.empty(),
      signIn: ({required email, required password}) async =>
          AppAuthSession(userId: 'user-2', email: email),
      signOut: () async {
        signOutCalls += 1;
      },
    );

    await repository.signOut();

    expect(signOutCalls, 1);
  });
}
