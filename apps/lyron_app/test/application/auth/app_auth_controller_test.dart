import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/app_auth_controller.dart';
import 'package:lyron_app/src/application/auth/auth_repository.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/auth/app_auth_status.dart';
import 'package:lyron_app/src/domain/auth/sign_in_method.dart';

class _FakeAuthRepository implements AuthRepository {
  final _controller = StreamController<AppAuthSession?>.broadcast();
  AppAuthSession? currentSession;
  bool oauthCalled = false;
  bool magicLinkCalled = false;
  bool signOutCalled = false;
  bool deleteCalled = false;

  @override
  Future<AppAuthSession?> restoreSession() async => currentSession;

  @override
  Stream<AppAuthSession?> watchSession() => _controller.stream;

  @override
  Future<void> signInWithOAuth(
    SignInMethod method, {
    required String redirectTo,
  }) async {
    oauthCalled = true;
  }

  @override
  Future<void> sendMagicLink({
    required String email,
    required String redirectTo,
  }) async {
    magicLinkCalled = true;
  }

  @override
  Future<void> signOut() async {
    signOutCalled = true;
  }

  @override
  Future<void> deleteAccount() async {
    deleteCalled = true;
  }

  void emit(AppAuthSession? session) => _controller.add(session);
}

void main() {
  test('restoreSession surfaces signedIn when a session exists', () async {
    final repo = _FakeAuthRepository();
    repo.currentSession = const AppAuthSession(userId: 'u', email: 'e@x');
    final controller = AppAuthController(repo);

    await controller.restoreSession();

    expect(controller.state.status, AppAuthStatus.signedIn);
    expect(controller.state.session?.userId, 'u');
  });

  test('signInWithOAuth delegates to the repository', () async {
    final repo = _FakeAuthRepository();
    final controller = AppAuthController(repo);
    await controller.restoreSession();

    await controller.signInWithOAuth(SignInMethod.google, redirectTo: 'redir');

    expect(repo.oauthCalled, isTrue);
  });

  test('sendMagicLink delegates to the repository', () async {
    final repo = _FakeAuthRepository();
    final controller = AppAuthController(repo);
    await controller.restoreSession();

    await controller.sendMagicLink(email: 'a@b', redirectTo: 'redir');

    expect(repo.magicLinkCalled, isTrue);
  });

  test('deleteAccount delegates and clears state', () async {
    final repo = _FakeAuthRepository();
    repo.currentSession = const AppAuthSession(userId: 'u', email: 'e@x');
    final controller = AppAuthController(repo);
    await controller.restoreSession();

    await controller.deleteAccount();

    expect(repo.deleteCalled, isTrue);
    expect(controller.state.status, AppAuthStatus.signedOut);
  });
}
