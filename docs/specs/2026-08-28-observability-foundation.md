# Spec: Observability Foundation (Sentry-backed, backend-swappable)

## Status

Approved for implementation.

## Problem

`apps/lyron_app` has no crash reporting, no error telemetry, and no
distributed tracing. Debugging production issues (sync failures, ANRs,
crashes) currently depends on user reports and `debugPrint` calls that are
never collected. There is also no way to correlate a client-side failure
with the corresponding Supabase Cloud request/log entry.

## Goals

- Unhandled and handled errors, native crashes, Android ANR, and iOS app
  hangs are captured and reported.
- Business operations become root traces; Drift and Supabase operations
  become child spans under them.
- Breadcrumbs, release/build context, and symbolication metadata are
  attached to every event.
- 100% error and trace sampling (justified by current low traffic).
- A Sentry trace's `trace_id` is correlatable with the corresponding
  Supabase Cloud log entry via a W3C `traceparent` header on every
  Supabase request.
- No PII, tokens, request/response bodies, RPC parameter values, lyrics, or
  ChordPro content ever reach Sentry. `user_id`/`organization_id` may be
  attached as pseudonymized context.
- Application code depends only on a thin first-party `Observability`
  abstraction, never directly on the Sentry API, so a future swap to
  OpenTelemetry does not require touching call sites.

## Non-goals (explicit, per direction from product/architecture)

- OpenTelemetry Dart SDK, OTLP gateway, Supabase Log Drain, or self-hosted
  Grafana/Loki/Tempo. These may arrive in a later slice; Sentry is the only
  telemetry backend introduced here.
- Native crash symbol upload wiring (Sentry Android Gradle plugin, iOS
  dSYM upload in CI). This modifies the CI/CD pipeline and belongs to the
  roadmap's Phase 9 (production readiness / release pipeline), not this
  slice. Dart-side native crash *capture* (via `sentry_flutter`'s bundled
  native SDKs) ships now; *readable* (symbolicated) native stack traces is
  deferred until that pipeline work lands.
- Instrumenting every use case in the app. This slice instruments one
  complete vertical slice end-to-end (song catalog refresh + sign-in) to
  prove the pattern. Remaining use cases (planning mutation sync, discard,
  storage eviction, unified sync overview) are explicitly deferred — see
  `docs/deferred/2026-08-28-observability-remaining-use-cases.md`.
- Live verification of the Sentry↔Supabase trace correlation against a
  real Supabase Cloud project. The Supabase MCP connector is not
  authenticated in this environment, so this slice ships an offline
  unit-level proof of the header contract plus a manual runbook — see
  `docs/specs/2026-08-28-w3c-traceparent-correlation-spike.md`.

## Architecture

### Abstraction shape

A first-party interface, not a static facade, following the existing
repository-contract pattern (`SongRepository` → `SupabaseSongRepository`):

```
lib/src/application/observability/
  observability.dart            # Observability, ObservabilitySpan,
                                 # ObservabilitySpanStatus, BreadcrumbLevel,
                                 # NoopObservability, NoopObservabilitySpan
  observability_providers.dart  # observabilityProvider (Riverpod)

lib/src/infrastructure/observability/
  sentry_observability.dart     # SentryObservability adapter
  w3c_trace_context.dart        # pure traceparent builder/parser
  tracing_http_client.dart      # http.Client wrapper injecting traceparent

lib/src/infrastructure/config/
  sentry_config.dart            # SentryConfig.fromEnvironment()
```

`Observability` surface:

```dart
abstract class Observability {
  ObservabilitySpan runInSpan<T>(
    String name,
    String operation,
    Future<T> Function(ObservabilitySpan span) body, {
    Map<String, Object?>? data,
  });

  ObservabilitySpan? get currentSpan;

  /// W3C `traceparent` header value for the current span, or null if there
  /// is no active span. Backend-agnostic name (W3C term, not a Sentry term)
  /// so an OpenTelemetry adapter can implement it the same way.
  String? get currentTraceParent;

  void captureException(
    Object error,
    StackTrace stackTrace, {
    Map<String, Object?>? extra,
  });

  void addBreadcrumb(
    String message, {
    String? category,
    BreadcrumbLevel level = BreadcrumbLevel.info,
    Map<String, Object?>? data,
  });

  void setUserContext({required String userId, required String organizationId});

  void clearUserContext();
}

abstract class ObservabilitySpan {
  ObservabilitySpan startChild(
    String operation, {
    String? description,
    Map<String, Object?>? data,
  });

  void setData(String key, Object? value);
  void setStatus(ObservabilitySpanStatus status);
  Future<void> finish();
}

enum ObservabilitySpanStatus { ok, cancelled, internalError, unknown }
enum BreadcrumbLevel { debug, info, warning, error }
```

