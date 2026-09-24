import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
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

/// Reports an error that escaped every other handler inside the guarded
/// bootstrap zone (see [runBootstrapGuarded]).
///
/// Always prints locally first ([dump], default
/// `FlutterError.dumpErrorToConsole`, which does NOT invoke
/// `FlutterError.onError`), so nothing is ever swallowed silently -- even
/// when Sentry is disabled or uninitialized. Then hands the error to
/// [capture] (default `Sentry.captureException`, a no-op returning
/// `SentryId.empty()` on the `NoOpHub` when Sentry is not initialized).
/// A failing [capture] is contained: telemetry must never turn a reported
/// error into a second one.
///
/// No double report: Sentry's `FlutterErrorIntegration` only sees errors
/// routed through `FlutterError.onError`, and it explicitly does not forward
/// them to `Zone.handleUncaughtError` (flutter_error_integration.dart: "we
/// don't call Zone.current.handleUncaughtError"). Errors reaching a zone
/// handler never pass through `FlutterError.onError`, and [dump] does not
/// re-enter it, so each error is captured exactly once.
void reportUncaughtZoneError(
  Object error,
  StackTrace stackTrace, {
  FutureOr<void> Function(Object error, StackTrace stackTrace)? capture,
  void Function(FlutterErrorDetails details)? dump,
}) {
  final dumpError =
      dump ??
      (FlutterErrorDetails details) =>
          FlutterError.dumpErrorToConsole(details, forceReport: true);
  final captureError =
      capture ??
      (Object e, StackTrace s) => Sentry.captureException(e, stackTrace: s);

  try {
    dumpError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'bootstrap',
        context: ErrorDescription('in the guarded bootstrap zone'),
      ),
    );
  } catch (_) {
    // Printing is best effort; still try to capture below.
  }
  unawaited(
    Future<void>.sync(
      () => captureError(error, stackTrace),
    ).then<void>((_) {}, onError: (Object _, StackTrace _) {}),
  );
}

/// Runs [body] (normally [bootstrap]) the way the Sentry SDK would, so that
/// unhandled asynchronous errors are still captured on every platform.
///
/// SDK facts (sentry_flutter 8.14.2), which this mirrors:
/// - `sentry_flutter/lib/src/sentry_flutter.dart:76-77`:
///   `isOnErrorSupported = !isWeb && PlatformDispatcher.onError is usable`.
///   On web this is always false, so no `OnErrorIntegration` is installed
///   (`sentry_flutter.dart:169-171`); the comment at `:73-75` says Flutter
///   Web does not deliver `Future` errors via `PlatformDispatcher.onError`
///   (flutter/flutter#100277).
/// - `sentry_flutter.dart:82`: `useRunZonedGuarded = !isOnErrorSupported &&
///   isRootZone`. The SDK only uses a zone when it was given an `appRunner`
///   (`sentry/lib/src/sentry.dart:157-176`); on native it is a plain
///   `await appRunner()`.
///
/// [bootstrap] deliberately calls `SentryFlutter.init` WITHOUT `appRunner`
/// (so a `Supabase.initialize` failure is not hidden by the SDK), so on web
/// the SDK installs no zone at all and uncaught async errors would be lost.
/// This function supplies that zone: on web ([useGuardedZone] defaults to
/// `kIsWeb`) the whole [body] -- including
/// `WidgetsFlutterBinding.ensureInitialized()` and `runApp`, which must share
/// one zone -- runs in `runZonedGuarded`, with [onError] (default
/// [reportUncaughtZoneError]) as handler. On native ([useGuardedZone] false)
/// `PlatformDispatcher.onError` (via Sentry's `OnErrorIntegration`) already
/// covers async errors, so [body] is simply awaited and its failure
/// propagates exactly as before.
///
/// A failure of [body] itself (sync throw or async error) is routed to
/// [onError] explicitly, once, so it is always printed and captured.
Future<void> runBootstrapGuarded(
  Future<void> Function() body, {
  bool useGuardedZone = kIsWeb,
  void Function(Object error, StackTrace stackTrace) onError =
      reportUncaughtZoneError,
}) {
  if (!useGuardedZone) {
    return body();
  }
  final done = Completer<void>();
  runZonedGuarded(() {
    Future<void>.sync(body).then<void>(
      (_) => done.complete(),
      onError: (Object error, StackTrace stackTrace) {
        onError(error, stackTrace);
        done.complete();
      },
    );
  }, onError);
  return done.future;
}

/// Initializes Sentry (when [config] is enabled) and returns the
/// [Observability] the rest of the app must use, also publishing it through
/// [setCurrentObservability].
///
/// Fail soft (ADR-036 point 5): if [init] throws (e.g. a malformed DSN), the
/// error is reported and [NoopObservability] is used. `Sentry` stays on its
/// `NoOpHub` in that case, so keeping [SentryObservability] would do
/// pointless work (spans/trace context against a disabled hub); the caller
/// must build `TracingHttpClient` from the returned value.
Future<Observability> initObservability(
  SentryConfig config, {
  FutureOr<void> Function(FlutterOptionsConfiguration) init =
      SentryFlutter.init,
}) async {
  Observability observability = const NoopObservability();
  if (config.isEnabled) {
    try {
      await init((options) {
        options.dsn = config.dsn;
        options.environment = config.environment;
        options.tracesSampleRate = 1.0;
        options.sendDefaultPii = false;
        // sentry_flutter 8.14.2 defaults `anrEnabled` to false
        // (sentry_flutter_options.dart:72; Android only). The spec puts
        // Android ANR detection in scope, so opt in. iOS/macOS
        // `enableAppHangTracking` already defaults to true (:271), left as is.
        options.anrEnabled = true;
      });
      observability = const SentryObservability();
    } catch (error, stackTrace) {
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
  setCurrentObservability(observability);
  return observability;
}

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  final sentryConfig = SentryConfig.fromEnvironment();
  final observability = await initObservability(sentryConfig);

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
