import 'package:lyrica_app/src/domain/auth/app_auth_session.dart';

abstract interface class AuthRepository {
  Future<AppAuthSession?> restoreSession();

  Stream<AppAuthSession?> watchSession();

  Future<AppAuthSession> signIn({
    required String email,
    required String password,
  });

  Future<void> signOut();
}
