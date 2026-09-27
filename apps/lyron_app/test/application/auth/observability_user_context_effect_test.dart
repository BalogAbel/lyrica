import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/app_auth_controller.dart';
import 'package:lyron_app/src/application/auth/auth_repository.dart';
import 'package:lyron_app/src/application/auth/last_known_identity.dart';
import 'package:lyron_app/src/application/observability/observability.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/auth/app_auth_status.dart';
import 'package:lyron_app/src/domain/auth/sign_in_method.dart';

void main() {
  late _FakeAuthRepository authRepository;
  late AppAuthController authController;

  setUp(() {
    authRepository = _FakeAuthRepository();
    addTearDown(authRepository.dispose);
    authController = AppAuthController(authRepository);
  });

  test('signedIn attaches the pseudonymized user id', () async {
    final recorder = _RecordingObservability();
    authRepository.currentSession = const AppAuthSession(
      userId: 'user-1',
      email: 'user@example.com',
    );
    final container = ProviderContainer(
      overrides: [
        appAuthControllerProvider.overrideWith((_) => authController),
        observabilityProvider.overrideWithValue(recorder),
      ],
    );
    addTearDown(container.dispose);

    container.read(observabilityUserContextEffectProvider);
    await authController.restoreSession();
    await Future<void>.delayed(Duration.zero);

    expect(recorder.calls, ['set:user-1']);
  });

  test('signedOut clears the user context', () async {
    final recorder = _RecordingObservability();
    authRepository.currentSession = const AppAuthSession(
      userId: 'user-1',
      email: 'user@example.com',
    );
    final container = ProviderContainer(
      overrides: [
        appAuthControllerProvider.overrideWith((_) => authController),
        observabilityProvider.overrideWithValue(recorder),
      ],
    );
    addTearDown(container.dispose);

    container.read(observabilityUserContextEffectProvider);
    await authController.restoreSession();
    await Future<void>.delayed(Duration.zero);
    expect(recorder.calls, ['set:user-1']);

    await authController.signOut();
    await Future<void>.delayed(Duration.zero);

    expect(recorder.calls, ['set:user-1', 'clear']);
  });

  group('transitions and fireImmediately', () {
    const userA = AppAuthSession(userId: 'user-a', email: 'a@example.com');
    const userB = AppAuthSession(userId: 'user-b', email: 'b@example.com');

    late _RecordingObservability recorder;

    ProviderContainer buildContainer() {
      recorder = _RecordingObservability();
      final container = ProviderContainer(
        overrides: [
          appAuthControllerProvider.overrideWith((_) => authController),
          observabilityProvider.overrideWithValue(recorder),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    Future<void> pump() async {
      for (var i = 0; i < 4; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test('already signedIn before the provider is first read: '
        'setUserContext fires immediately with that user id', () async {
      authRepository.currentSession = userA;
      await authController.restoreSession();
      expect(authController.state.status, AppAuthStatus.signedIn);
      final container = buildContainer();

      container.read(observabilityUserContextEffectProvider);

      // No pump: fireImmediately must call synchronously.
      expect(recorder.calls, ['set:user-a']);
      await pump();
      expect(recorder.calls, ['set:user-a']);
    });

    test('still initializing when the provider is first read: neither set nor '
        'clear is called', () async {
      expect(authController.state.status, AppAuthStatus.initializing);
      final container = buildContainer();

      container.read(observabilityUserContextEffectProvider);
      await pump();

      expect(authController.state.status, AppAuthStatus.initializing);
      expect(recorder.calls, isEmpty);
    });

    test('sessionExpired is a deliberate no-op: no clear and no further set '
        'after signedIn -> sessionExpired', () async {
      // A null session only maps to sessionExpired (not signedOut) when the
      // controller has a persisted identity to protect (D2).
      final identityStore = _SeededIdentityStore(
        const LastKnownIdentity(
          userId: 'user-a',
          email: 'a@example.com',
          organizationId: 'org-1',
        ),
      );
      authController = AppAuthController(
        authRepository,
        lastKnownIdentityStore: identityStore,
      );
      authRepository.currentSession = userA;
      final container = buildContainer();

      container.read(observabilityUserContextEffectProvider);
      await authController.restoreSession();
      await pump();
      expect(recorder.calls, ['set:user-a']);

      authRepository.emit(null);
      await pump();

      expect(authController.state.status, AppAuthStatus.sessionExpired);
      expect(recorder.calls, ['set:user-a']);
      expect(recorder.clearCount, 0);
      expect(recorder.setCount, 1);
    });

    test('signedIn(A) -> signedIn(B) with no signedOut in between: set is '
        'called again with B and clear is never called', () async {
      authRepository.currentSession = userA;
      final container = buildContainer();

      container.read(observabilityUserContextEffectProvider);
      await authController.restoreSession();
      await pump();
      expect(recorder.calls, ['set:user-a']);

      // The controller maps a non-null stream event straight to signedIn(B);
      // it does not pass through signedOut.
      authRepository.emit(userB);
      await pump();

      expect(authController.state.status, AppAuthStatus.signedIn);
      expect(authController.state.session?.userId, 'user-b');
      expect(recorder.calls, ['set:user-a', 'set:user-b']);
      expect(recorder.clearCount, 0);
    });

    test('signedIn(A) -> signedOut -> signedIn(B): clear then set, order '
        'preserved', () async {
      authRepository.currentSession = userA;
      final container = buildContainer();

      container.read(observabilityUserContextEffectProvider);
      await authController.restoreSession();
      await pump();
      await authController.signOut();
      await pump();
      authRepository.emit(userB);
      await pump();

      expect(authController.state.status, AppAuthStatus.signedIn);
      expect(recorder.calls, ['set:user-a', 'clear', 'set:user-b']);
    });
  });
}

/// Records every user-context call in arrival order as `set:<userId>` /
/// `clear`. organizationId is deliberately not recorded: its cross-user
/// staleness is a documented, deferred issue and is not asserted here.
class _RecordingObservability extends NoopObservability {
  final List<String> calls = <String>[];

  int get setCount => calls.where((c) => c.startsWith('set:')).length;
  int get clearCount => calls.where((c) => c == 'clear').length;

  @override
  void setUserContext({required String userId, String? organizationId}) {
    calls.add('set:$userId');
  }

  @override
  void clearUserContext() {
    calls.add('clear');
  }
}

/// Read-only identity store: only [read] is used by [AppAuthController].
class _SeededIdentityStore implements LastKnownIdentityStore {
  _SeededIdentityStore(this._identity);

  final LastKnownIdentity? _identity;

  @override
  Future<LastKnownIdentity?> read() async => _identity;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not used by test');
}

// Minimal fake covering every method on the real AuthRepository interface,
// copied in shape from the equivalent fake in
// test/application/auth/identity_persistence_wiring_test.dart -- kept
// local (not shared) per this codebase's existing convention of one
// private test-double class per test file rather than a shared fakes
// module.
class _FakeAuthRepository implements AuthRepository {
  final _controller = StreamController<AppAuthSession?>.broadcast();
  AppAuthSession? currentSession;

  void dispose() {
    _controller.close();
  }

  @override
  Future<AppAuthSession?> restoreSession() async => currentSession;

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
    currentSession = null;
    _controller.add(null);
  }

  @override
  Future<void> deleteAccount() async {}

  void emit(AppAuthSession? session) => _controller.add(session);
}
