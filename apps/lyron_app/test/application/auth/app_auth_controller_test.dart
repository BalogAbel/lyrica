import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/app_auth_controller.dart';
import 'package:lyron_app/src/application/auth/auth_repository.dart';
import 'package:lyron_app/src/application/auth/last_known_identity.dart';
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

class _FakeLastKnownIdentityStore implements LastKnownIdentityStore {
  LastKnownIdentity? value;
  Completer<LastKnownIdentity?>? readCompleter;

  @override
  Future<LastKnownIdentity?> read() async {
    final completer = readCompleter;
    if (completer != null) {
      return completer.future;
    }
    return value;
  }

  @override
  Future<void> write(LastKnownIdentity identity) async {
    value = identity;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

void main() {
  test(
    'cold start null session + persisted identity → sessionExpired',
    () async {
      final repo = _FakeAuthRepository();
      final identityStore = _FakeLastKnownIdentityStore()
        ..value = const LastKnownIdentity(
          userId: 'u1',
          email: 'e@x',
          organizationId: null,
        );
      final controller = AppAuthController(
        repo,
        lastKnownIdentityStore: identityStore,
      );

      await controller.restoreSession();

      expect(controller.state.status, AppAuthStatus.sessionExpired);
      expect(controller.state.lastKnownSession?.userId, 'u1');
      expect(controller.state.lastKnownSession?.email, 'e@x');
    },
  );

  test('cold start null session + no identity → signedOut', () async {
    final repo = _FakeAuthRepository();
    final controller = AppAuthController(
      repo,
      lastKnownIdentityStore: _FakeLastKnownIdentityStore(),
    );

    await controller.restoreSession();

    expect(controller.state.status, AppAuthStatus.signedOut);
  });

  test(
    'stream null from signedIn keeps sessionExpired with last known session',
    () async {
      final repo = _FakeAuthRepository();
      final controller = AppAuthController(repo);

      repo.currentSession = const AppAuthSession(userId: 'u', email: 'e@x');
      await controller.restoreSession();

      repo.emit(null);
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.status, AppAuthStatus.sessionExpired);
      expect(controller.state.lastKnownSession?.userId, 'u');
      expect(controller.state.lastKnownSession?.email, 'e@x');
    },
  );

  test(
    'live stream session wins over stale cold-start identity read',
    () async {
      final repo = _FakeAuthRepository();
      final identityRead = Completer<LastKnownIdentity?>();
      final identityStore = _FakeLastKnownIdentityStore()
        ..readCompleter = identityRead;
      final controller = AppAuthController(
        repo,
        lastKnownIdentityStore: identityStore,
      );

      final restore = controller.restoreSession();
      repo.emit(
        const AppAuthSession(userId: 'live', email: 'live@example.com'),
      );
      await Future<void>.delayed(Duration.zero);
      identityRead.complete(
        const LastKnownIdentity(
          userId: 'stale',
          email: 'stale@example.com',
          organizationId: null,
        ),
      );
      await restore;

      expect(controller.state.status, AppAuthStatus.signedIn);
      expect(controller.state.session?.userId, 'live');
    },
  );

  test('explicit signOut wins over stale cold-start identity read', () async {
    final repo = _FakeAuthRepository();
    final identityRead = Completer<LastKnownIdentity?>();
    final identityStore = _FakeLastKnownIdentityStore()
      ..readCompleter = identityRead;
    final controller = AppAuthController(
      repo,
      lastKnownIdentityStore: identityStore,
    );

    final restore = controller.restoreSession();
    await controller.signOut();
    identityRead.complete(
      const LastKnownIdentity(
        userId: 'stale',
        email: 'stale@example.com',
        organizationId: null,
      ),
    );
    await restore;

    expect(controller.state.status, AppAuthStatus.signedOut);
  });

  test('restoreSession surfaces signedIn when a session exists', () async {
    final repo = _FakeAuthRepository();
    repo.currentSession = const AppAuthSession(userId: 'u', email: 'e@x');
    final controller = AppAuthController(repo);

    await controller.restoreSession();

    expect(controller.state.status, AppAuthStatus.signedIn);
    expect(controller.state.session?.userId, 'u');
  });

  test('restoreSession does not notify when state is unchanged', () async {
    final repo = _FakeAuthRepository();
    repo.currentSession = const AppAuthSession(userId: 'u', email: 'e@x');
    final controller = AppAuthController(repo);
    var notifications = 0;
    controller.addListener(() => notifications += 1);

    await controller.restoreSession();
    await controller.restoreSession();

    expect(notifications, 1);
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
