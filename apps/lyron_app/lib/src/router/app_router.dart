import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lyron_app/src/application/auth/app_auth_controller.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/domain/auth/app_auth_status.dart';
import 'package:lyron_app/src/presentation/account/account_screen.dart';
import 'package:lyron_app/src/presentation/auth/invite_required_screen.dart';
import 'package:lyron_app/src/presentation/auth/magic_link_sent_screen.dart';
import 'package:lyron_app/src/presentation/auth/membership_gate.dart';
import 'package:lyron_app/src/presentation/auth/redeem_progress_screen.dart';
import 'package:lyron_app/src/presentation/auth/sign_in_screen.dart';
import 'package:lyron_app/src/presentation/planning/plan_list_screen.dart';
import 'package:lyron_app/src/presentation/song_editor/song_editor_screen.dart';
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
      final loc = state.matchedLocation;
      final isOnBootstrap = loc == AppRoutes.bootstrap.path;
      final isOnSignIn = loc == AppRoutes.signIn.path;
      // Public routes are accessible without authentication.
      // Everything else requires sign-in.
      final isPublicRoute =
          isOnSignIn ||
          isOnBootstrap ||
          loc == AppRoutes.invite.path ||
          loc == AppRoutes.magicLinkSent.path;
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

      if (!isPublicRoute) {
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
        builder: (context, state) =>
            const MembershipGate(child: SongListScreen()),
      ),
      GoRoute(
        path: AppRoutes.magicLinkSent.path,
        builder: (context, _) => const MagicLinkSentScreen(),
      ),
      GoRoute(
        path: AppRoutes.invite.path,
        builder: (context, state) {
          final token = state.uri.queryParameters['token'];
          if (token != null && token.isNotEmpty) {
            return _InviteLandingCapture(token: token);
          }
          return const SignInScreen();
        },
      ),
      GoRoute(
        path: AppRoutes.inviteRequired.path,
        builder: (context, _) => const InviteRequiredScreen(),
      ),
      GoRoute(
        path: AppRoutes.redeem.path,
        builder: (context, _) => const RedeemProgressScreen(),
      ),
      GoRoute(
        path: AppRoutes.account.path,
        builder: (context, _) => const AccountScreen(),
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
          songSlug: state.pathParameters['songSlug']!,
        ),
      ),
      GoRoute(
        path: AppRoutes.songCreate.path,
        builder: (context, state) => const SongEditorScreen.create(),
      ),
      GoRoute(
        path: AppRoutes.songReader.path,
        builder: (context, state) =>
            SongSlugRouteResolver(songSlug: state.pathParameters['songSlug']!),
      ),
      GoRoute(
        path: AppRoutes.songEditor.path,
        builder: (context, state) => SongEditorSlugRouteResolver(
          songSlug: state.pathParameters['songSlug']!,
        ),
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

class _InviteLandingCapture extends ConsumerStatefulWidget {
  const _InviteLandingCapture({required this.token});
  final String token;

  @override
  ConsumerState<_InviteLandingCapture> createState() =>
      _InviteLandingCaptureState();
}

class _InviteLandingCaptureState extends ConsumerState<_InviteLandingCapture> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(pendingInviteTokenControllerProvider).capture(widget.token);
    });
  }

  @override
  Widget build(BuildContext context) {
    return const SignInScreen();
  }
}
