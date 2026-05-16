// ignore_for_file: subtype_of_sealed_class
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/app_auth_controller.dart';
import 'package:lyron_app/src/application/auth/auth_repository.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/auth/sign_in_method.dart';
import 'package:lyron_app/src/presentation/account/account_screen.dart';

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
  bool deleted = false;
  bool signedOut = false;

  @override
  Future<void> deleteAccount() async {
    deleted = true;
  }

  @override
  Future<void> signOut() async {
    signedOut = true;
  }
}

void main() {
  testWidgets('delete confirmation triggers deleteAccount', (tester) async {
    final controller = _RecordingController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appAuthControllerProvider.overrideWith((_) => controller)],
        child: const MaterialApp(home: AccountScreen()),
      ),
    );

    await tester.tap(find.text('Delete account'));
    await tester.pump();
    await tester.tap(find.text('Delete permanently'));
    await tester.pumpAndSettle();

    expect(controller.deleted, isTrue);
  });
}
