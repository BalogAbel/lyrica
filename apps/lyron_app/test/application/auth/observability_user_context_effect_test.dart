import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/app_auth_controller.dart';
import 'package:lyron_app/src/application/auth/auth_repository.dart';
import 'package:lyron_app/src/application/observability/observability.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
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

    expect(recorder.lastUserId, 'user-1');
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
    expect(recorder.lastUserId, 'user-1');

    await authController.signOut();
    await Future<void>.delayed(Duration.zero);

    expect(recorder.userContextCleared, isTrue);
  });
}

class _RecordingObservability extends NoopObservability {
  String? lastUserId;
  bool userContextCleared = false;

  @override
  void setUserContext({required String userId, String? organizationId}) {
    lastUserId = userId;
  }

  @override
  void clearUserContext() {
    userContextCleared = true;
  }
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
}
