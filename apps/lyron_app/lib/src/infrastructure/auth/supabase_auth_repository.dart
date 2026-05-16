import 'package:flutter/foundation.dart';
import 'package:lyron_app/src/application/auth/auth_repository.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/auth/sign_in_method.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef RestoreSessionFn = Future<AppAuthSession?> Function();
typedef WatchSessionFn = Stream<AppAuthSession?> Function();
typedef OAuthSignInFn =
    Future<void> Function(SignInMethod method, {required String redirectTo});
typedef MagicLinkFn =
    Future<void> Function({required String email, required String redirectTo});
typedef SignOutFn = Future<void> Function();
typedef DeleteAccountFn = Future<void> Function();

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(SupabaseClient client)
    : this.testing(
        restoreSession: () async => _mapSession(client.auth.currentSession),
        watchSession: () => client.auth.onAuthStateChange.map(
          (event) => _mapSession(event.session),
        ),
        signInWithOAuth: (method, {required redirectTo}) async {
          final provider = switch (method) {
            SignInMethod.google => OAuthProvider.google,
            SignInMethod.apple => OAuthProvider.apple,
            SignInMethod.magicLink => throw ArgumentError(
              'magic link must use sendMagicLink',
            ),
          };
          await client.auth.signInWithOAuth(provider, redirectTo: redirectTo);
        },
        sendMagicLink: ({required email, required redirectTo}) async {
          await client.auth.signInWithOtp(
            email: email,
            emailRedirectTo: redirectTo,
          );
        },
        signOut: client.auth.signOut,
        deleteAccount: () async {
          await client.rpc('delete_account');
        },
      );

  @visibleForTesting
  SupabaseAuthRepository.testing({
    required RestoreSessionFn restoreSession,
    required WatchSessionFn watchSession,
    required OAuthSignInFn signInWithOAuth,
    required MagicLinkFn sendMagicLink,
    required SignOutFn signOut,
    required DeleteAccountFn deleteAccount,
  }) : _restoreSession = restoreSession,
       _watchSession = watchSession,
       _signInWithOAuth = signInWithOAuth,
       _sendMagicLink = sendMagicLink,
       _signOut = signOut,
       _deleteAccount = deleteAccount;

  final RestoreSessionFn _restoreSession;
  final WatchSessionFn _watchSession;
  final OAuthSignInFn _signInWithOAuth;
  final MagicLinkFn _sendMagicLink;
  final SignOutFn _signOut;
  final DeleteAccountFn _deleteAccount;

  @override
  Future<AppAuthSession?> restoreSession() => _restoreSession();

  @override
  Stream<AppAuthSession?> watchSession() => _watchSession();

  @override
  Future<void> signInWithOAuth(
    SignInMethod method, {
    required String redirectTo,
  }) => _signInWithOAuth(method, redirectTo: redirectTo);

  @override
  Future<void> sendMagicLink({
    required String email,
    required String redirectTo,
  }) => _sendMagicLink(email: email, redirectTo: redirectTo);

  @override
  Future<void> signOut() => _signOut();

  @override
  Future<void> deleteAccount() => _deleteAccount();

  static AppAuthSession? _mapSession(Session? session) {
    if (session == null) return null;
    final email = session.user.email;
    if (email == null || email.isEmpty) {
      throw StateError('Supabase session is missing a user email.');
    }
    final providers =
        session.user.identities
            ?.map((i) => i.provider)
            .whereType<String>()
            .toList() ??
        const <String>[];
    return AppAuthSession(
      userId: session.user.id,
      email: email,
      linkedProviders: providers,
    );
  }
}
