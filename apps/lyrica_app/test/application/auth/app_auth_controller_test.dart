import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyrica_app/src/application/auth/app_auth_controller.dart';
import 'package:lyrica_app/src/application/auth/app_auth_state.dart';
import 'package:lyrica_app/src/application/auth/auth_repository.dart';
import 'package:lyrica_app/src/domain/auth/app_auth_session.dart';
import 'package:lyrica_app/src/domain/auth/app_auth_status.dart';

void main() {
  test(
    'starts initializing and restores to signed out when no session exists',
    () async {
      final repository = _StubAuthRepository();
      final controller = AppAuthController(repository);
      addTearDown(controller.dispose);

      expect(controller.state.status, AppAuthStatus.initializing);

      await controller.restoreSession();

      expect(
        controller.state,
        const AppAuthState(status: AppAuthStatus.signedOut),
      );
    },
  );

  test('restores a valid session', () async {
    final repository = _StubAuthRepository(
      restoredSession: const AppAuthSession(
        userId: 'user-1',
        email: 'demo@lyrica.local',
      ),
    );
    final controller = AppAuthController(repository);
    addTearDown(controller.dispose);

    await controller.restoreSession();

    expect(controller.state.status, AppAuthStatus.signedIn);
    expect(controller.state.session?.userId, 'user-1');
  });

  test('signs in with repository credentials', () async {
    final repository = _StubAuthRepository(
      signInSession: const AppAuthSession(
        userId: 'user-2',
        email: 'demo@lyrica.local',
      ),
    );
    final controller = AppAuthController(repository);
    addTearDown(controller.dispose);

    await controller.signIn(
      email: 'demo@lyrica.local',
      password: 'LyricaDemo123!',
    );

    expect(controller.state.status, AppAuthStatus.signedIn);
    expect(repository.lastSignInEmail, 'demo@lyrica.local');
    expect(repository.lastSignInPassword, 'LyricaDemo123!');
  });

  test(
    'transitions to session expired when a valid session disappears',
    () async {
      final repository = _StubAuthRepository(
        restoredSession: const AppAuthSession(
          userId: 'user-1',
          email: 'demo@lyrica.local',
        ),
      );
      final controller = AppAuthController(repository);
      addTearDown(controller.dispose);

      await controller.restoreSession();
      repository.emitSession(null);
      await Future<void>.delayed(Duration.zero);

      expect(
        controller.state,
        const AppAuthState(status: AppAuthStatus.sessionExpired),
      );
    },
  );

  test('sign out clears the current session state', () async {
    final repository = _StubAuthRepository(
      restoredSession: const AppAuthSession(
        userId: 'user-1',
        email: 'demo@lyrica.local',
      ),
    );
    final controller = AppAuthController(repository);
    addTearDown(controller.dispose);

    await controller.restoreSession();
    await controller.signOut();

    expect(
      controller.state,
      const AppAuthState(status: AppAuthStatus.signedOut),
    );
    expect(repository.signOutCalls, 1);
  });
}

class _StubAuthRepository implements AuthRepository {
  _StubAuthRepository({this.restoredSession, this.signInSession});

  final AppAuthSession? restoredSession;
  final AppAuthSession? signInSession;
  final StreamController<AppAuthSession?> _controller =
      StreamController<AppAuthSession?>.broadcast();

  String? lastSignInEmail;
  String? lastSignInPassword;
  int signOutCalls = 0;

  @override
  Future<AppAuthSession?> restoreSession() async => restoredSession;

  @override
  Stream<AppAuthSession?> watchSession() => _controller.stream;

  @override
  Future<AppAuthSession> signIn({
    required String email,
    required String password,
  }) async {
    lastSignInEmail = email;
    lastSignInPassword = password;
    final session =
        signInSession ?? AppAuthSession(userId: 'signed-in-user', email: email);
    _controller.add(session);
    return session;
  }

  @override
  Future<void> signOut() async {
    signOutCalls += 1;
    _controller.add(null);
  }

  void emitSession(AppAuthSession? session) {
    _controller.add(session);
  }
}
