# Observability Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Introduce a thin, backend-swappable `Observability` abstraction over `sentry_flutter`, wire it through `apps/lyron_app`'s bootstrap, and instrument one complete vertical slice (`SongCatalogController`'s song catalog refresh, plus sign-in's pseudonymized user-context tagging) end-to-end with root traces, child spans, breadcrumbs, and a W3C `traceparent` header on Supabase requests.

**Architecture:** Application code depends only on `Observability`/`ObservabilitySpan` (interface + `Noop` implementations in `lib/src/application/observability/`); `SentryObservability` (`lib/src/infrastructure/observability/`) is the sole adapter. Span parent/child resolution runs through a dedicated Dart `Zone` value, not Sentry's ambient `Scope`. Repository/store classes (`SupabaseSongRepository`, `DriftSongCatalogStore`) receive zero changes — every span-creation call site lives inside `SongCatalogController`, which already owns the calls being wrapped.

**Tech Stack:** Flutter, Riverpod, `sentry_flutter` (resolves to `sentry`/`sentry_flutter` 9.28.0), `package:http` (^1.6.0), Drift, Supabase.

**Source spec:** `docs/specs/2026-08-28-observability-foundation.md` (ADR-036, deferred doc, spike doc all committed alongside it on this branch). Read that spec's "Architecture" section before starting — every design decision below traces back to it, including the revision notes explaining what an adversarial review found and fixed in the first draft.

**Working directory for every command below:** `apps/lyron_app/` (all paths are relative to it unless stated otherwise).

---

### Task 1: Add dependencies

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Add the dependencies**

```bash
flutter pub add sentry_flutter http
```

Expected: resolves `sentry`/`sentry_flutter` to `9.28.0` and `http` to `^1.6.0` (already a transitive dependency via `supabase`, now promoted to direct since `tracing_http_client.dart` will import `package:http/http.dart` directly). If your resolution picks a different version, that is fine — the API surface used by this plan (`Sentry.startTransaction`, `ISentrySpan`, `SentrySpanContext`, `SpanStatus`, `Sentry.captureException(withScope:)`, `Sentry.configureScope`, `Scope.setUser`/`.span`, `Breadcrumb`, `SentryLevel`, `http.BaseClient`) has been stable across recent majors; if `flutter analyze` (Task 7+) surfaces a signature mismatch, fix it there rather than re-running this step.

- [ ] **Step 2: Verify it builds**

```bash
flutter analyze
```

Expected: no new errors (existing baseline warnings, if any, are unrelated to this change).

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore(deps): add sentry_flutter and http to lyron_app"
```

---

### Task 2: W3C traceparent builder (pure, no Sentry dependency)

**Files:**
- Create: `lib/src/infrastructure/observability/w3c_trace_context.dart`
- Test: `test/infrastructure/observability/w3c_trace_context_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/infrastructure/observability/w3c_trace_context.dart';

void main() {
  group('buildTraceParent', () {
    test('produces a spec-shaped header for a sampled span', () {
      final header = buildTraceParent(
        traceId: 'a' * 32,
        spanId: 'b' * 16,
      );

      expect(header, 'aa-${'a' * 32}-${'b' * 16}-01'.replaceFirst('aa-', '00-'));
    });

    test('matches the full traceparent regex', () {
      final header = buildTraceParent(
        traceId: '0123456789abcdef0123456789abcdef',
        spanId: '0123456789abcdef',
      );

      expect(
        header,
        matches(RegExp(r'^00-[0-9a-f]{32}-[0-9a-f]{16}-0[01]$')),
      );
      expect(header, '00-0123456789abcdef0123456789abcdef-0123456789abcdef-01');
    });

    test('encodes an unsampled decision as flag 00', () {
      final header = buildTraceParent(
        traceId: '0123456789abcdef0123456789abcdef',
        spanId: '0123456789abcdef',
        sampled: false,
      );

      expect(header, endsWith('-00'));
    });
  });
}
```

Note: the first test's expected-value construction is deliberately awkward
(string surgery to avoid literally repeating the header twice) — replace it
with the direct literal once you've confirmed the second test's exact-match
assertion passes; the second test is the one that matters. If it's easier,
just delete the first test's odd construction and rely on the second and
third tests, which already pin the exact format precisely.

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/infrastructure/observability/w3c_trace_context_test.dart
```

Expected: FAIL — `w3c_trace_context.dart` does not exist yet (`Target of URI doesn't exist`).

- [ ] **Step 3: Write the implementation**

```dart
/// Builds a W3C Trace Context `traceparent` header value from a Sentry
/// trace id (32 lowercase hex chars) and span id (16 lowercase hex chars).
/// Sentry's own id formats are already W3C-shaped — this is pure string
/// assembly, with no Sentry dependency, so it is testable in isolation and
/// portable to any future tracing backend that also produces hex ids in
/// these lengths.
String buildTraceParent({
  required String traceId,
  required String spanId,
  bool sampled = true,
}) {
  final flags = sampled ? '01' : '00';
  return '00-$traceId-$spanId-$flags';
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/infrastructure/observability/w3c_trace_context_test.dart
```

Expected: PASS (3 tests). If the first test's string-surgery assertion is
confusing or fails on a typo, simplify it to a direct literal comparison
matching the pattern used in the second test.

- [ ] **Step 5: Commit**

```bash
git add lib/src/infrastructure/observability/w3c_trace_context.dart test/infrastructure/observability/w3c_trace_context_test.dart
git commit -m "feat(observability): add W3C traceparent header builder"
```

---

### Task 3: `Observability` interface and Noop implementations

**Files:**
- Create: `lib/src/application/observability/observability.dart`
- Test: `test/application/observability/observability_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/observability/observability.dart';

void main() {
  group('NoopObservability', () {
    const observability = NoopObservability();

    test('runInSpan runs body with a NoopObservabilitySpan and returns its result', () async {
      final result = await observability.runInSpan(
        'name',
        'operation',
        (span) async {
          expect(span, isA<NoopObservabilitySpan>());
          return 42;
        },
      );

      expect(result, 42);
    });

    test('currentSpan is a NoopObservabilitySpan, never null', () {
      expect(observability.currentSpan, isA<NoopObservabilitySpan>());
    });

    test('currentTraceParent is null', () {
      expect(observability.currentTraceParent, isNull);
    });

    test('captureException, addBreadcrumb, setUserContext, clearUserContext are safe no-ops', () {
      expect(
        () => observability.captureException(Exception('x'), StackTrace.current),
        returnsNormally,
      );
      expect(
        () => observability.addBreadcrumb('msg', category: 'cat'),
        returnsNormally,
      );
      expect(
        () => observability.setUserContext(userId: 'u1', organizationId: 'o1'),
        returnsNormally,
      );
      expect(() => observability.clearUserContext(), returnsNormally);
    });

    test('runInSpan propagates a thrown error from body', () {
      expect(
        () => observability.runInSpan('n', 'o', (span) async => throw Exception('boom')),
        throwsException,
      );
    });
  });

  group('NoopObservabilitySpan', () {
    const span = NoopObservabilitySpan();

    test('startChild returns another NoopObservabilitySpan', () {
      expect(span.startChild('op'), isA<NoopObservabilitySpan>());
    });

    test('setData, setStatus, finish are safe no-ops', () async {
      expect(() => span.setData('k', 'v'), returnsNormally);
      expect(() => span.setStatus(ObservabilitySpanStatus.ok), returnsNormally);
      await expectLater(span.finish(), completes);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/application/observability/observability_test.dart
```

