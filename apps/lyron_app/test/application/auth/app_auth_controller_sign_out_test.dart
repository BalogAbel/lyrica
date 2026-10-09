import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/app_auth_controller.dart';
import 'package:lyron_app/src/application/auth/auth_repository.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/auth/app_auth_status.dart';
import 'package:lyron_app/src/domain/auth/sign_in_method.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Models gotrue's sign-out (gotrue_client.dart:1085-1108): drop the local
/// session and emit signedOut, then call the backend.
class _RevocationRepository implements AuthRepository {
  final _controller = StreamController<AppAuthSession?>.broadcast();
  final revocation = Completer<void>();
  bool emitSignedOutFirst = true;

  void dispose() => _controller.close();

  void emit(AppAuthSession? session) => _controller.add(session);

  @override
  Future<AppAuthSession?> restoreSession() async =>
      const AppAuthSession(userId: 'u1', email: 'u1@example.com');

  @override
  Stream<AppAuthSession?> watchSession() => _controller.stream;

  @override
  Future<void> signInWithOAuth(
    SignInMethod method, {
    required String redirectTo,
  }) async {}

  @override
  Future<void> sendMagicLink({
    required String email,
    required String redirectTo,
  }) async {}

  @override
  Future<void> signOut() async {
    if (emitSignedOutFirst) {
      _controller.add(null);
    }
    await revocation.future;
  }

  @override
  Future<void> deleteAccount() async {}
}

void main() {
  late _RevocationRepository repo;
  late AppAuthController controller;
  late List<Object> reported;

  setUp(() async {
    repo = _RevocationRepository();
    addTearDown(repo.dispose);
    controller = AppAuthController(repo);
    await controller.restoreSession();
    expect(controller.state.status, AppAuthStatus.signedIn);
    reported = [];
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) => reported.add(details.exception);
    addTearDown(() => FlutterError.onError = originalOnError);
  });

  test('completes at the local sign-out while the revocation never '
      'answers', () async {
    await controller.signOut().timeout(const Duration(seconds: 2));
    expect(controller.state.status, AppAuthStatus.signedOut);
  });

  test('a connectivity failure of the revocation is not reported', () async {
    await controller.signOut();
    repo.revocation.completeError(
      AuthRetryableFetchException(message: 'ClientException: offline'),
    );
    await pumpEventQueue();
    expect(reported, isEmpty);
    expect(controller.state.status, AppAuthStatus.signedOut);
  });

  test('any other revocation failure is reported once and never '
      'thrown', () async {
    await controller.signOut();
    repo.revocation.completeError(StateError('server error'));
    await pumpEventQueue();
    expect(reported, hasLength(1));
    expect(reported.single, isA<StateError>());
    expect(controller.state.status, AppAuthStatus.signedOut);
  });

  test('a failure before the signedOut event still ends signed out and is '
      'reported once', () async {
    repo.emitSignedOutFirst = false;
    final done = controller.signOut();
    repo.revocation.completeError(StateError('local storage failure'));
    await done;
    await pumpEventQueue();
    expect(controller.state.status, AppAuthStatus.signedOut);
    expect(reported, hasLength(1));
  });

  test('a revocation result after a new sign-in does not touch the new '
      'user\'s state', () async {
    await controller.signOut();
    repo.emit(const AppAuthSession(userId: 'u2', email: 'u2@example.com'));
    await pumpEventQueue();
    expect(controller.state.status, AppAuthStatus.signedIn);

    repo.revocation.completeError(
      AuthRetryableFetchException(message: 'ClientException: offline'),
    );
    await pumpEventQueue();
    expect(controller.state.status, AppAuthStatus.signedIn);
    expect(controller.state.currentUserId, 'u2');
    expect(reported, isEmpty);
  });
}
