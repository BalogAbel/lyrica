// ignore_for_file: subtype_of_sealed_class
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lyron_app/src/application/auth/app_auth_controller.dart';
import 'package:lyron_app/src/application/auth/app_auth_state.dart';
import 'package:lyron_app/src/application/auth/auth_repository.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/auth/app_auth_status.dart';
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
  _RecordingController({required this.testState}) : super(_StubRepo());

  final AppAuthState testState;
  SignInMethod? lastOAuth;
  String? lastMagicLinkEmail;

  @override
  AppAuthState get state => testState;

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
    final controller = _RecordingController(
      testState: const AppAuthState(status: AppAuthStatus.signedOut),
    );
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
    final controller = _RecordingController(
      testState: const AppAuthState(status: AppAuthStatus.signedOut),
    );
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

    final controller = _RecordingController(
      testState: const AppAuthState(status: AppAuthStatus.signedOut),
    );
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

  testWidgets('sessionExpired shows Continue offline button', (tester) async {
    final controller = _RecordingController(
      testState: const AppAuthState(status: AppAuthStatus.sessionExpired),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appAuthControllerProvider.overrideWith((_) => controller)],
        child: const MaterialApp(home: SignInScreen()),
      ),
    );

    expect(find.text('Continue offline'), findsOneWidget);
  });

  testWidgets('signedOut does not show Continue offline button', (
    tester,
  ) async {
    final controller = _RecordingController(
      testState: const AppAuthState(status: AppAuthStatus.signedOut),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appAuthControllerProvider.overrideWith((_) => controller)],
        child: const MaterialApp(home: SignInScreen()),
      ),
    );

    expect(find.text('Continue offline'), findsNothing);
  });

  testWidgets(
    'sessionExpired with from param navigates to that route when Continue offline is tapped',
    (tester) async {
      GoRouter.optionURLReflectsImperativeAPIs = true;

      final controller = _RecordingController(
        testState: const AppAuthState(status: AppAuthStatus.sessionExpired),
      );

      final router = GoRouter(
        initialLocation: '/sign-in?from=/plans/team-rehearsal',
        routes: [
          GoRoute(
            path: '/sign-in',
            builder: (context, state) => SignInScreen(),
          ),
          GoRoute(
            path: '/plans/:planSlug',
            builder: (context, state) =>
                const Scaffold(body: Text('Plan Detail')),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appAuthControllerProvider.overrideWith((_) => controller),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Continue offline'), findsOneWidget);

      await tester.tap(find.text('Continue offline'));
      await tester.pumpAndSettle();

      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        '/plans/team-rehearsal',
      );
    },
  );

  testWidgets(
    'sessionExpired without from param navigates to home when Continue offline is tapped',
    (tester) async {
      GoRouter.optionURLReflectsImperativeAPIs = true;

      final controller = _RecordingController(
        testState: const AppAuthState(status: AppAuthStatus.sessionExpired),
      );

      final router = GoRouter(
        initialLocation: '/sign-in',
        routes: [
          GoRoute(
            path: '/sign-in',
            builder: (context, state) => SignInScreen(),
          ),
          GoRoute(
            path: '/',
            builder: (context, state) => const Scaffold(body: Text('Home')),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appAuthControllerProvider.overrideWith((_) => controller),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Continue offline'), findsOneWidget);

      await tester.tap(find.text('Continue offline'));
      await tester.pumpAndSettle();

      expect(router.routerDelegate.currentConfiguration.uri.toString(), '/');
    },
  );
}