Expected: FAIL — file does not exist.

- [ ] **Step 3: Write the implementation**

```dart
/// Backend-agnostic status for a completed span. Named after the W3C/OTel
/// concept, not Sentry's `SpanStatus` type, so a future OpenTelemetry
/// adapter maps onto the same four values without a Sentry-specific name
/// leaking into application code.
enum ObservabilitySpanStatus { ok, cancelled, internalError, unknown }

enum BreadcrumbLevel { debug, info, warning, error }

/// A first-party tracing/error-reporting abstraction. Application code
/// depends only on this interface, never on the Sentry API directly, so a
/// future OpenTelemetry adapter can be substituted without touching call
/// sites. See docs/specs/2026-08-28-observability-foundation.md and
/// docs/architecture/decisions/ADR-036-observability-sentry-adapter.md for
/// the full design rationale, including why span propagation happens
/// through a dedicated Dart Zone value rather than Sentry's own ambient
/// scope.
abstract class Observability {
  /// Runs [body] as a span named [name] with operation [operation]. If
  /// there is already an active span in the current Zone, the new span is
  /// its child; otherwise it starts a new root trace. The span finishes
  /// automatically when [body] completes or throws; on throw,
  /// [ObservabilitySpanStatus.internalError] is set before the exception
  /// is rethrown unmodified. [body] runs inside a new Zone in which this
  /// span is the ambient [currentSpan]/[currentTraceParent] for its
  /// duration -- including for code with no direct span reference, called
  /// deep inside [body]'s call stack.
  Future<T> runInSpan<T>(
    String name,
    String operation,
    Future<T> Function(ObservabilitySpan span) body, {
    Map<String, Object?>? data,
  });

  /// The active span in the current Zone. Never null -- resolves to a
  /// [NoopObservabilitySpan] when nothing is active, so callers never need
  /// to branch on whether tracing is active.
  ObservabilitySpan get currentSpan;

  /// W3C `traceparent` header value for the current span, or null if there
  /// is no active span.
  String? get currentTraceParent;

  /// Reports a handled error, explicitly linked to the current span.
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

  /// [userId] and [organizationId] must be pseudonymized identifiers
  /// (Supabase UUIDs) -- never an email address or display name.
  void setUserContext({required String userId, String? organizationId});

  void clearUserContext();
}

abstract class ObservabilitySpan {
  /// A non-ambient nested span: does not enter a new Zone, so it does not
  /// become [Observability.currentSpan] for anything else. Prefer
  /// [Observability.runInSpan] unless you specifically want a nested span
  /// that stays invisible to ambient lookups.
  ObservabilitySpan startChild(
    String operation, {
    String? description,
    Map<String, Object?>? data,
  });

  void setData(String key, Object? value);
  void setStatus(ObservabilitySpanStatus status);
  Future<void> finish();
}

class NoopObservability implements Observability {
  const NoopObservability();

  @override
  Future<T> runInSpan<T>(
    String name,
    String operation,
    Future<T> Function(ObservabilitySpan span) body, {
    Map<String, Object?>? data,
  }) {
    return body(const NoopObservabilitySpan());
  }

  @override
  ObservabilitySpan get currentSpan => const NoopObservabilitySpan();

  @override
  String? get currentTraceParent => null;

  @override
  void captureException(
    Object error,
    StackTrace stackTrace, {
    Map<String, Object?>? extra,
  }) {}

  @override
  void addBreadcrumb(
    String message, {
    String? category,
    BreadcrumbLevel level = BreadcrumbLevel.info,
    Map<String, Object?>? data,
  }) {}

  @override
  void setUserContext({required String userId, String? organizationId}) {}

  @override
  void clearUserContext() {}
}

class NoopObservabilitySpan implements ObservabilitySpan {
  const NoopObservabilitySpan();

  @override
  ObservabilitySpan startChild(
    String operation, {
    String? description,
    Map<String, Object?>? data,
  }) => const NoopObservabilitySpan();

  @override
  void setData(String key, Object? value) {}

  @override
  void setStatus(ObservabilitySpanStatus status) {}

  @override
  Future<void> finish() async {}
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/application/observability/observability_test.dart
```

