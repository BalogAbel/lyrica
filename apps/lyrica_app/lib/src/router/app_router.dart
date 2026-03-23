import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lyrica_app/src/application/auth/app_auth_controller.dart';
import 'package:lyrica_app/src/application/providers.dart';
import 'package:lyrica_app/src/domain/auth/app_auth_status.dart';
import 'package:lyrica_app/src/presentation/auth/sign_in_screen.dart';
import 'package:lyrica_app/src/presentation/song_library/song_list_screen.dart';
import 'package:lyrica_app/src/presentation/song_reader/song_reader_screen.dart';
import 'package:lyrica_app/src/router/app_routes.dart';
import 'package:lyrica_app/src/router/auth_router_refresh_notifier.dart';
import 'package:lyrica_app/src/shared/app_strings.dart';

GoRouter createAppRouter({
  required AppAuthController authController,
  required Listenable refreshListenable,
  String initialLocation = '/',
}) {
  return GoRouter(
    initialLocation: initialLocation,
    refreshListenable: refreshListenable,
    redirect: (context, state) {
      final isOnBootstrap = state.matchedLocation == AppRoutes.bootstrap.path;
      final isOnSignIn = state.matchedLocation == AppRoutes.signIn.path;
      final status = authController.state.status;

      if (status == AppAuthStatus.initializing) {
        return isOnBootstrap ? null : AppRoutes.bootstrap.path;
      }

      if (status == AppAuthStatus.signedIn) {
        return isOnSignIn || isOnBootstrap ? AppRoutes.home.path : null;
      }

      if (isOnBootstrap) {
        return AppRoutes.signIn.path;
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
        path: AppRoutes.bootstrap.path,
        builder: (context, state) => const Scaffold(
          body: SafeArea(
            child: Center(child: Text(AppStrings.restoringSessionMessage)),
          ),
        ),
      ),
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
