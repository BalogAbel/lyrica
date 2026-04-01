import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/app_auth_controller.dart';
import 'package:lyron_app/src/application/auth/auth_repository.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/presentation/auth/sign_in_screen.dart';

void main() {
  testWidgets('shows the sign-in form and submits credentials', (tester) async {
    final repository = _StubAuthRepository();
    final controller = AppAuthController(repository);
    await controller.restoreSession();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(repository),
          appAuthControllerProvider.overrideWithValue(controller),
          appAuthListenableProvider.overrideWithValue(controller),
        ],
        child: const MaterialApp(home: SignInScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Sign in'), findsOneWidget);

    await tester.enterText(
      find.byType(TextFormField).at(0),
      'demo@lyron.local',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'LyricaDemo123!');
    await tester.tap(find.text('Continue'));
    await tester.pump();

    expect(repository.lastEmail, 'demo@lyron.local');
    expect(repository.lastPassword, 'LyricaDemo123!');
  });
}

class _StubAuthRepository implements AuthRepository {
  String? lastEmail;
  String? lastPassword;

  @override
  Future<AppAuthSession?> restoreSession() async => null;

  @override
  Stream<AppAuthSession?> watchSession() => const Stream.empty();

  @override
  Future<AppAuthSession> signIn({
    required String email,
    required String password,
  }) async {
    lastEmail = email;
    lastPassword = password;
    return AppAuthSession(userId: 'user-1', email: email);
  }

  @override
  Future<void> signOut() async {}
}