Expected: PASS (9 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/src/application/observability/observability.dart test/application/observability/observability_test.dart
git commit -m "feat(observability): add Observability interface and Noop implementations"
```

---

### Task 4: `SentryConfig`

**Files:**
- Create: `lib/src/infrastructure/config/sentry_config.dart`
- Test: `test/infrastructure/config/sentry_config_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/infrastructure/config/sentry_config.dart';

void main() {
  test('disabled when the DSN is empty', () {
    final config = SentryConfig.fromEnvironment(dsn: '', environment: 'development');

    expect(config.isEnabled, isFalse);
    expect(config.dsn, '');
    expect(config.environment, 'development');
  });

  test('enabled when a non-empty DSN is provided', () {
    final config = SentryConfig.fromEnvironment(
      dsn: 'https://public@example.ingest.sentry.io/1',
      environment: 'production',
    );

    expect(config.isEnabled, isTrue);
    expect(config.environment, 'production');
  });

  test('defaults environment to development when not provided', () {
    final config = SentryConfig.fromEnvironment(dsn: '');

    expect(config.environment, 'development');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/infrastructure/config/sentry_config_test.dart
```

Expected: FAIL — file does not exist.

- [ ] **Step 3: Write the implementation**

```dart
/// Mirrors `SupabaseConfig`'s dart-define pattern, but fails soft: a
/// missing Sentry DSN disables telemetry ([isEnabled] == false) rather
/// than throwing, because telemetry is not a correctness-critical
/// dependency the way Supabase configuration is.
class SentryConfig {
  const SentryConfig({required this.dsn, required this.environment});

  final String dsn;
  final String environment;

  bool get isEnabled => dsn.isNotEmpty;

  factory SentryConfig.fromEnvironment({
    String dsn = const String.fromEnvironment('SENTRY_DSN'),
    String environment = const String.fromEnvironment(
      'SENTRY_ENVIRONMENT',
      defaultValue: 'development',
    ),
  }) {
    return SentryConfig(dsn: dsn, environment: environment);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/infrastructure/config/sentry_config_test.dart
```

Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/src/infrastructure/config/sentry_config.dart test/infrastructure/config/sentry_config_test.dart
git commit -m "feat(observability): add SentryConfig.fromEnvironment"
```

---

### Task 5: `observability_providers.dart` (bootstrap-time singleton + Riverpod provider)

**Files:**
- Create: `lib/src/application/observability/observability_providers.dart`
- Test: `test/application/observability/observability_providers_test.dart`
- Modify: `lib/src/application/providers.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/observability/observability.dart';
import 'package:lyron_app/src/application/observability/observability_providers.dart';

class _FakeObservability extends NoopObservability {
  const _FakeObservability();
}

void main() {
  test('observabilityProvider resolves to NoopObservability by default', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(observabilityProvider), isA<NoopObservability>());
  });

  test('observabilityProvider is overridable in tests without touching the global setter', () {
    const fake = _FakeObservability();
    final container = ProviderContainer(
      overrides: [observabilityProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    expect(container.read(observabilityProvider), same(fake));
  });

  test('setCurrentObservability changes what a fresh provider read resolves to', () {
    const fake = _FakeObservability();
    setCurrentObservability(fake);
    addTearDown(() => setCurrentObservability(const NoopObservability()));

    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(observabilityProvider), same(fake));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/application/observability/observability_providers_test.dart
```

Expected: FAIL — file does not exist.

- [ ] **Step 3: Write the implementation**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/application/observability/observability.dart';

// `Observability` must exist before `Supabase.initialize` runs in
// bootstrap.dart (needed to construct `TracingHttpClient`), which itself
// runs before any `ProviderScope` exists -- so it cannot be resolved
// through Riverpod at the point it is first needed. This mirrors how
// `core_providers.dart`'s `supabaseClientProvider` reads the static
// `Supabase.instance.client` rather than constructing it. Tests should
// prefer `ProviderContainer(overrides: [observabilityProvider
// .overrideWithValue(fake)])` over this setter -- the setter exists only
// for the one call site (`bootstrap()`) that runs before any
// `ProviderScope` exists.
Observability _currentObservability = const NoopObservability();

void setCurrentObservability(Observability observability) {
  _currentObservability = observability;
}

final observabilityProvider = Provider<Observability>((ref) {
  return _currentObservability;
});
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/application/observability/observability_providers_test.dart
```

Expected: PASS (3 tests). Note: since `_currentObservability` is
module-level mutable state, the third test's `setCurrentObservability`
call must be undone in `addTearDown` (shown above) so it doesn't leak into
other tests in the same process -- this is exactly why production/most
test code should prefer the `overrideWithValue` path from the second test.

- [ ] **Step 5: Export from the providers barrel**

In `lib/src/application/providers.dart`, add one line (matches the existing style of that file):

```dart
export 'observability/observability_providers.dart';
```

- [ ] **Step 6: Run the full test suite for a sanity check**

```bash
flutter test test/application/providers_test.dart
```

Expected: PASS — the barrel export must not break existing re-exports (name collisions would surface here).

- [ ] **Step 7: Commit**

```bash
git add lib/src/application/observability/observability_providers.dart test/application/observability/observability_providers_test.dart lib/src/application/providers.dart
git commit -m "feat(observability): add observabilityProvider and bootstrap singleton holder"
```

---

### Task 6: `TracingHttpClient`

**Files:**
- Create: `lib/src/infrastructure/observability/tracing_http_client.dart`
- Test: `test/infrastructure/observability/tracing_http_client_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lyron_app/src/application/observability/observability.dart';
import 'package:lyron_app/src/infrastructure/observability/tracing_http_client.dart';

class _RecordingInnerClient extends http.BaseClient {
  http.BaseRequest? lastRequest;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastRequest = request;
    return http.StreamedResponse(const Stream.empty(), 200);
  }
}

class _FakeObservability extends NoopObservability {
  const _FakeObservability(this._traceParent);

  final String? _traceParent;

  @override
  String? get currentTraceParent => _traceParent;
}

void main() {
  test('injects the traceparent header when a span is active', () async {
    final inner = _RecordingInnerClient();
    final client = TracingHttpClient(
      inner,
      const _FakeObservability('00-${'a' * 32}-${'b' * 16}-01'),
      isWeb: false,
    );

    await client.get(Uri.parse('https://example.supabase.co/rest/v1/songs'));

    expect(inner.lastRequest!.headers['traceparent'], '00-${'a' * 32}-${'b' * 16}-01');
  });

  test('omits the header when there is no active span', () async {
    final inner = _RecordingInnerClient();
    final client = TracingHttpClient(inner, const _FakeObservability(null), isWeb: false);

    await client.get(Uri.parse('https://example.supabase.co/rest/v1/songs'));

    expect(inner.lastRequest!.headers.containsKey('traceparent'), isFalse);
  });

  test('omits the header on web even when a span is active', () async {
    final inner = _RecordingInnerClient();
    final client = TracingHttpClient(
      inner,
      const _FakeObservability('00-${'a' * 32}-${'b' * 16}-01'),
      isWeb: true,
    );

    await client.get(Uri.parse('https://example.supabase.co/rest/v1/songs'));

    expect(inner.lastRequest!.headers.containsKey('traceparent'), isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/infrastructure/observability/tracing_http_client_test.dart
```

Expected: FAIL — file does not exist.

- [ ] **Step 3: Write the implementation**

```dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:lyron_app/src/application/observability/observability.dart';

/// Injects a W3C `traceparent` header (built from the current span, if
/// any) into every outgoing request, so a Sentry trace's `trace_id` is
/// correlatable with the corresponding Supabase Cloud request log.
///
/// The header is never sent on web ([isWeb] defaults to [kIsWeb]):
/// `traceparent` is not a CORS-safelisted header, and injecting it
/// unconditionally would break web requests outright if Supabase's CORS
/// configuration does not explicitly allow it. See
/// docs/specs/2026-08-28-w3c-traceparent-correlation-spike.md for the web
/// verification runbook required before this gate can be lifted.
class TracingHttpClient extends http.BaseClient {
  TracingHttpClient(
    this._inner,
    this._observability, {
    bool isWeb = kIsWeb,
  }) : _isWeb = isWeb;

  final http.Client _inner;
  final Observability _observability;
  final bool _isWeb;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (!_isWeb) {
      final traceParent = _observability.currentTraceParent;
      if (traceParent != null) {
        request.headers['traceparent'] = traceParent;
      }
    }
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/infrastructure/observability/tracing_http_client_test.dart
```

Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/src/infrastructure/observability/tracing_http_client.dart test/infrastructure/observability/tracing_http_client_test.dart
git commit -m "feat(observability): add TracingHttpClient for W3C traceparent injection"
```

---

### Task 7: `SentryObservability` adapter — PII scrub helper first

The adapter is the most complex piece. Build and test the recursive PII
scrub as a standalone private-but-testable function first, then the
adapter itself, so failures are easy to localize.

**Files:**
- Create: `lib/src/infrastructure/observability/sentry_pii_scrub.dart`
- Test: `test/infrastructure/observability/sentry_pii_scrub_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/infrastructure/observability/sentry_pii_scrub.dart';

void main() {
  test('drops denylisted keys case-insensitively', () {
    final result = scrubPii({
      'Authorization': 'Bearer xyz',
      'apikey': 'k',
      'access_token': 't',
      'refresh_token': 'r',
      'token': 't2',
      'safe': 'kept',
      // ChordPro content and lyrics are deliberately NOT denylisted --
      // per explicit product direction they are not sensitive and may
      // aid debugging. Confirmed by the next test.
    });

    expect(result, {'safe': 'kept'});
  });

  test('does not scrub ChordPro content or lyrics -- not sensitive by product direction', () {
    final result = scrubPii({
      'chordpro_source': '{title: Amazing Grace}\n[G]Amazing [C]grace',
      'lyrics': 'Amazing grace, how sweet the sound',
    });

    expect(result, {
      'chordpro_source': '{title: Amazing Grace}\n[G]Amazing [C]grace',
      'lyrics': 'Amazing grace, how sweet the sound',
    });
  });

  test('recurses into nested maps and lists', () {
    final result = scrubPii({
      'outer': {
        'authorization': 'Bearer xyz',
        'list': [
          {'token': 't'},
          {'safe': 'kept'},
        ],
      },
    });

    expect(result, {
      'outer': {
        'list': [<String, Object?>{}, {'safe': 'kept'}],
      },
    });
  });

  test('strips the query string from URL-shaped string values', () {
    final result = scrubPii({
      'url': 'https://example.supabase.co/rest/v1/songs?slug=eq.some-song&select=*',
    });

    expect(result, {'url': 'https://example.supabase.co/rest/v1/songs'});
  });

  test('redacts JWT-shaped string values regardless of key', () {
    const jwt =
        'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1c2VyIn0.dGVzdC1zaWduYXR1cmU';
    final result = scrubPii({'unlisted_key': jwt});

    expect(result, {'unlisted_key': '[redacted]'});
  });

  test('passes through ordinary non-URL, non-JWT string values unchanged', () {
    final result = scrubPii({'reason': 'refresh failed'});

    expect(result, {'reason': 'refresh failed'});
  });

  test('returns null for null input', () {
    expect(scrubPii(null), isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/infrastructure/observability/sentry_pii_scrub_test.dart
```

Expected: FAIL — file does not exist.

- [ ] **Step 3: Write the implementation**

```dart
const _piiKeyDenylist = {
  'authorization',
  'apikey',
  'access_token',
  'refresh_token',
  'token',
};

final _jwtPattern = RegExp(
  r'^eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*$',
);

/// Recursively scrubs a data map before it reaches the Sentry SDK.
/// Defense-in-depth only -- call sites must never pass a raw
/// token/credential or a personal identifier (email, display name) as
/// span/breadcrumb data in the first place. ChordPro content, lyrics, and
/// other business/domain content are deliberately NOT scrubbed -- per
/// explicit product direction, only credentials and personal identifiers
/// are treated as sensitive here. See
/// docs/architecture/decisions/ADR-036-observability-sentry-adapter.md
/// point 7 for the full policy.
Map<String, Object?>? scrubPii(Map<String, Object?>? data) {
  if (data == null) return null;
  return _scrubMap(data);
}

Map<String, Object?> _scrubMap(Map<String, Object?> data) {
  final result = <String, Object?>{};
  for (final entry in data.entries) {
    if (_piiKeyDenylist.contains(entry.key.toLowerCase())) {
      continue;
    }
    result[entry.key] = _scrubValue(entry.value);
  }
  return result;
}

Object? _scrubValue(Object? value) {
  if (value is Map<String, Object?>) {
    return _scrubMap(value);
  }
  if (value is List) {
    return value.map(_scrubValue).toList(growable: false);
  }
  if (value is String) {
    return _scrubString(value);
  }
  return value;
}

String _scrubString(String value) {
  if (_jwtPattern.hasMatch(value)) {
    return '[redacted]';
  }
  final uri = Uri.tryParse(value);
  if (uri != null && uri.hasScheme && uri.query.isNotEmpty) {
    return uri.replace(query: '').toString();
  }
  return value;
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/infrastructure/observability/sentry_pii_scrub_test.dart
```

Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/src/infrastructure/observability/sentry_pii_scrub.dart test/infrastructure/observability/sentry_pii_scrub_test.dart
git commit -m "feat(observability): add recursive PII scrub for Sentry span/breadcrumb data"
```

---

### Task 8: `SentryObservability` adapter

**Files:**
- Create: `lib/src/infrastructure/observability/sentry_observability.dart`
- Test: `test/infrastructure/observability/sentry_observability_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/observability/observability.dart';
import 'package:lyron_app/src/infrastructure/observability/sentry_observability.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main() {
  setUp(() async {
    await Sentry.init((options) {
      options.dsn = 'https://public@o0.ingest.sentry.io/0';
      options.tracesSampleRate = 1.0;
      options.automatedTestMode = true;
    });
  });

  tearDown(() async {
    await Sentry.close();
  });

  test('runInSpan with no enclosing span starts a root, currentSpan sees it', () async {
    const observability = SentryObservability();
    ObservabilitySpan? seenInside;

    await observability.runInSpan('root', 'business.refresh', (span) async {
      seenInside = observability.currentSpan;
      expect(seenInside, isNot(isA<NoopObservabilitySpan>()));
      return null;
    });

    expect(observability.currentSpan, isA<NoopObservabilitySpan>());
  });

  test('nested runInSpan becomes a child of the enclosing span', () async {
    const observability = SentryObservability();
    String? parentTraceId;
    String? childTraceId;

    await observability.runInSpan('root', 'business.refresh', (rootSpan) async {
      parentTraceId = observability.currentTraceParent;
      await observability.runInSpan('child', 'http.client', (childSpan) async {
        childTraceId = observability.currentTraceParent;
        return null;
      });
      return null;
    });

    expect(parentTraceId, isNotNull);
    expect(childTraceId, isNotNull);
    // Same trace, different span (different parent-id segment).
    final parentTraceSegment = parentTraceId!.split('-')[1];
    final childTraceSegment = childTraceId!.split('-')[1];
    expect(childTraceSegment, parentTraceSegment);
    expect(childTraceId!.split('-')[2], isNot(parentTraceId!.split('-')[2]));
  });

  test('concurrent sibling runInSpan calls do not cross-attach', () async {
    const observability = SentryObservability();
    final traceIds = <String>[];

    await Future.wait([
      observability.runInSpan('a', 'business.refresh', (span) async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        traceIds.add(observability.currentTraceParent!.split('-')[1]);
      }),
      observability.runInSpan('b', 'business.refresh', (span) async {
        traceIds.add(observability.currentTraceParent!.split('-')[1]);
      }),
    ]);

    expect(traceIds.toSet().length, 2, reason: 'each root must have its own trace id');
  });

  test('currentTraceParent matches the real active span\'s ids', () async {
    const observability = SentryObservability();

    await observability.runInSpan('root', 'business.refresh', (span) async {
      final header = observability.currentTraceParent!;
      final parts = header.split('-');
      // header shape: 00-<traceId>-<spanId>-<flag>
      expect(parts[1].length, 32);
      expect(parts[2].length, 16);
    });
  });

  test('runInSpan sets internalError status and rethrows on failure', () async {
    const observability = SentryObservability();

    await expectLater(
      observability.runInSpan('root', 'business.refresh', (span) async {
        throw Exception('boom');
      }),
      throwsException,
    );
  });

  test('addBreadcrumb does not throw', () {
    const observability = SentryObservability();

    expect(
      () => observability.addBreadcrumb('did a thing', category: 'song_catalog'),
      returnsNormally,
    );
  });

  test('setUserContext and clearUserContext do not throw', () async {
    const observability = SentryObservability();

    observability.setUserContext(userId: 'u1', organizationId: 'o1');
    observability.clearUserContext();
  });

  test('captureException does not throw and does not require an active span', () {
    const observability = SentryObservability();

    expect(
      () => observability.captureException(Exception('handled'), StackTrace.current),
      returnsNormally,
    );
  });

  test('captureException inside a span does not throw', () async {
    const observability = SentryObservability();

    await observability.runInSpan('root', 'business.refresh', (span) async {
      observability.captureException(Exception('handled'), StackTrace.current);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/infrastructure/observability/sentry_observability_test.dart
```

Expected: FAIL — file does not exist.

- [ ] **Step 3: Write the implementation**

```dart
import 'dart:async';

import 'package:lyron_app/src/application/observability/observability.dart';
import 'package:lyron_app/src/infrastructure/observability/sentry_pii_scrub.dart';
import 'package:lyron_app/src/infrastructure/observability/w3c_trace_context.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

const _spanZoneKey = #lyronCurrentObservabilitySpan;

/// Sentry-backed [Observability] adapter. Span parent/child resolution
/// runs through a dedicated Dart Zone value ([_spanZoneKey]), not
/// Sentry's own ambient `Scope` -- see
/// docs/architecture/decisions/ADR-036-observability-sentry-adapter.md
/// point 2 for why, including the accepted consequence that
/// SDK-auto-captured unhandled errors are never trace-linked as a result.
class SentryObservability implements Observability {
  const SentryObservability();

  _SentrySpanHandle? get _current =>
      Zone.current[_spanZoneKey] as _SentrySpanHandle?;

  @override
  Future<T> runInSpan<T>(
    String name,
    String operation,
    Future<T> Function(ObservabilitySpan span) body, {
    Map<String, Object?>? data,
  }) {
    final parent = _current;
    final sentrySpan = parent == null
        ? Sentry.startTransaction(name, operation, bindToScope: false)
        : parent.sentrySpan.startChild(operation, description: name);

    final scrubbed = scrubPii(data);
    if (scrubbed != null) {
      for (final entry in scrubbed.entries) {
        sentrySpan.setData(entry.key, entry.value);
      }
    }

    final handle = _SentrySpanHandle(sentrySpan);

    return runZoned<Future<T>>(() async {
      try {
        final result = await body(handle);
        return result;
      } catch (error, stackTrace) {
        sentrySpan.throwable = error;
        sentrySpan.status = const SpanStatus.internalError();
        rethrow;
      } finally {
        await sentrySpan.finish();
      }
    }, zoneValues: {_spanZoneKey: handle});
  }

  @override
  ObservabilitySpan get currentSpan =>
      _current ?? const NoopObservabilitySpan();

  @override
  String? get currentTraceParent {
    final span = _current?.sentrySpan;
    if (span == null) return null;
    return buildTraceParent(
      traceId: span.context.traceId.toString(),
      spanId: span.context.spanId.toString(),
      sampled: span.samplingDecision?.sampled ?? true,
    );
  }

  @override
  void captureException(
    Object error,
    StackTrace stackTrace, {
    Map<String, Object?>? extra,
  }) {
    final activeSpan = _current?.sentrySpan;
    final scrubbedExtra = scrubPii(extra);
    Sentry.captureException(
      error,
      stackTrace: stackTrace,
      withScope: (scope) {
        if (activeSpan != null) {
          scope.span = activeSpan;
        }
        if (scrubbedExtra != null) {
          for (final entry in scrubbedExtra.entries) {
            scope.setContexts(entry.key, entry.value);
          }
        }
      },
    );
  }

  @override
  void addBreadcrumb(
    String message, {
    String? category,
    BreadcrumbLevel level = BreadcrumbLevel.info,
    Map<String, Object?>? data,
  }) {
    Sentry.addBreadcrumb(
      Breadcrumb(
        message: message,
        category: category,
        level: _toSentryLevel(level),
        data: scrubPii(data),
      ),
    );
  }

  @override
  void setUserContext({required String userId, String? organizationId}) {
    Sentry.configureScope((scope) {
      scope.setUser(SentryUser(id: userId));
      if (organizationId != null) {
        scope.setContexts('organization', {'id': organizationId});
      }
    });
  }

  @override
  void clearUserContext() {
    Sentry.configureScope((scope) {
      scope.setUser(null);
    });
  }

  SentryLevel _toSentryLevel(BreadcrumbLevel level) {
    switch (level) {
      case BreadcrumbLevel.debug:
        return SentryLevel.debug;
      case BreadcrumbLevel.info:
        return SentryLevel.info;
      case BreadcrumbLevel.warning:
        return SentryLevel.warning;
      case BreadcrumbLevel.error:
        return SentryLevel.error;
    }
  }
}

class _SentrySpanHandle implements ObservabilitySpan {
  _SentrySpanHandle(this.sentrySpan);

  final ISentrySpan sentrySpan;

  @override
  ObservabilitySpan startChild(
    String operation, {
    String? description,
    Map<String, Object?>? data,
  }) {
    final child = sentrySpan.startChild(operation, description: description);
    final scrubbed = scrubPii(data);
    if (scrubbed != null) {
      for (final entry in scrubbed.entries) {
        child.setData(entry.key, entry.value);
      }
    }
    return _SentrySpanHandle(child);
  }

  @override
  void setData(String key, Object? value) {
    final scrubbed = scrubPii({key: value});
    if (scrubbed != null && scrubbed.containsKey(key)) {
      sentrySpan.setData(key, scrubbed[key]);
    }
  }

  @override
  void setStatus(ObservabilitySpanStatus status) {
    sentrySpan.status = _toSentryStatus(status);
  }

  @override
  Future<void> finish() => sentrySpan.finish();

  SpanStatus _toSentryStatus(ObservabilitySpanStatus status) {
    switch (status) {
      case ObservabilitySpanStatus.ok:
        return const SpanStatus.ok();
      case ObservabilitySpanStatus.cancelled:
        return const SpanStatus.cancelled();
      case ObservabilitySpanStatus.internalError:
        return const SpanStatus.internalError();
      case ObservabilitySpanStatus.unknown:
        return const SpanStatus.unknown();
    }
  }
}
```

Note on `runInSpan`'s success path: the SDK's `ISentrySpan.finish()`
defaults an unset `status` to `ok` on its own (standard Sentry SDK
behavior across languages) — there is deliberately no explicit
`sentrySpan.status = const SpanStatus.ok()` on the success path above; if
`flutter test` for this task shows a finished span's status is not `ok`
when no error occurred, add that explicit line rather than assuming the
default and moving on.

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/infrastructure/observability/sentry_observability_test.dart
```

Expected: PASS (10 tests). If the "matches the real active span's ids"
or nested-span tests fail on an API shape mismatch (e.g.
`samplingDecision` not accessible, or `context` not exposing `traceId`/
`spanId` the way this plan assumes), re-check against the installed
package: `grep -n "class SentrySpanContext" $(dart pub cache dir 2>/dev/null || echo ~/.pub-cache)/hosted/pub.dev/sentry-*/lib/src/sentry_span_context.dart` and adjust the adapter, not the test's intent.

- [ ] **Step 5: Commit**

```bash
git add lib/src/infrastructure/observability/sentry_observability.dart test/infrastructure/observability/sentry_observability_test.dart
git commit -m "feat(observability): add SentryObservability adapter"
```

---

### Task 9: Wire `bootstrap.dart`

**Files:**
- Modify: `lib/src/bootstrap/bootstrap.dart`
- Test: manual verification only (bootstrap has no existing unit test — it is exercised by every widget/integration test that boots the app; this task's correctness is proven by Task 12's full-suite run and Task 13's manual check)

- [ ] **Step 1: Read the current file**

Current content (already read earlier in this session, reproduced here so this step is self-contained):

```dart
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/app/lyron_app.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/infrastructure/config/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = SupabaseConfig.fromEnvironment();
  await Supabase.initialize(url: config.url, publishableKey: config.anonKey);
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
```

- [ ] **Step 2: Replace the imports and `bootstrap()` function**

Replace everything from the top of the file through the end of `bootstrap()` (i.e. everything above `class _BootstrapScope`) with:

```dart
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:lyron_app/src/app/lyron_app.dart';
import 'package:lyron_app/src/application/observability/observability.dart';
import 'package:lyron_app/src/application/observability/observability_providers.dart';
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
      options.captureFailedRequests = false;
    }, appRunner: initSupabaseAndRun);
  } else {
    await initSupabaseAndRun();
  }
}
```

Leave `class _BootstrapScope` and `class _BootstrapScopeState` exactly as
they are — nothing in this task changes them.

- [ ] **Step 3: Run analyzer**

```bash
flutter analyze lib/src/bootstrap/bootstrap.dart
```

Expected: no errors. If `SentryFlutter.init`'s `appRunner` parameter type
doesn't accept a `Future<void> Function()` closure the way this plan
assumes, check `flutter_test` output for the exact expected signature and
adjust.

- [ ] **Step 4: Run the full existing test suite**

```bash
flutter test
```

Expected: PASS — this task changes app bootstrap wiring but not any
tested unit in isolation (no widget test boots through real `bootstrap()`
today; confirm that assumption holds by checking test output for any
new failures rather than assuming).

- [ ] **Step 5: Commit**

```bash
git add lib/src/bootstrap/bootstrap.dart
git commit -m "feat(observability): wire Sentry init and TracingHttpClient into bootstrap"
```

---

### Task 10: Instrument `SongCatalogController`

This is the core instrumentation task. `song_catalog_controller.dart` is
long and stateful — every edit below is anchored to exact existing lines
so it can be applied as a precise diff rather than a rewrite.

**Files:**
- Modify: `lib/src/application/song_library/song_catalog_controller.dart`
- Modify: `test/application/song_library/song_catalog_controller_test.dart`

- [ ] **Step 1: Add the `Observability` field and constructor parameter**

In `song_catalog_controller.dart`, add an import:

```dart
import 'package:lyron_app/src/application/observability/observability.dart';
```

In the constructor's parameter list, add one optional named parameter
(after `this._refreshInterval = _defaultRefreshInterval,` at the end of
the existing list):

```dart
    this._refreshInterval = _defaultRefreshInterval,
    Observability? observability,
```

and change the constructor's initializer list (`:` clause) from:

```dart
  }) : _foregroundState = foregroundState ?? _AlwaysForegroundState(),
       _state = const CatalogSnapshotState.initial() {
```

to:

```dart
  }) : _foregroundState = foregroundState ?? _AlwaysForegroundState(),
       _observability = observability ?? const NoopObservability(),
       _state = const CatalogSnapshotState.initial() {
```

Add the field declaration next to the other final fields (near
`final Duration _refreshInterval;`):

```dart
  final Observability _observability;
```

- [ ] **Step 2: Rename `_refreshCatalog` to `_refreshCatalogBody` and add the thin wrapper**

Change the method signature from:

```dart
  Future<void> _refreshCatalog() async {
    final generation = _refreshGeneration;
```

to:

```dart
  Future<void> _refreshCatalog() async {
    await _observability.runInSpan(
      'song_catalog.refresh',
      'business.refresh',
      (_) => _refreshCatalogBody(),
    );
  }

  Future<void> _refreshCatalogBody() async {
    _observability.addBreadcrumb(
      'song_catalog.refresh started',
      category: 'song_catalog',
    );
    final generation = _refreshGeneration;
```

Every other line of the original method body stays exactly as it was —
this rename only touches the method's own opening two lines; nothing
inside the body (the dozens of early returns, state transitions, etc.)
changes shape.

- [ ] **Step 3: Wrap the organization-id lookup**

Find (inside `_refreshCatalogBody`, unchanged from the original method):

```dart
    try {
      organizationId = await _resolveOrganizationId();
    } catch (error) {
```

Change to:

```dart
    try {
      organizationId = await _observability.runInSpan(
        'membership.resolve',
        'business.refresh',
        (_) => _resolveOrganizationId(),
      );
    } catch (error) {
```

- [ ] **Step 4: Wrap the session-verifier call**

Find:

```dart
    final sessionStatus = await _sessionVerifier();
    if (_isStale(generation)) {
      return;
    }

    if (sessionStatus == CatalogSessionStatus.expired) {
```

Change the first line to:

```dart
    final sessionStatus = await _observability.runInSpan(
      'auth.verify_session',
      'business.refresh',
      (_) => _sessionVerifier(),
    );
    if (_isStale(generation)) {
      return;
    }

    if (sessionStatus == CatalogSessionStatus.expired) {
```

- [ ] **Step 5: Wrap the `listSongs` call**

Find:

```dart
    try {
      final summaries = await _remoteRepository.listSongs();
      if (summaries.isEmpty) {
```

Change to:

```dart
    try {
      final summaries = await _observability.runInSpan(
        'http.client',
        'http.client',
        (_) => _remoteRepository.listSongs(),
      );
      if (summaries.isEmpty) {
```

- [ ] **Step 6: Wrap the `getSongSource` fan-out**

Find:

```dart
      final sources = await Future.wait(
        summaries.map((summary) => _remoteRepository.getSongSource(summary.id)),
      );
      if (_isStale(generation)) {
```

Change to:

```dart
      final sources = await _observability.runInSpan(
        'http.client',
        'http.client',
        (_) => Future.wait(
          summaries.map((summary) => _remoteRepository.getSongSource(summary.id)),
        ),
      );
      if (_isStale(generation)) {
```

- [ ] **Step 7: Wrap the Drift write, and add success/failure breadcrumbs**

Find:

```dart
      await _store.replaceActiveSnapshot(
        userId: context.userId,
        organizationId: context.organizationId,
        summaries: summaries,
        sources: sources,
        refreshedAt: DateTime.now().toUtc(),
      );
      if (_isStale(generation)) {
        return;
      }

      _setStateIfCurrent(
        generation,
        _state.copyWith(
          context: context,
          connectionStatus: CatalogConnectionStatus.online,
          refreshStatus: CatalogRefreshStatus.idle,
          sessionStatus: CatalogSessionStatus.verified,
          hasCachedCatalog: true,
        ),
      );
    } catch (error) {
```

Change to:

```dart
      await _observability.runInSpan(
        'db.write',
        'db.write',
        (_) => _store.replaceActiveSnapshot(
          userId: context.userId,
          organizationId: context.organizationId,
          summaries: summaries,
          sources: sources,
          refreshedAt: DateTime.now().toUtc(),
        ),
      );
      if (_isStale(generation)) {
        return;
      }

      _observability.addBreadcrumb(
        'song_catalog.refresh succeeded',
        category: 'song_catalog',
      );
      _setStateIfCurrent(
        generation,
        _state.copyWith(
          context: context,
          connectionStatus: CatalogConnectionStatus.online,
          refreshStatus: CatalogRefreshStatus.idle,
          sessionStatus: CatalogSessionStatus.verified,
          hasCachedCatalog: true,
        ),
      );
    } catch (error) {
      _observability.addBreadcrumb(
        'song_catalog.refresh failed',
        category: 'song_catalog',
        level: BreadcrumbLevel.warning,
      );
```

Nothing else in the `catch (error) { ... }` block below this point
changes.

- [ ] **Step 8: Run analyzer on the file**

```bash
flutter analyze lib/src/application/song_library/song_catalog_controller.dart
```

Expected: no errors. If a `runInSpan` type-inference error appears (e.g.
`(_) => _resolveOrganizationId()` not matching
`Future<T> Function(ObservabilitySpan span) body`), the parameter name
`_` is fine for an unused callback parameter in Dart, but double check
the closure's inferred return type `T` matches what the surrounding
`await` expects (e.g. `String?` for organization id) — add an explicit
type argument (`_observability.runInSpan<String?>(...)`) if inference
fails.

- [ ] **Step 9: Run the existing controller test suite**

```bash
flutter test test/application/song_library/song_catalog_controller_test.dart
```

Expected: PASS, unchanged — every existing test constructs
`SongCatalogController` without passing `observability`, so it defaults
to `NoopObservability` and every wrapped call becomes a plain pass-through
(no behavior change, since `NoopObservability.runInSpan` just calls
`body(const NoopObservabilitySpan())` and returns its result). This is
the regression check: if anything in this suite fails, the wrapping
changed a return value's shape or an exception's propagation somewhere,
which the diffs above should not do — `runInSpan` on the happy or error
path always returns/rethrows exactly what `body` returned/threw.

- [ ] **Step 10: Add new tests for the instrumentation itself**

Add this test group to the end of
`test/application/song_library/song_catalog_controller_test.dart` (inside
the existing `void main() { ... }`, as a sibling `group` to what's already
there):

```dart
group('observability instrumentation', () {
  test('a successful refresh records start and success breadcrumbs', () async {
    final recorder = _RecordingObservability();
    final controller = _buildControllerForObservabilityTest(
      observability: recorder,
    );

    await controller.refreshCatalog();

    expect(
      recorder.breadcrumbMessages,
      containsAllInOrder([
        'song_catalog.refresh started',
        'song_catalog.refresh succeeded',
      ]),
    );
  });

  test('a failed refresh records the root span and the failure breadcrumb', () async {
    final recorder = _RecordingObservability();
    final controller = _buildControllerForObservabilityTest(
      observability: recorder,
      repository: _FailingSongRepository(),
    );

    await controller.refreshCatalog();

    expect(recorder.spanNames, contains('song_catalog.refresh'));
    expect(recorder.breadcrumbMessages, contains('song_catalog.refresh failed'));
  });
});
```

Add the supporting test doubles near the file's other private test-double
classes (e.g. next to `_FakeSongRepository`):

```dart
class _RecordingObservability extends NoopObservability {
  final List<String> spanNames = [];
  final List<String> breadcrumbMessages = [];

  @override
  Future<T> runInSpan<T>(
    String name,
    String operation,
    Future<T> Function(ObservabilitySpan span) body, {
    Map<String, Object?>? data,
  }) {
    spanNames.add(name);
    return body(const NoopObservabilitySpan());
  }

  @override
  void addBreadcrumb(
    String message, {
    String? category,
    BreadcrumbLevel level = BreadcrumbLevel.info,
    Map<String, Object?>? data,
  }) {
    breadcrumbMessages.add(message);
  }
}

class _FailingSongRepository implements SongRepository {
  @override
  Future<List<SongSummary>> listSongs() => Future.error(Exception('boom'));

  @override
  Future<SongSource> getSongSource(String id) =>
      Future.error(Exception('unreached'));

  @override
  Future<SongSummary?> getSongSummaryBySlug(String slug) =>
      Future.error(Exception('unreached'));
}
```

You will need to build `_buildControllerForObservabilityTest` (or inline
the equivalent `SongCatalogController(...)` construction directly in each
test) by copying the pattern the existing tests in this file already use
to construct a controller with a signed-in session, a resolvable
organization id, and a verified session status — read the top of the
existing test file's `setUp`/helper functions first and reuse whatever
helper already exists there rather than duplicating a new one; the exact
existing helper name and shape were not re-transcribed into this plan to
avoid drifting out of sync with the real file, since it will have
changed by the time you run this step. If no reusable helper exists,
construct the controller directly, mirroring the constructor call
pattern already visible in "the failing session" or "the happy path"
tests elsewhere in the same file, and pass `observability: recorder` as
the new parameter added in Step 1.

- [ ] **Step 11: Run test to verify the new tests fail first, then pass**

```bash
flutter test test/application/song_library/song_catalog_controller_test.dart
```

Run this once before Step 10's test bodies are correct (expect FAIL,
confirming the test actually exercises new code and isn't vacuously
true), then again after fixing any construction issues (expect PASS, all
tests in the file, old and new).

- [ ] **Step 12: Commit**

```bash
git add lib/src/application/song_library/song_catalog_controller.dart test/application/song_library/song_catalog_controller_test.dart
git commit -m "feat(observability): instrument SongCatalogController's refresh as a root trace"
```

---

### Task 11: Wire `observabilityProvider` into `SongCatalogController`'s provider

**Files:**
- Modify: `lib/src/application/song_catalog_providers.dart`

- [ ] **Step 1: Pass the provider into the controller construction**

In `song_catalog_providers.dart`, find (inside `songCatalogControllerProvider`):

```dart
      final controller = SongCatalogController(
        store: ref.watch(songCatalogStoreProvider),
```

Change to:

```dart
      final controller = SongCatalogController(
        store: ref.watch(songCatalogStoreProvider),
        observability: ref.watch(observabilityProvider),
```

(Placement among the other named arguments does not matter — Dart named
arguments are order-independent; putting it first, right after `store:`,
just keeps it visually grouped with the other direct dependencies rather
than buried among the callback parameters further down.)

- [ ] **Step 2: Run analyzer and the provider test**

```bash
flutter analyze lib/src/application/song_catalog_providers.dart
flutter test test/application/song_catalog_providers_test.dart
```

Expected: no errors, existing tests PASS (they don't override
`observabilityProvider`, so it resolves to `NoopObservability` — no
behavior change).

- [ ] **Step 3: Commit**

```bash
git add lib/src/application/song_catalog_providers.dart
git commit -m "feat(observability): inject observabilityProvider into songCatalogControllerProvider"
```

---

### Task 12: Sign-in user-context tagging

**Files:**
- Modify: `lib/src/application/auth_providers.dart`
- Modify: `lib/src/app/lyron_app.dart`
- Test: `test/application/auth_providers_test.dart` (add to existing file)

- [ ] **Step 1: Add the effect provider**

In `auth_providers.dart`, add near `membershipRefreshEffectProvider` (same
file, same pattern):

```dart
/// Attaches/clears pseudonymized identity on the Observability scope as
/// the auth state transitions. Deliberately not a root trace -- sign-in
/// is OAuth-redirect/magic-link based (the initiating call returns
/// immediately; the session arrives later via a stream/deep-link callback
/// in an unrelated async context), so there is no single call tree to
/// wrap. See docs/architecture/decisions/ADR-036-observability-sentry
/// -adapter.md point 8.
final observabilityUserContextEffectProvider = Provider<void>((ref) {
  final observability = ref.watch(observabilityProvider);
  final authController = ref.read(appAuthControllerProvider);

  ref.listen<AppAuthState>(
    appAuthControllerProvider.select((c) => c.state),
    (prev, next) {
      switch (next.status) {
        case AppAuthStatus.signedIn:
          final session = next.session;
          if (session != null) {
            observability.setUserContext(
              userId: session.userId,
              organizationId: authController.lastKnownIdentity?.organizationId,
            );
          }
          return;
        case AppAuthStatus.signedOut:
          observability.clearUserContext();
          return;
        case AppAuthStatus.initializing:
        case AppAuthStatus.sessionExpired:
          return;
      }
    },
    fireImmediately: true,
  );
});
```

Make sure `lyron_app/src/application/observability/observability_providers.dart`'s
`observabilityProvider` is importable here — it already is, via the
`providers.dart` barrel this file is part of (Task 5 added the export);
no new import line should be needed since `auth_providers.dart` is
exported from the same barrel it's consumed through elsewhere in the app.
If the analyzer disagrees, add
`import 'package:lyron_app/src/application/observability/observability_providers.dart';`
directly.

- [ ] **Step 2: Activate the effect provider**

In `lib/src/app/lyron_app.dart`, find:

```dart
    ref.read(deepLinkListenerProvider).start();
    ref.read(membershipRefreshEffectProvider);
    ref.read(planningSyncControllerProvider);
```

Change to:

```dart
    ref.read(deepLinkListenerProvider).start();
    ref.read(membershipRefreshEffectProvider);
    ref.read(observabilityUserContextEffectProvider);
    ref.read(planningSyncControllerProvider);
```

- [ ] **Step 3: Run analyzer**

```bash
flutter analyze lib/src/application/auth_providers.dart lib/src/app/lyron_app.dart
```

Expected: no errors.

- [ ] **Step 4: Add a test**

Add to `test/application/auth_providers_test.dart` (find the existing
`ProviderContainer` construction pattern used by other tests in this file
and reuse it — do not duplicate a second container-building helper):

```dart
test('observabilityUserContextEffectProvider sets and clears user context on auth transitions', () {
  final recorder = _RecordingObservability();
  // Build the container the same way the surrounding tests in this file
  // already do, adding this one override:
  //   observabilityProvider.overrideWithValue(recorder),
  // alongside whatever auth-controller override those tests already use
  // to drive `appAuthControllerProvider` into signedIn/signedOut states.
  // ... construct container, drive state to signedIn with a session ...

  container.read(observabilityUserContextEffectProvider);

  // after driving to signedIn:
  expect(recorder.lastUserId, isNotNull);

  // after driving to signedOut:
  expect(recorder.userContextCleared, isTrue);
});
```

with the recorder:

```dart
class _RecordingObservability extends NoopObservability {
  String? lastUserId;
  bool userContextCleared = false;

  @override
  void setUserContext({required String userId, String? organizationId}) {
    lastUserId = userId;
  }

  @override
  void clearUserContext() {
    userContextCleared = true;
  }
}
```

This step is deliberately less prescriptive than earlier tasks about the
exact container/override wiring: `auth_providers_test.dart`'s existing
setup for driving `appAuthControllerProvider` through signed-in/signed-out
transitions is nontrivial (see the ADR-029 reauth machinery referenced in
`architecture.md`) and already has an established test pattern in that
file — read it first and match it, rather than inventing a second way to
drive the same state machine.

- [ ] **Step 5: Run the test**

```bash
flutter test test/application/auth_providers_test.dart
```

Expected: PASS, including the new test and every pre-existing one in the
file unchanged.

- [ ] **Step 6: Commit**

```bash
git add lib/src/application/auth_providers.dart lib/src/app/lyron_app.dart test/application/auth_providers_test.dart
git commit -m "feat(observability): attach pseudonymized user context on sign-in/out"
```

---

### Task 13: Full verification pass

**Files:** none (verification only)

- [ ] **Step 1: Full analyzer run**

```bash
flutter analyze
```

Expected: no new errors or warnings versus the pre-existing baseline.

- [ ] **Step 2: Full test suite**

```bash
flutter test
```

Expected: PASS, every test in the suite, not just the ones touched by
this plan — this is the regression check for the whole branch.

- [ ] **Step 3: Confirm the app still boots with telemetry disabled (default, no DSN)**

```bash
flutter run -d <a connected device or simulator, or use the Claude_Browser preview tooling if targeting web>
```

Expected: app launches normally, song library screen loads and refreshes
exactly as before this branch — since `SENTRY_DSN` is unset by default,
`bootstrap()` takes the `NoopObservability`/no-`SentryFlutter.init` path,
so this proves the feature is fully inert until a DSN is supplied.

- [ ] **Step 4: Confirm the app still boots with a placeholder DSN (Sentry path exercised, no real project needed)**

```bash
flutter run --dart-define=SENTRY_DSN=https://public@o0.ingest.sentry.io/0 -d <device>
```

Expected: app launches normally (this DSN is syntactically valid but
points at no real Sentry project, so `SentryFlutter.init` succeeds and
just fails silently to deliver events over the network — this step only
proves the *initialization and wiring* path doesn't crash, not that
events reach a real dashboard; that is the spike runbook's job once a
real DSN exists).

- [ ] **Step 5: Update the spike doc's "Runbook result" placeholder**

In `docs/specs/2026-08-28-w3c-traceparent-correlation-spike.md`, leave the
"Not yet run" note as-is — it is accurate until the user actually
provisions a Sentry project and runs the manual steps. Do not mark it
done based on Step 3/4 above; those only prove the code doesn't crash; a
verification of "did not crash" and "shows up correlated in two separate
dashboards" (rather than "did not crash") are two different claims.

- [ ] **Step 6: Final commit (docs sync, if anything drifted)**

If any of the above steps required deviating from this plan's exact code
(an API signature mismatch caught by the analyzer, for instance), make
sure `docs/specs/2026-08-28-observability-foundation.md` and ADR-036 still
accurately describe what was actually built — update them in the same
commit as whatever code change caused the drift, per this repo's AGENTS.md
rule that documentation lands with the change that justifies it, not as
follow-up cleanup.

```bash
git status
```

Expected: clean working tree (everything already committed task-by-task
above) or, if Step 6 required a doc fix, one final commit for it.

---

## After this plan

Per AGENTS.md workflow: open a pull request from `feat/observability-sentry-foundation` once this plan's tasks are all committed and Task 13 passes, rather than merging directly to `main`. Do not merge without green CI. The next slice (remaining use cases from `docs/deferred/2026-08-28-observability-remaining-use-cases.md`) is intentionally not part of this plan.
