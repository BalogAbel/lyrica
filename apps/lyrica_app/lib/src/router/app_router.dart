import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lyrica_app/src/application/auth/app_auth_controller.dart';
import 'package:lyrica_app/src/application/providers.dart';
import 'package:lyrica_app/src/domain/auth/app_auth_status.dart';
import 'package:lyrica_app/src/presentation/auth/sign_in_screen.dart';
import 'package:lyrica_app/src/presentation/song_library/song_list_screen.dart';
import 'package:lyrica_app/src/presentation/song_reader/song_reader_screen.dart';
import 'package:lyrica_app/src/router/auth_router_refresh_notifier.dart';
import 'package:lyrica_app/src/router/app_routes.dart';

GoRouter createAppRouter({
  required AppAuthController authController,
  required Listenable refreshListenable,
  String initialLocation = '/',
}) {
  return GoRouter(
    initialLocation: initialLocation,
    refreshListenable: refreshListenable,
    redirect: (context, state) {
      final isOnSignIn = state.matchedLocation == AppRoutes.signIn.path;
      final status = authController.state.status;

      if (status == AppAuthStatus.signedIn) {
        return isOnSignIn ? AppRoutes.home.path : null;
      }

      final requiresAuth =
          state.matchedLocation == AppRoutes.home.path ||
          state.matchedLocation.startsWith('/songs/');
      if (requiresAuth) {
        return AppRoutes.signIn.path;
      }

      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.signIn.path,
        builder: (context, state) => const SignInScreen(),
      ),
      GoRoute(
        path: AppRoutes.home.path,
        builder: (context, state) => const SongListScreen(),
      ),
      GoRoute(
        path: AppRoutes.songReader.path,
        builder: (context, state) =>
            SongReaderScreen(songId: state.pathParameters['songId']!),
      ),
    ],
  );
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final authController = ref.watch(appAuthControllerProvider);
  final refreshNotifier = AuthRouterRefreshNotifier(
    ref.watch(appAuthListenableProvider),
  );
  ref.onDispose(refreshNotifier.dispose);
  unawaited(authController.restoreSession());

  return createAppRouter(
    authController: authController,
    refreshListenable: refreshNotifier,
  );
});
