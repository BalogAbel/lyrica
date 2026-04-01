import 'package:flutter/foundation.dart';
import 'package:lyron_app/src/application/auth/auth_repository.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef RestoreAppAuthSession = Future<AppAuthSession?> Function();
typedef WatchAppAuthSession = Stream<AppAuthSession?> Function();
typedef SignInAppAuthSession =
    Future<AppAuthSession> Function({
      required String email,
      required String password,
    });
typedef SignOutAppAuthSession = Future<void> Function();

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(SupabaseClient client)
    : this.testing(
        restoreSession: () async => _mapSession(client.auth.currentSession),
        watchSession: () => client.auth.onAuthStateChange.map(
          (event) => _mapSession(event.session),
        ),
        signIn: ({required email, required password}) async {
          final response = await client.auth.signInWithPassword(
            email: email,
            password: password,
          );
          final session = _mapSession(response.session);

          if (session == null) {
            throw StateError('Supabase sign-in did not return a session.');
          }

          return session;
        },
        signOut: client.auth.signOut,
      );

  @visibleForTesting
  SupabaseAuthRepository.testing({
    required RestoreAppAuthSession restoreSession,
    required WatchAppAuthSession watchSession,
    required SignInAppAuthSession signIn,
    required SignOutAppAuthSession signOut,
  }) : _restoreSession = restoreSession,
       _watchSession = watchSession,
       _signIn = signIn,
       _signOut = signOut;

  final RestoreAppAuthSession _restoreSession;
  final WatchAppAuthSession _watchSession;
  final SignInAppAuthSession _signIn;
  final SignOutAppAuthSession _signOut;

  @override
  Future<AppAuthSession?> restoreSession() => _restoreSession();

  @override
  Stream<AppAuthSession?> watchSession() => _watchSession();

  @override
  Future<AppAuthSession> signIn({
    required String email,
    required String password,
  }) => _signIn(email: email, password: password);

  @override
  Future<void> signOut() => _signOut();

  static AppAuthSession? _mapSession(Session? session) {
    if (session == null) {
      return null;
    }

    final email = session.user.email;
    if (email == null || email.isEmpty) {
      throw StateError('Supabase session is missing a user email.');
    }

    return AppAuthSession(userId: session.user.id, email: email);
  }
}
