import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lyron_app/src/application/auth/app_auth_controller.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/domain/auth/app_auth_status.dart';
import 'package:lyron_app/src/presentation/auth/sign_in_screen.dart';
import 'package:lyron_app/src/presentation/planning/plan_list_screen.dart';
import 'package:lyron_app/src/presentation/song_library/song_list_screen.dart';
import 'package:lyron_app/src/router/app_routes.dart';
import 'package:lyron_app/src/router/auth_router_refresh_notifier.dart';
import 'package:lyron_app/src/router/slug_route_resolvers.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

GoRouter createAppRouter({
  required AppAuthController authController,
  required Listenable refreshListenable,
  String initialLocation = '/',
}) {
  GoRouter.optionURLReflectsImperativeAPIs = true;

  return GoRouter(
    initialLocation: initialLocation,
    refreshListenable: refreshListenable,
    redirect: (context, state) {
      final isOnBootstrap = state.matchedLocation == AppRoutes.bootstrap.path;
      final isOnSignIn = state.matchedLocation == AppRoutes.signIn.path;
      final status = authController.state.status;
      final restoreTarget = state.uri.queryParameters['from'];

      if (status == AppAuthStatus.initializing) {
        if (isOnBootstrap) {
          return null;
        }

        final preserveLocation = !isOnSignIn;
        return Uri(
          path: AppRoutes.bootstrap.path,
          queryParameters: preserveLocation
              ? {'from': state.uri.toString()}
              : null,
        ).toString();
      }

      if (status == AppAuthStatus.signedIn) {
        return isOnSignIn || isOnBootstrap
            ? (restoreTarget ?? AppRoutes.home.path)
            : null;
      }

      if (isOnBootstrap) {
        return AppRoutes.signIn.path;
      }

      final requiresAuth =
          state.matchedLocation == AppRoutes.home.path ||
          state.matchedLocation == AppRoutes.planList.path ||
          state.matchedLocation.startsWith('/plans/') ||
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
        path: AppRoutes.planList.path,
        builder: (context, state) => const PlanListScreen(),
      ),
      GoRoute(
        path: AppRoutes.planDetail.path,
        builder: (context, state) =>
            PlanSlugRouteResolver(planSlug: state.pathParameters['planSlug']!),
      ),
      GoRoute(
        path: AppRoutes.planSessionSongReader.path,
        builder: (context, state) => PlanSessionSongSlugRouteResolver(
          planSlug: state.pathParameters['planSlug']!,
          sessionSlug: state.pathParameters['sessionSlug']!,
          sessionItemId: state.pathParameters['sessionItemId']!,
          songSlug: state.pathParameters['songSlug']!,
        ),
      ),
      GoRoute(
        path: AppRoutes.songReader.path,
        builder: (context, state) =>
            SongSlugRouteResolver(songSlug: state.pathParameters['songSlug']!),
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
