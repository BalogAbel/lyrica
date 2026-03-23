import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lyrica_app/src/app/app_theme.dart';
import 'package:lyrica_app/src/presentation/home/home_screen.dart';
import 'package:lyrica_app/src/presentation/song_library/song_list_screen.dart';
import 'package:lyrica_app/src/router/app_routes.dart';
import 'package:lyrica_app/src/shared/app_strings.dart';

class LyricaApp extends StatelessWidget {
  LyricaApp({super.key, GoRouter? router}) : _router = router ?? _buildRouter();

  final GoRouter _router;

  static GoRouter _buildRouter() {
    return GoRouter(
      routes: [
        GoRoute(
          path: AppRoutes.home.path,
          builder: (context, state) => const SongListScreen(),
        ),
        GoRoute(
          path: AppRoutes.songReader.path,
          builder: (context, state) => const HomeScreen(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: AppStrings.appName,
      theme: buildAppTheme(),
      routerConfig: _router,
    );
  }
}