`NoopObservability`/`NoopObservabilitySpan` are the default when
`SentryConfig.dsn` is empty (local dev without a DSN) and the default in
unit tests. This mirrors the project's existing fail-soft pattern for
optional infrastructure rather than the fail-fast `SupabaseConfig` pattern,
because a missing telemetry DSN must never crash the app.

### Span propagation: Dart `Zone`, not Sentry's ambient scope

Sentry's Dart SDK exposes an ambient "current span" via a mutable `Scope`
object (`Sentry.getSpan()`). This app has concurrent independent root
operations by design (the unified sync overview can run song-catalog sync
and planning sync at the same time). A single mutable ambient scope would
let one root trace's child spans attach to the other's transaction.

Instead, `SentryObservability.runInSpan` propagates the active span through
a dedicated `Zone` value (`Zone.current[_spanKey]`), scoped per async call
tree. Concurrent `runInSpan` calls each fork their own zone and cannot
clobber each other. `startChild` on an `ObservabilitySpan` looks up its
parent through this zone key, not through Sentry's scope stack. The
underlying Sentry transaction/span is still created via
`Sentry.startTransaction`/`span.startChild`, but with `bindToScope: false`
— the app's zone-based propagation is authoritative, and Sentry's own scope
stack is left untouched. This detail is internal to the Sentry adapter and
does not appear in the `Observability` interface; a future OpenTelemetry
adapter would use its own `Context`-based propagation (which is likewise
`Zone`-based in `package:opentelemetry`) behind the same interface.

### Business ops = root traces, Drift/Supabase = child spans

`runInSpan` starting with no parent in the current zone creates a new
Sentry transaction (root trace). Call sites for this slice:

- `SongCatalogController`'s guarded refresh path — root trace
  `song_catalog.refresh` / operation `business.refresh`.
- Sign-in completion in `auth_providers.dart` — root trace
  `auth.sign_in` / operation `business.auth`.

Child spans, created via `observability.currentSpan?.startChild(...)`
inside the already-running root trace:

- `SupabaseSongRepository` network calls — operation `http.client`.
- The Drift write in the song catalog store that persists the refreshed
  snapshot — operation `db.write`.

If `currentSpan` is null (no root trace in progress — e.g. a call outside
the instrumented paths, or Sentry disabled), `startChild` is a no-op on
`NoopObservabilitySpan` and callers do not need to branch on this.

### Error reporting semantics

- **Unhandled**: `SentryFlutter.init`'s bundled `FlutterError.onError` and
  `PlatformDispatcher.onError` hooks capture these automatically. No
  application code changes this behavior.
- **Handled**: explicit `observability.captureException(error, stackTrace)`
  calls at true-bug boundaries. `runInSpan`'s internal catch block sets
  `ObservabilitySpanStatus.internalError` on the span and rethrows — it
  does **not** call `captureException` itself. Typed control-flow
  exceptions already used throughout the app (`SongNotFoundException`,
  `SongAccessDeniedException`, `ConnectivityFailure`-classified errors)
  are expected outcomes, not bugs; auto-capturing every thrown exception
  inside a span would flood Sentry with noise. Callers decide, at their
  existing error-classification boundary, whether a caught error is
  reportable.
