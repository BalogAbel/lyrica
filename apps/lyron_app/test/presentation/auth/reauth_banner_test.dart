import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lyron_app/src/application/auth/app_auth_controller.dart';
import 'package:lyron_app/src/application/auth/auth_repository.dart';
import 'package:lyron_app/src/application/auth/last_known_identity.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/auth/sign_in_method.dart';
import 'package:lyron_app/src/presentation/auth/reauth_banner.dart';
import 'package:lyron_app/src/router/app_routes.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

class _TestAuthRepository implements AuthRepository {
  final AppAuthSession? restoredSession;

  _TestAuthRepository({this.restoredSession});

  @override
  Future<AppAuthSession?> restoreSession() async => restoredSession;

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

class _FakeLastKnownIdentityStore implements LastKnownIdentityStore {
  final LastKnownIdentity? _identity;

  _FakeLastKnownIdentityStore({LastKnownIdentity? identity})
    : _identity = identity;

  @override
  Future<LastKnownIdentity?> read() async => _identity;

  @override
  Future<void> write(LastKnownIdentity identity) async {}

  @override
  Future<void> clear() async {}
}

void main() {
  testWidgets('re-auth banner shows when sessionExpired', (tester) async {
    final fakeStore = _FakeLastKnownIdentityStore(
      identity: const LastKnownIdentity(
        userId: 'user-1',
        email: 'demo@lyron.local',
        organizationId: 'org-1',
      ),
    );
    final controller = AppAuthController(
      _TestAuthRepository(),
      lastKnownIdentityStore: fakeStore,
    );
    await controller.restoreSession();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appAuthControllerProvider.overrideWith((_) => controller)],
        child: MaterialApp.router(
          routerConfig: GoRouter(
            initialLocation: '/',
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) =>
                    const Scaffold(body: ReauthBanner()),
              ),
              GoRoute(
                path: AppRoutes.signIn.path,
                builder: (context, state) =>
                    const Scaffold(body: Text('SIGN IN SCREEN')),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text(AppStrings.reauthRequiredMessage), findsOneWidget);
  });

  testWidgets('re-auth banner hidden when signedIn', (tester) async {
    final controller = AppAuthController(
      _TestAuthRepository(
        restoredSession: const AppAuthSession(
          userId: 'user-1',
          email: 'demo@lyron.local',
        ),
      ),
    );
    await controller.restoreSession();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appAuthControllerProvider.overrideWith((_) => controller)],
        child: MaterialApp.router(
          routerConfig: GoRouter(
            initialLocation: '/',
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) =>
                    const Scaffold(body: ReauthBanner()),
              ),
              GoRoute(
                path: AppRoutes.signIn.path,
                builder: (context, state) =>
                    const Scaffold(body: Text('SIGN IN SCREEN')),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text(AppStrings.reauthRequiredMessage), findsNothing);
    expect(find.byKey(const ValueKey('reauth-banner-empty')), findsOneWidget);
  });

  testWidgets('re-auth banner action opens sign-in', (tester) async {
    final fakeStore = _FakeLastKnownIdentityStore(
      identity: const LastKnownIdentity(
        userId: 'user-1',
        email: 'demo@lyron.local',
        organizationId: 'org-1',
      ),
    );
    final controller = AppAuthController(
      _TestAuthRepository(),
      lastKnownIdentityStore: fakeStore,
    );
    await controller.restoreSession();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appAuthControllerProvider.overrideWith((_) => controller)],
        child: MaterialApp.router(
          routerConfig: GoRouter(
            initialLocation: '/',
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) =>
                    const Scaffold(body: ReauthBanner()),
              ),
              GoRoute(
                path: AppRoutes.signIn.path,
                builder: (context, state) => Scaffold(
                  body: Text(
                    'SIGN IN from=${state.uri.queryParameters['from']}',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('reauth-banner-action')));
    await tester.pumpAndSettle();

    // Action must preserve the origin location via the `from` query param so the
    // router returns the user to where they were after same-user re-auth.
    expect(find.text('SIGN IN from=/'), findsOneWidget);
  });
}
