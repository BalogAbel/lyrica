import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lyrica_app/src/app/app_theme.dart';
import 'package:lyrica_app/src/router/app_router.dart';
import 'package:lyrica_app/src/shared/app_strings.dart';

class LyricaApp extends StatelessWidget {
  LyricaApp({super.key, GoRouter? router}) : _router = router ?? appRouter;

  final GoRouter _router;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: AppStrings.appName,
      theme: buildAppTheme(),
      routerConfig: _router,
    );
  }
}