- `bootstrap.dart`'s `closeSharedDatabases().catchError` continues to call
  `FlutterError.reportError` (already auto-captured by Sentry's hook) — no
  change needed there.

### PII and secret redaction

Layered, not relying on a single control:

1. `options.sendDefaultPii = false` (explicit; Sentry's own default is
   `true`).
2. A `beforeSend`/span-attribute scrub in `SentryObservability` that
   strips any breadcrumb/span data entry whose **key** matches a denylist:
   `authorization`, `apikey`, `access_token`, `refresh_token`,
   `chordpro_source`, `lyrics`, `token`. This is defense-in-depth, not a
   substitute for discipline at call sites.
3. `setUserContext` only ever accepts `userId`/`organizationId` — both are
   Supabase UUIDs already opaque/pseudonymous, never email or display
   name. There is no code path to attach email or name to Sentry scope.
4. `maxRequestBodySize` is left at Sentry's default `never` behavior for
   this SDK version's HTTP breadcrumb capture (not raised) — request/
   response bodies are never attached.
5. Documented explicitly in ADR-036: what must never be passed as
   span/breadcrumb `data` values.

### Sentry configuration

`SentryConfig.fromEnvironment()` mirrors `SupabaseConfig`'s dart-define
pattern but fails soft:

```dart
factory SentryConfig.fromEnvironment({
  String dsn = const String.fromEnvironment('SENTRY_DSN'),
  String environment = const String.fromEnvironment(
    'SENTRY_ENVIRONMENT',
    defaultValue: 'development',
  ),
}) => SentryConfig(dsn: dsn, environment: environment);

bool get isEnabled => dsn.isNotEmpty;
```

`bootstrap.dart` calls `SentryFlutter.init` only when `isEnabled`; when
disabled, `observabilityProvider` resolves to `NoopObservability` and the
app runs exactly as it does today. Release version is read from the
platform package-info (Sentry's default behavior) which already reflects
`pubspec.yaml`'s `version: 0.1.0+8`; no separate release wiring is added.

`options.tracesSampleRate = 1.0`. Native crash handling, ANR detection,
and iOS app hang tracking are left at `sentry_flutter`'s defaults (all
`true`) — no explicit override needed, this is already the documented
default.

### W3C `traceparent` propagation to Supabase

Sentry's Dart SDK does not emit a standard `traceparent` header — it emits
its own `sentry-trace` and `baggage` headers (confirmed via context7
against `getsentry/sentry-dart` docs and the `SentryHttpClient`/
`tracing_client` behavior). Sentry's trace ID (32 hex chars) and span ID
(16 hex chars) are format-compatible with the W3C spec's `trace-id` and
`parent-id`, so a compliant `traceparent` header can be constructed
manually from the currently active span.

- `w3c_trace_context.dart` — pure function
  `String buildTraceParent({required String traceId, required String spanId, bool sampled = true})`
  producing `00-<trace_id>-<span_id>-<01|00>`. No Sentry dependency; unit
  testable in isolation.
- `Observability.currentTraceParent` (see interface above) returns this
  string for the active span, or null.
- `TracingHttpClient` wraps `package:http`'s `Client`, injects the
  `traceparent` header (when non-null) into every outgoing request, and is
  passed to `Supabase.initialize(httpClient: TracingHttpClient(...))`.
  `SupabaseClient`/`Supabase.initialize` accept an `httpClient` parameter
  (confirmed by reading the installed `supabase` package source,
  `supabase_client.dart`), so no monkey-patching of the Postgrest/GoTrue
  internals is required.

Validation of this mechanism is a separate spike document — see
`docs/specs/2026-08-28-w3c-traceparent-correlation-spike.md`.

## Testing strategy

TDD, mirroring existing test layout:

- `test/infrastructure/observability/w3c_trace_context_test.dart` — pure
  builder/parser round-trip and format validation.
- `test/infrastructure/observability/tracing_http_client_test.dart` —
  header injection present when a span is active, absent when not.
- `test/infrastructure/observability/sentry_observability_test.dart` —
  zone-based propagation: nested `runInSpan` calls produce parent/child
  relationships; concurrent sibling `runInSpan` calls do not cross-attach;
  PII denylist scrub strips denylisted keys from span/breadcrumb data.
- `test/infrastructure/config/sentry_config_test.dart` — empty DSN →
  `isEnabled == false`; non-empty DSN → `isEnabled == true`; environment
  default.
- `test/application/observability/observability_providers_test.dart` —
  provider resolves to `NoopObservability` when config disabled.
- Existing `SongCatalogController`/`SupabaseSongRepository`/auth provider
  tests gain assertions that the injected `Observability` records the
  expected root trace / child span calls (via a test double implementing
  the interface — no real Sentry network calls in tests).

## Documentation impact

- `docs/architecture/architecture.md` — new "Observability" section.
- `docs/architecture/decisions/ADR-036-observability-sentry-adapter.md`.
- `docs/deferred/2026-08-28-observability-remaining-use-cases.md`.
- `docs/specs/2026-08-28-w3c-traceparent-correlation-spike.md`.

## Open questions

None outstanding — DSN is a placeholder (`SENTRY_DSN` dart-define, empty
by default) until the user provisions a real Sentry project; the runbook
in the spike doc tells them exactly what to do at that point.
