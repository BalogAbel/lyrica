import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lyron_app/src/app/app_theme.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/presentation/auth/reauth_prompt_host.dart';
import 'package:lyron_app/src/router/app_router.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

class LyronApp extends ConsumerStatefulWidget {
  const LyronApp({super.key, this._router});

  final GoRouter? _router;

  @override
  ConsumerState<LyronApp> createState() => _LyronAppState();
}

class _LyronAppState extends ConsumerState<LyronApp> {
  @override
  void initState() {
    super.initState();
    ref.read(deepLinkListenerProvider).start();
    ref.read(membershipRefreshEffectProvider);
    ref.read(planningSyncControllerProvider);
  }

  @override
  Widget build(BuildContext context) {
    final router = widget._router ?? ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: AppStrings.appName,
      theme: buildAppTheme(),
      routerConfig: router,
      builder: (context, child) =>
          ReauthPromptHost(child: child ?? const SizedBox.shrink()),
    );
  }
}
