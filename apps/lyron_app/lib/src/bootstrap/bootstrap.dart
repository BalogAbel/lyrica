import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:lyron_app/src/app/lyron_app.dart';
import 'package:lyron_app/src/application/observability/observability.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/infrastructure/config/sentry_config.dart';
import 'package:lyron_app/src/infrastructure/config/supabase_config.dart';
import 'package:lyron_app/src/infrastructure/observability/sentry_observability.dart';
import 'package:lyron_app/src/infrastructure/observability/tracing_http_client.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  final sentryConfig = SentryConfig.fromEnvironment();
  final observability = sentryConfig.isEnabled
      ? const SentryObservability()
      : const NoopObservability();
  setCurrentObservability(observability);

  final supabaseConfig = SupabaseConfig.fromEnvironment();

  Future<void> initSupabaseAndRun() async {
    // supabase_flutter 2.16 deprecated anonKey in favour of publishableKey;
    // both feed the same effective key, so the legacy anon JWT keeps
    // working. The SUPABASE_ANON_KEY dart-define keeps its name — that is
    // an environment contract shared with the scripts and CI, not
    // something to rename inside a dependency bump.
    await Supabase.initialize(
      url: supabaseConfig.url,
      publishableKey: supabaseConfig.anonKey,
      httpClient: TracingHttpClient(http.Client(), observability),
    );
    runApp(const _BootstrapScope(child: LyronApp()));
  }

  if (sentryConfig.isEnabled) {
    await SentryFlutter.init((options) {
      options.dsn = sentryConfig.dsn;
      options.environment = sentryConfig.environment;
      options.tracesSampleRate = 1.0;
      options.sendDefaultPii = false;
    }, appRunner: initSupabaseAndRun);
  } else {
    await initSupabaseAndRun();
  }
}

class _BootstrapScope extends StatefulWidget {
  const _BootstrapScope({required this.child});

  final Widget child;

  @override
  State<_BootstrapScope> createState() => _BootstrapScopeState();
}

class _BootstrapScopeState extends State<_BootstrapScope> {
  @override
  void dispose() {
    unawaited(
      closeSharedDatabases().catchError((Object error, StackTrace stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'bootstrap',
            context: ErrorDescription('while closing shared drift databases'),
          ),
        );
      }),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ProviderScope(child: widget.child);
  }
}
