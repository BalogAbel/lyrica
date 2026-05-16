import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/auth/sign_in_method.dart';

abstract interface class AuthRepository {
  Future<AppAuthSession?> restoreSession();

  Stream<AppAuthSession?> watchSession();

  Future<void> signInWithOAuth(
    SignInMethod method, {
    required String redirectTo,
  });

  Future<void> sendMagicLink({
    required String email,
    required String redirectTo,
  });

  Future<void> signOut();

  Future<void> deleteAccount();
}
