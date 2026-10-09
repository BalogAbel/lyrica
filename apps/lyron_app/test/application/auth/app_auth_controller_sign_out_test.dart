import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/app_auth_controller.dart';
import 'package:lyron_app/src/application/auth/auth_repository.dart';
import 'package:lyron_app/src/application/auth/last_known_identity.dart';
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
  int signOutCalls = 0;

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
    signOutCalls += 1;
    if (emitSignedOutFirst) {
      _controller.add(null);
    }
    await revocation.future;
  }

  @override
  Future<void> deleteAccount() async {}
}

/// Holds one identity, so a null session maps by the real rules (D2): to
/// sessionExpired when the app did not initiate a sign-out, to signedOut only
/// while a sign-out is in flight.
class _FakeLastKnownIdentityStore implements LastKnownIdentityStore {
  _FakeLastKnownIdentityStore(this.value);

  LastKnownIdentity? value;

  @override
  Future<LastKnownIdentity?> read() async => value;

  @override
  Future<void> write(LastKnownIdentity identity) async {
    value = identity;
  }

  @override
  Future<void> clear() async {
    value = null;
  }

  @override
  Future<EmptyMembershipResolutionOutcome> resolveEmptyMembership({
    required String userId,
  }) async => const EmptyMembershipResolutionIgnored();

  @override
  Future<bool> clearMembershipRevocation({required String userId}) async =>
      false;

  @override
  Future<bool> hasCurrentMembershipRevocationMarker({
    required String userId,
    required DateTime markedAt,
  }) async => false;
}

/// A repository whose signOut throws synchronously (a non-async method), the
/// way a failure before the first await of the real call would.
class _SyncThrowRepository extends _RevocationRepository {
  @override
  Future<void> signOut() {
    signOutCalls += 1;
    throw StateError('sync failure');
  }
}

/// deleteAccount stays in flight until [deletion] completes, so a test can land
/// another auth event while the RPC is running.
class _GatedDeleteRepository extends _RevocationRepository {
  final deletion = Completer<void>();
  int deleteAccountCalls = 0;

  @override
  Future<void> deleteAccount() {
    deleteAccountCalls += 1;
    return deletion.future;
  }
}

void main() {
  late _RevocationRepository repo;
  late AppAuthController controller;
  late List<Object> reported;

  Future<void> start(
    _RevocationRepository repository, {
    LastKnownIdentityStore? identityStore,
  }) async {
    repo = repository;
    addTearDown(repo.dispose);
    controller = AppAuthController(repo, lastKnownIdentityStore: identityStore);
    await controller.restoreSession();
    expect(controller.state.status, AppAuthStatus.signedIn);
    reported = [];
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) => reported.add(details.exception);
    addTearDown(() => FlutterError.onError = originalOnError);
  }

  setUp(() => start(_RevocationRepository()));

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

  test('overlapping calls join the one in flight and call the repository '
      'once', () async {
    final first = controller.signOut();
    final second = controller.signOut();
    await Future.wait([first, second]).timeout(const Duration(seconds: 2));
    expect(repo.signOutCalls, 1);
    expect(controller.state.status, AppAuthStatus.signedOut);
    repo.revocation.complete();
    await pumpEventQueue();
    expect(reported, isEmpty);
  });

  test('a newer sign-in before the local sign-out is not overwritten by the '
      'completion of this sign-out', () async {
    repo.emitSignedOutFirst = false;
    final done = controller.signOut();
    repo.emit(const AppAuthSession(userId: 'u2', email: 'u2@example.com'));
    await pumpEventQueue();
    expect(controller.state.status, AppAuthStatus.signedIn);

    repo.revocation.completeError(
      AuthRetryableFetchException(message: 'ClientException: offline'),
    );
    await done;
    await pumpEventQueue();
    expect(controller.state.status, AppAuthStatus.signedIn);
    expect(controller.state.currentUserId, 'u2');
    expect(reported, isEmpty);
  });

  group('deleteAccount', () {
    late _GatedDeleteRepository gated;

    setUp(() async {
      gated = _GatedDeleteRepository();
      await start(gated);
    });

    test('ends signed out when no other auth event landed during the '
        'RPC', () async {
      final done = controller.deleteAccount();
      await pumpEventQueue();
      gated.deletion.complete();
      await done;
      expect(gated.deleteAccountCalls, 1);
      expect(controller.state.status, AppAuthStatus.signedOut);
    });

    test('does not overwrite another user\'s sign-in that landed during the '
        'RPC (SO8)', () async {
      final done = controller.deleteAccount();
      gated.emit(const AppAuthSession(userId: 'u2', email: 'u2@example.com'));
      await pumpEventQueue();
      expect(controller.state.status, AppAuthStatus.signedIn);
      expect(controller.state.currentUserId, 'u2');

      gated.deletion.complete();
      await done;
      await pumpEventQueue();
      expect(controller.state.status, AppAuthStatus.signedIn);
      expect(controller.state.currentUserId, 'u2');
    });
  });

  group('a synchronous throw of the repository call', () {
    setUp(() async {
      await start(
        _SyncThrowRepository(),
        identityStore: _FakeLastKnownIdentityStore(
          const LastKnownIdentity(
            userId: 'u3',
            email: 'u3@example.com',
            organizationId: null,
          ),
        ),
      );
    });

    test('is a handled revocation failure: signs out, reported once, and '
        'does not stay in the signing-out mode', () async {
      await controller.signOut().timeout(const Duration(seconds: 2));
      await pumpEventQueue();
      expect(controller.state.status, AppAuthStatus.signedOut);
      expect(reported, hasLength(1));
      expect(reported.single, isA<StateError>());

      // _isSigningOut was reset: u3 signs in and later loses the session. With
      // u3's identity on file that is sessionExpired (D2); a stuck signing-out
      // flag would map the null session to signedOut.
      repo.emit(const AppAuthSession(userId: 'u3', email: 'u3@example.com'));
      await pumpEventQueue();
      expect(controller.state.status, AppAuthStatus.signedIn);
      repo.emit(null);
      await pumpEventQueue();
      expect(controller.state.status, AppAuthStatus.sessionExpired);
      expect(controller.state.currentUserId, 'u3');
    });
  });
}
