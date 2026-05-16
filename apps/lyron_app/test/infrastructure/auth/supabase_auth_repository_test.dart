import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/domain/auth/sign_in_method.dart';
import 'package:lyron_app/src/infrastructure/auth/supabase_auth_repository.dart';

void main() {
  test('restoreSession returns null when no session', () async {
    final repo = SupabaseAuthRepository.testing(
      restoreSession: () async => null,
      watchSession: () => const Stream.empty(),
      signInWithOAuth: (_, {required redirectTo}) async {},
      sendMagicLink: ({required email, required redirectTo}) async {},
      signOut: () async {},
      deleteAccount: () async {},
    );

    expect(await repo.restoreSession(), isNull);
  });

  test('signInWithOAuth dispatches the chosen provider', () async {
    SignInMethod? captured;
    final repo = SupabaseAuthRepository.testing(
      restoreSession: () async => null,
      watchSession: () => const Stream.empty(),
      signInWithOAuth: (method, {required redirectTo}) async {
        captured = method;
      },
      sendMagicLink: ({required email, required redirectTo}) async {},
      signOut: () async {},
      deleteAccount: () async {},
    );

    await repo.signInWithOAuth(SignInMethod.apple, redirectTo: 'r');

    expect(captured, SignInMethod.apple);
  });

  test('deleteAccount invokes the RPC', () async {
    var called = false;
    final repo = SupabaseAuthRepository.testing(
      restoreSession: () async => null,
      watchSession: () => const Stream.empty(),
      signInWithOAuth: (_, {required redirectTo}) async {},
      sendMagicLink: ({required email, required redirectTo}) async {},
      signOut: () async {},
      deleteAccount: () async => called = true,
    );

    await repo.deleteAccount();

    expect(called, isTrue);
  });
}
