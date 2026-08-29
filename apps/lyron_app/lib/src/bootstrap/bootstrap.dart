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

  if (sentryConfig.isEnabled) {
    try {
      // Deliberately no `appRunner`: Sentry's `appRunner` pattern runs the
      // given closure inside its own `runZonedGuarded` zone, whose `onError`
      // silently absorbs any exception the closure throws (reported to
      // Sentry, if reachable, but never rethrown to this call site) -- see
      // RunZonedGuardedIntegration.call in the installed SDK. That is the
      // right behavior for genuinely optional app code, but Supabase.
      // initialize() below is a hard dependency: if it throws, there is no
      // working backend and the app cannot function. Running it as an
      // appRunner would turn that failure into a silent, un-rendered blank
      // screen (runApp() never reached, nothing thrown, nothing visible)
      // instead of the loud, debuggable failure it was before this slice
      // introduced Sentry. Calling SentryFlutter.init without appRunner
      // still installs its global FlutterError.onError/PlatformDispatcher.
      // onError hooks (those are set up regardless), so an unhandled error
      // later is still reported to Sentry -- it just does not swallow a
      // Supabase.initialize failure into invisibility.
      await SentryFlutter.init((options) {
        options.dsn = sentryConfig.dsn;
        options.environment = sentryConfig.environment;
        options.tracesSampleRate = 1.0;
        options.sendDefaultPii = false;
      });
    } catch (error, stackTrace) {
      // Telemetry must fail soft (see SentryConfig's doc comment and
      // ADR-036 point 5): a bad SENTRY_DSN throws out of SentryFlutter.
      // init's internal setup. Sentry's own static API (Sentry.
      // captureException et al.) already no-ops safely when the SDK never
      // finished initializing -- no need to repoint `observability` at
      // NoopObservability here. We only need to make sure the app still
      // starts, which happens unconditionally below regardless of this
      // catch firing.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'bootstrap',
          context: ErrorDescription(
            'while initializing Sentry; continuing without telemetry',
          ),
        ),
      );
    }
  }

  final supabaseConfig = SupabaseConfig.fromEnvironment();
  // supabase_flutter 2.16 deprecated anonKey in favour of publishableKey;
  // both feed the same effective key, so the legacy anon JWT keeps working.
  // The SUPABASE_ANON_KEY dart-define keeps its name — that is an
  // environment contract shared with the scripts and CI, not something to
  // rename inside a dependency bump.
  await Supabase.initialize(
    url: supabaseConfig.url,
    publishableKey: supabaseConfig.anonKey,
    httpClient: TracingHttpClient(http.Client(), observability),
  );
  runApp(const _BootstrapScope(child: LyronApp()));
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
