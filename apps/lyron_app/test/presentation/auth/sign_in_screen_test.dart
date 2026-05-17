// ignore_for_file: subtype_of_sealed_class
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/app_auth_controller.dart';
import 'package:lyron_app/src/application/auth/auth_repository.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/auth/sign_in_method.dart';
import 'package:lyron_app/src/presentation/auth/sign_in_screen.dart';

class _StubRepo implements AuthRepository {
  @override
  Future<AppAuthSession?> restoreSession() async => null;
  @override
  Stream<AppAuthSession?> watchSession() => const Stream.empty();
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
  Future<void> signOut() async {}
  @override
  Future<void> deleteAccount() async {}
}

class _RecordingController extends AppAuthController {
  _RecordingController() : super(_StubRepo());
  SignInMethod? lastOAuth;
  String? lastMagicLinkEmail;

  @override
  Future<void> signInWithOAuth(
    SignInMethod method, {
    required String redirectTo,
  }) async {
    lastOAuth = method;
  }

  @override
  Future<void> sendMagicLink({
    required String email,
    required String redirectTo,
  }) async {
    lastMagicLinkEmail = email;
  }
}

void main() {
  testWidgets('shows three sign-in entry points', (tester) async {
    final controller = _RecordingController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appAuthControllerProvider.overrideWith((_) => controller)],
        child: const MaterialApp(home: SignInScreen()),
      ),
    );

    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Continue with Apple'), findsOneWidget);
    expect(find.text('Send magic link'), findsOneWidget);
  });

  testWidgets('tapping Google triggers OAuth', (tester) async {
    final controller = _RecordingController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appAuthControllerProvider.overrideWith((_) => controller)],
        child: const MaterialApp(home: SignInScreen()),
      ),
    );
    await tester.tap(find.text('Continue with Google'));
    await tester.pump();
    expect(controller.lastOAuth, SignInMethod.google);
  });

  testWidgets('remains usable on a short viewport', (tester) async {
    await tester.binding.setSurfaceSize(const Size(375, 235));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = _RecordingController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appAuthControllerProvider.overrideWith((_) => controller)],
        child: const MaterialApp(home: SignInScreen()),
      ),
    );

    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Send magic link'), findsOneWidget);
  });
}
