import 'dart:async';

import 'package:flutter/foundation.dart';
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
  bool emitNullOnSignOut = false;
  Object? signOutError;
  // When set, restoreSession() awaits this instead of returning
  // currentSession immediately -- lets tests hold restoreSession() mid-flight
  // to interleave it with a concurrent stream event.
  Completer<AppAuthSession?>? restoreCompleter;

  @override
  Future<AppAuthSession?> restoreSession() async {
    final completer = restoreCompleter;
    if (completer != null) {
      return completer.future;
    }
    return currentSession;
  }

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
    // Models the real Supabase client: calling signOut() also drives the
    // auth-state-change stream to emit null as a side effect, at a time
    // relative to the caller's `await` that this fake does not pin down.
    if (emitNullOnSignOut) {
      _controller.add(null);
    }
    final error = signOutError;
    if (error != null) {
      throw error;
    }
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
  Object? readError;

  @override
  Future<LastKnownIdentity?> read() async {
    final error = readError;
    if (error != null) {
      throw error;
    }
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
      // A LastKnownIdentity matching the signed-in session must already be
      // persisted for this to stay offline-authenticated under the D2 rule
      // (a null session with no identity to protect maps to signedOut).
      final identityStore = _FakeLastKnownIdentityStore()
        ..value = const LastKnownIdentity(
          userId: 'u',
          email: 'e@x',
          organizationId: null,
        );
      final controller = AppAuthController(
        repo,
        lastKnownIdentityStore: identityStore,
      );

      repo.currentSession = const AppAuthSession(userId: 'u', email: 'e@x');
      await controller.restoreSession();

      repo.emit(null);
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.status, AppAuthStatus.sessionExpired);
      expect(controller.state.lastKnownSession?.userId, 'u');
      expect(controller.state.lastKnownSession?.email, 'e@x');
    },
  );

  test('stream null from initializing with identity present maps to '
      'sessionExpired, not signedOut', () async {
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

    // Let the identity load settle before emitting, so the event below is
    // processed immediately rather than buffered.
    await Future<void>.delayed(Duration.zero);

    // No restoreSession() call: the app never got a signedIn status, it's
    // still `initializing` when this null event lands.
    repo.emit(null);
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.status, AppAuthStatus.sessionExpired);
    expect(controller.state.lastKnownSession?.userId, 'u1');
    expect(controller.state.lastKnownSession?.email, 'e@x');
  });

  test('stream null while already sessionExpired with identity present stays '
      'sessionExpired', () async {
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
    await Future<void>.delayed(Duration.zero);

    repo.emit(null);
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.status, AppAuthStatus.sessionExpired);

    // A second, independent null event while already sessionExpired must
    // not do anything more destructive.
    repo.emit(null);
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.status, AppAuthStatus.sessionExpired);
    expect(controller.state.lastKnownSession?.userId, 'u1');
  });

  test('stream null from initializing with no identity maps to signedOut -- '
      'nothing to protect', () async {
    final repo = _FakeAuthRepository();
    final controller = AppAuthController(repo); // no identity store wired
    await Future<void>.delayed(Duration.zero);

    repo.emit(null);
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.status, AppAuthStatus.signedOut);
  });

  test('null session delivered synchronously during signOut() maps to '
      'signedOut even though an identity is present to protect', () async {
    final repo = _FakeAuthRepository()..emitNullOnSignOut = true;
    final identityStore = _FakeLastKnownIdentityStore()
      ..value = const LastKnownIdentity(
        userId: 'u1',
        email: 'e@x',
        organizationId: null,
      );
    repo.currentSession = const AppAuthSession(userId: 'u1', email: 'e@x');
    final controller = AppAuthController(
      repo,
      lastKnownIdentityStore: identityStore,
    );
    await controller.restoreSession();
    expect(controller.state.status, AppAuthStatus.signedIn);

    await controller.signOut();

    expect(controller.state.status, AppAuthStatus.signedOut);
  });

  test(
    'a null stream event arriving mid-restoreSession() cannot leave a more '
    'destructive state than the one restoreSession() itself converges on',
    () async {
      final repo = _FakeAuthRepository();
      final restoreCompleter = Completer<AppAuthSession?>();
      repo.restoreCompleter = restoreCompleter;
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

      // Let the identity load settle first so the stream event below is
      // processed immediately instead of buffered.
      await Future<void>.delayed(Duration.zero);
      expect(controller.lastKnownIdentity?.userId, 'u1');

      final restore = controller.restoreSession();
      // While restoreSession() is still awaiting the repository, the stream
      // independently emits null.
      repo.emit(null);
      await Future<void>.delayed(Duration.zero);

      // The stream's own computation (identity present, not signing out)
      // must already land on sessionExpired here -- not the old, more
      // destructive signedOut.
      expect(controller.state.status, AppAuthStatus.sessionExpired);

      restoreCompleter.complete(null);
      await restore;

      // restoreSession() finishing afterwards must not leave anything worse
      // in place either.
      expect(controller.state.status, AppAuthStatus.sessionExpired);
      expect(controller.state.lastKnownSession?.userId, 'u1');
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

  test('a stream event arriving before the identity load settles is buffered '
      'and only evaluated once the load completes -- proven by state staying '
      'untouched beforehand and a log showing the read complete strictly '
      'before the resulting notification', () async {
    final repo = _FakeAuthRepository();
    final identityRead = Completer<LastKnownIdentity?>();
    final identityStore = _FakeLastKnownIdentityStore()
      ..readCompleter = identityRead;
    final controller = AppAuthController(
      repo,
      lastKnownIdentityStore: identityStore,
    );

    final log = <Object>[];
    controller.addListener(() => log.add(controller.state.status));

    // The stream event arrives immediately, well before the identity
    // load resolves.
    repo.emit(null);
    await Future<void>.delayed(Duration.zero);

    // Not evaluated yet: state is untouched and nothing notified.
    expect(controller.state.status, AppAuthStatus.initializing);
    expect(log, isEmpty);

    log.add('read-completing');
    identityRead.complete(null);
    await Future<void>.delayed(Duration.zero);

    // Only now, after the identity load settles, is the buffered event
    // evaluated -- the log proves the read completed strictly before the
    // resulting notification, not concurrently or before.
    expect(log, ['read-completing', AppAuthStatus.signedOut]);
    expect(controller.state.status, AppAuthStatus.signedOut);
  });

  test(
    'multiple stream events arriving before the identity load settles are '
    'replayed in arrival order once the load completes, and the loaded '
    'identity becomes synchronously readable via lastKnownIdentity',
    () async {
      final repo = _FakeAuthRepository();
      final identityRead = Completer<LastKnownIdentity?>();
      final identityStore = _FakeLastKnownIdentityStore()
        ..readCompleter = identityRead;
      final controller = AppAuthController(
        repo,
        lastKnownIdentityStore: identityStore,
      );

      final log = <Object>[];
      controller.addListener(() => log.add(controller.state.status));

      // Two events arrive back-to-back before the identity load resolves:
      // a live session first, then null. Both must be buffered, not
      // dropped, and replayed in the order they arrived -- if replayed out
      // of order the resulting log would differ (signedOut, signedIn
      // instead of signedIn, sessionExpired), so this also proves ordering.
      repo.emit(const AppAuthSession(userId: 'u', email: 'e@x'));
      repo.emit(null);
      await Future<void>.delayed(Duration.zero);

      expect(log, isEmpty);
      expect(controller.lastKnownIdentity, isNull);

      const identity = LastKnownIdentity(
        userId: 'cached',
        email: 'cached@example.com',
        organizationId: null,
      );
      identityRead.complete(identity);
      await Future<void>.delayed(Duration.zero);

      expect(log, [AppAuthStatus.signedIn, AppAuthStatus.sessionExpired]);
      expect(controller.state.status, AppAuthStatus.sessionExpired);
      expect(controller.state.lastKnownSession?.userId, 'u');
      expect(controller.lastKnownIdentity, identity);
    },
  );

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

  test('cancelReauthToPriorSession signs out the new session and returns to '
      "sessionExpired carrying the PRIOR user's session -- not signedOut, and "
      'not the cancelled new user', () async {
    final repo = _FakeAuthRepository();
    repo.currentSession = const AppAuthSession(
      userId: 'u2',
      email: 'u2@example.com',
    );
    final controller = AppAuthController(repo);
    await controller.restoreSession();
    expect(controller.state.status, AppAuthStatus.signedIn);

    await controller.cancelReauthToPriorSession(
      const AppAuthSession(userId: 'u1', email: 'u1@example.com'),
    );

    expect(repo.signOutCalled, isTrue);
    expect(controller.state.status, AppAuthStatus.sessionExpired);
    expect(controller.state.session, isNull);
    expect(controller.state.lastKnownSession?.userId, 'u1');
    expect(controller.state.lastKnownSession?.email, 'u1@example.com');
  });

  test('cancelReauthToPriorSession converges on the prior session even when '
      'the auth stream also emits null as a side effect of the sign-out call '
      '-- this must not be lucky about which one wins', () async {
    final repo = _FakeAuthRepository()..emitNullOnSignOut = true;
    repo.currentSession = const AppAuthSession(
      userId: 'u2',
      email: 'u2@example.com',
    );
    final controller = AppAuthController(repo);
    await controller.restoreSession();

    await controller.cancelReauthToPriorSession(
      const AppAuthSession(userId: 'u1', email: 'u1@example.com'),
    );
    // Let any additional microtask from the stream-driven path settle.
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.status, AppAuthStatus.sessionExpired);
    expect(controller.state.lastKnownSession?.userId, 'u1');
    expect(controller.state.session, isNull);
  });

  test('cancelReauthToPriorSession stays offline-authenticated as the prior '
      "user even when the auth stream's null side effect is delivered LATE "
      '-- after the cancel call has already returned, not during its await '
      '-- because _repository.signOut() resolving does not guarantee its '
      'own stream side effect has been delivered yet', () async {
    final repo = _FakeAuthRepository();
    repo.currentSession = const AppAuthSession(
      userId: 'u2',
      email: 'u2@example.com',
    );
    final controller = AppAuthController(repo);
    await controller.restoreSession();

    await controller.cancelReauthToPriorSession(
      const AppAuthSession(userId: 'u1', email: 'u1@example.com'),
    );
    expect(controller.state.status, AppAuthStatus.sessionExpired);
    expect(controller.state.lastKnownSession?.userId, 'u1');

    // The stream's null event arrives only now -- well after
    // cancelReauthToPriorSession has returned and its `finally` has already
    // run. Falling through to the ordinary null-session mapping here would
    // read _state.status as sessionExpired (not signedIn) and return
    // signedOut, discarding lastKnownSession and the offline-authenticated
    // state cancel exists to preserve.
    repo.emit(null);
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.status, AppAuthStatus.sessionExpired);
    expect(controller.state.lastKnownSession?.userId, 'u1');
    expect(controller.state.lastKnownSession?.email, 'u1@example.com');
    expect(controller.state.session, isNull);
  });

  test('cancelReauthToPriorSession still converges to sessionExpired carrying '
      "the PRIOR user's session and reports the failure when the backend "
      'signOut() call throws -- Finding 2, PR #64 review: the state must not '
      'silently stay put', () async {
    final repo = _FakeAuthRepository()
      ..signOutError = StateError('offline: signOut unreachable');
    repo.currentSession = const AppAuthSession(
      userId: 'u2',
      email: 'u2@example.com',
    );
    final controller = AppAuthController(repo);
    await controller.restoreSession();
    expect(controller.state.status, AppAuthStatus.signedIn);

    final reportedErrors = <Object>[];
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) => reportedErrors.add(details.exception);
    addTearDown(() => FlutterError.onError = originalOnError);

    await controller.cancelReauthToPriorSession(
      const AppAuthSession(userId: 'u1', email: 'u1@example.com'),
    );

    expect(repo.signOutCalled, isTrue);
    // The state must not silently stay put -- it converges exactly as it
    // does when the backend signOut() call succeeds.
    expect(controller.state.status, AppAuthStatus.sessionExpired);
    expect(controller.state.lastKnownSession?.userId, 'u1');
    expect(controller.state.session, isNull);
    // The failure must be observable, not silently dropped.
    expect(reportedErrors, isNotEmpty);
    expect(reportedErrors.single, isA<StateError>());
  });

  test(
    'a later, unrelated null session event does not misapply the pending '
    'cancel record after a failed cancelReauthToPriorSession -- Finding 2, '
    'PR #64 review: the record must not linger able to be wrongly consumed',
    () async {
      final repo = _FakeAuthRepository()
        ..signOutError = StateError('offline: signOut unreachable');
      repo.currentSession = const AppAuthSession(
        userId: 'u2',
        email: 'u2@example.com',
      );
      final controller = AppAuthController(repo);
      await controller.restoreSession();

      final originalOnError = FlutterError.onError;
      FlutterError.onError = (_) {};
      addTearDown(() => FlutterError.onError = originalOnError);

      await controller.cancelReauthToPriorSession(
        const AppAuthSession(userId: 'u1', email: 'u1@example.com'),
      );
      expect(controller.state.status, AppAuthStatus.sessionExpired);
      expect(controller.state.lastKnownSession?.userId, 'u1');

      // A later, UNRELATED null event (nothing to do with the failed
      // cancel above) must not be misapplied via a lingering pending
      // record. State has already converged, so this must be a true no-op
      // -- not a state change driven by stale bookkeeping -- proven here by
      // asserting no listener notification fires at all.
      var notified = false;
      controller.addListener(() => notified = true);
      repo.emit(null);
      await Future<void>.delayed(Duration.zero);

      expect(notified, isFalse);
      expect(controller.state.status, AppAuthStatus.sessionExpired);
      expect(controller.state.lastKnownSession?.userId, 'u1');
    },
  );

  test('a failed identity-store read does not strand the controller in '
      'initializing forever -- it fails open to "no identity known" and '
      'still processes subsequent events', () async {
    final repo = _FakeAuthRepository();
    final identityStore = _FakeLastKnownIdentityStore()
      ..readError = StateError('disk I/O error');
    final controller = AppAuthController(
      repo,
      lastKnownIdentityStore: identityStore,
    );

    final originalOnError = FlutterError.onError;
    final reportedErrors = <Object>[];
    FlutterError.onError = (details) => reportedErrors.add(details.exception);
    addTearDown(() => FlutterError.onError = originalOnError);

    await controller.restoreSession();

    // No identity could be read, and no session was restored: nothing to
    // protect, so this correctly resolves to signedOut -- the important
    // part is that it resolves AT ALL, rather than hanging.
    expect(controller.state.status, AppAuthStatus.signedOut);
    expect(reportedErrors, isNotEmpty);

    // A subsequent live session must still be processed normally --
    // proving the buffer actually drained and the controller did not get
    // stuck treating every future event as still-loading.
    repo.emit(const AppAuthSession(userId: 'u', email: 'e@x'));
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.status, AppAuthStatus.signedIn);
    expect(controller.state.session?.userId, 'u');
  });

  test('a signedIn session that expires before its identity is durably '
      'persisted maps to signedOut, not sessionExpired -- a KNOWN, accepted '
      'gap (PR #73 review finding 4), documented here rather than fixed: '
      'making the live session in _state count as "someone to protect" '
      'independent of _identity would also make a just-purged identity '
      '(VerifiedEmptyMembershipCleanupCoordinator, still signedIn at the '
      '_state level -- it never touches _state itself) wrongly count too, '
      'reopening D1\'s purge finality. See the class-level note above '
      '_stateForSession. Practical impact of the gap this test documents is '
      'narrow: a brand-new sign-in with no durably persisted identity yet '
      'almost certainly also has no cached local data at stake.', () async {
    final repo = _FakeAuthRepository();
    repo.currentSession = const AppAuthSession(userId: 'u', email: 'e@x');
    final controller = AppAuthController(
      repo,
      lastKnownIdentityStore: _FakeLastKnownIdentityStore(),
    );
    await controller.restoreSession();
    expect(controller.state.status, AppAuthStatus.signedIn);

    repo.emit(null);
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.status, AppAuthStatus.signedOut);
  });

  test('a second consecutive null-session event while already sessionExpired '
      'reuses the lastKnownSession from the first transition, including '
      'linkedProviders, instead of re-synthesizing a poorer one from the '
      'identity cache alone', () async {
    final repo = _FakeAuthRepository();
    repo.currentSession = const AppAuthSession(
      userId: 'u',
      email: 'e@x',
      linkedProviders: ['google'],
    );
    final identityStore = _FakeLastKnownIdentityStore()
      ..value = const LastKnownIdentity(
        userId: 'u',
        email: 'e@x',
        organizationId: null,
      );
    final controller = AppAuthController(
      repo,
      lastKnownIdentityStore: identityStore,
    );
    await controller.restoreSession();

    repo.emit(null);
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.status, AppAuthStatus.sessionExpired);
    expect(controller.state.lastKnownSession?.linkedProviders, ['google']);

    // A second null event lands while already sessionExpired --
    // _state.session is null at this point (only set on signedIn), so a
    // naive implementation falls back to the identity cache alone and
    // silently drops linkedProviders.
    repo.emit(null);
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.status, AppAuthStatus.sessionExpired);
    expect(controller.state.lastKnownSession?.userId, 'u');
    expect(controller.state.lastKnownSession?.linkedProviders, ['google']);
  });

  test('signedOut is sticky against a late null-session stream event -- e.g. '
      'the auth SDK\'s own side-effect of signOut() arriving after '
      '_isSigningOut has already reset -- so a just-signed-out user is never '
      'resurrected as offline-authenticated', () async {
    final repo = _FakeAuthRepository();
    repo.currentSession = const AppAuthSession(userId: 'u', email: 'e@x');
    final identityStore = _FakeLastKnownIdentityStore()
      ..value = const LastKnownIdentity(
        userId: 'u',
        email: 'e@x',
        organizationId: null,
      );
    final controller = AppAuthController(
      repo,
      lastKnownIdentityStore: identityStore,
    );
    await controller.restoreSession();
    expect(controller.state.status, AppAuthStatus.signedIn);

    await controller.signOut();
    expect(controller.state.status, AppAuthStatus.signedOut);

    // The identity cache is deliberately NOT nulled here (nothing in
    // this controller-level test drives auth_providers.dart's reactive
    // listener) -- this is exactly the production race window: the
    // durable clear + cache update run asynchronously in reaction to the
    // signedOut state and are not guaranteed to land before a delayed
    // stream side effect of the same signOut() call arrives.
    repo.emit(null);
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.status, AppAuthStatus.signedOut);
  });
}
