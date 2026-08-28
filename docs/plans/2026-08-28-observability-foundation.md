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

    test('runInSpan propagates a thrown error from body', () async {
      await expectLater(
        observability.runInSpan('n', 'o', (span) async => throw Exception('boom')),
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

Expected: PASS (7 tests).

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

In `lib/src/application/providers.dart`, this project's lint rules include
`directives_ordering`, and the file's existing exports are alphabetical
(`auth_providers.dart`, `core_providers.dart`, `planning_providers.dart`,
`song_catalog_providers.dart`). Insert the new line alphabetically between
`core_providers.dart`'s export block and `planning_providers.dart`'s:

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

const _sampleTraceParent =
    '00-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-bbbbbbbbbbbbbbbb-01';

void main() {
  test('injects the traceparent header when a span is active', () async {
    final inner = _RecordingInnerClient();
    // `_FakeObservability` is instantiated non-const here: `'a' * 32` (String
    // repetition) is not a const-evaluable expression in Dart, so `const
    // _FakeObservability('00-${'a' * 32}-...')` would fail to compile. Use
    // the plain literal `_sampleTraceParent` above instead of repetition —
    // it is defined as a `const` top-level string precisely so it can be
    // reused across the two tests below without re-typing 48 hex characters.
    final client = TracingHttpClient(
      inner,
      _FakeObservability(_sampleTraceParent),
      isWeb: false,
    );

    await client.get(Uri.parse('https://example.supabase.co/rest/v1/songs'));

    expect(inner.lastRequest!.headers['traceparent'], _sampleTraceParent);
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
      _FakeObservability(_sampleTraceParent),
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
      // Deliberately NOT setting `options.automatedTestMode = true` here:
      // it is annotated `@internal` in the SDK source and would trip
      // `invalid_use_of_internal_member` under `flutter analyze`. It is
      // also unnecessary -- `SentryOptions.transport` already defaults to
      // `NoOpTransport()` (confirmed in the installed SDK source), so no
      // real network call happens regardless of whether the DSN above
      // points at a real project. The DSN only needs to be
      // *syntactically* valid for `Sentry.init` to complete successfully.
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
        // Explicit, not relying on finish()'s default: a root Transaction
        // defaults an unset status to `ok` on finish, but a plain child
        // span (from `startChild`) does not reliably do the same --
        // setting it explicitly here covers both cases identically.
        sentrySpan.status = const SpanStatus.ok();
        return result;
      } catch (error, stackTrace) {
        // `internalError` here is a span-status marker ("this span did
        // not complete normally"), not a Sentry issue -- captureException
        // is never called here, so classified/expected failures (e.g. a
        // ConnectivityFailure during an offline refresh) never file an
        // issue just because they passed through a span. See ADR-036
        // point 4.
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
    // `toSentryTrace()` is the public API for reading a span's trace/span
    // id and sampling decision. `ISentrySpan.context`/`.samplingDecision`
    // also exist but are annotated `@internal` in the SDK source -- using
    // them directly would trip `invalid_use_of_internal_member` under
    // `flutter analyze`.
    final trace = span.toSentryTrace();
    return buildTraceParent(
      traceId: trace.traceId.toString(),
      spanId: trace.spanId.toString(),
      sampled: trace.sampled ?? true,
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
      // Must also clear the 'organization' context setUserContext sets --
      // clearing only the user would leave a stale organization id
      // attached to events fired after sign-out.
      scope.removeContexts('organization');
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

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/infrastructure/observability/sentry_observability_test.dart
```

Expected: PASS (9 tests). If the "matches the real active span's ids" or
nested-span tests fail on an API shape mismatch (e.g. `toSentryTrace()`
not returning the fields this plan assumes), re-check against the
installed package: `grep -n "class SentryTraceHeader" -A 15 $(dart pub cache dir 2>/dev/null || echo ~/.pub-cache)/hosted/pub.dev/sentry-*/lib/src/protocol/sentry_trace_header.dart` and adjust the adapter, not the test's intent.

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

Current content (re-read at plan-writing time so this step is
byte-accurate — do not trust memory or an earlier partial read; re-read
the real file yourself before editing if any doubt remains):

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
  // supabase_flutter 2.16 deprecated anonKey in favour of publishableKey; both
  // feed the same effective key, so the legacy anon JWT keeps working. The
  // SUPABASE_ANON_KEY dart-define keeps its name — that is an environment
  // contract shared with the scripts and CI, not something to rename inside a
  // dependency bump.
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
        'http.client',
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
      'http.client',
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
        'song_catalog.list_songs',
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
        'song_catalog.fetch_sources',
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
        'song_catalog.write_snapshot',
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

The existing top-level `group('SongCatalogController', () { ... })` in
this file (read it — its `setUp` already builds an in-memory `database`,
`store`, `remoteRepository` (a `_FakeSongRepository`, which already has a
settable `listSongsError` field for exactly this purpose — do not
introduce a second failing-repository class), and `lifecycle`, with a
`tearDown` that closes `database`) is the group to nest the new tests
inside, as a **nested** `group('observability instrumentation', () {
... })` — not a sibling at the top level, which would get none of that
`setUp`/`tearDown`. Add it as the last member of the outer group, right
before that group's own closing `});`:

```dart
group('observability instrumentation', () {
  test('a successful refresh records the start and success breadcrumbs', () async {
    final recorder = _RecordingObservability();
    final controller = SongCatalogController(
      onImplausibleEmptySnapshot:
          ({required userId, required organizationId}) async {},
      store: store,
      localDataLifecycle: lifecycle,
      remoteRepository: remoteRepository,
      authSessionReader: () =>
          const AppAuthSession(userId: 'user-1', email: 'demo@lyron.local'),
      organizationReader: () async => 'org-1',
      sessionVerifier: () async => CatalogSessionStatus.verified,
      observability: recorder,
    );

    await controller.refreshCatalog();

    expect(
      recorder.breadcrumbMessages,
      ['song_catalog.refresh started', 'song_catalog.refresh succeeded'],
    );
    expect(recorder.spanNames.first, 'song_catalog.refresh');
  });

  test('a failed refresh records the failure breadcrumb, not the success one', () async {
    final recorder = _RecordingObservability();
    remoteRepository.listSongsError = Exception('boom');
    final controller = SongCatalogController(
      onImplausibleEmptySnapshot:
          ({required userId, required organizationId}) async {},
      store: store,
      localDataLifecycle: lifecycle,
      remoteRepository: remoteRepository,
      authSessionReader: () =>
          const AppAuthSession(userId: 'user-1', email: 'demo@lyron.local'),
      organizationReader: () async => 'org-1',
      sessionVerifier: () async => CatalogSessionStatus.verified,
      observability: recorder,
    );

    await controller.refreshCatalog();

    expect(recorder.spanNames, contains('song_catalog.refresh'));
    expect(
      recorder.breadcrumbMessages,
      ['song_catalog.refresh started', 'song_catalog.refresh failed'],
    );
  });
});
```

Note why the first test's assertion is a full list-equality
(`breadcrumbMessages, [...]`) rather than `contains(...)`: a `contains`
check on the success path would pass even if the code accidentally
recorded a `'song_catalog.refresh failed'` breadcrumb too, which is
exactly the kind of near-vacuous assertion to avoid — pin the exact
sequence instead.

Add the one supporting test double near the file's other private
test-double classes (e.g. right after `_FakeSongRepository`'s class body,
around line 1723 as of this writing — line numbers drift, find it by the
class name, not the number):

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
```

This needs two new imports at the top of the test file:

```dart
import 'package:lyron_app/src/application/observability/observability.dart';
```

(`AppAuthSession`, `CatalogSessionStatus`, and `SongCatalogController`
are already imported by this file per its existing top-of-file import
list — do not add a second import for any of those.)

- [ ] **Step 11: Run the new tests, confirm they fail first, then pass**

```bash
flutter test test/application/song_library/song_catalog_controller_test.dart
```

Run this immediately after adding Step 10's test bodies but *before*
Steps 1–7's production-code edits exist (i.e. if you are working through
this task strictly in order, temporarily comment out Steps 1–7 or run
this check right after Step 10 lands, before assuming production code is
already in place) — expect FAIL, specifically on the `observability:
recorder` named parameter not existing yet (confirms the test exercises
real code, not a vacuous pass). Once Steps 1–7 are applied, run again —
expect PASS, every test in the file, old and new.

If you are executing this plan task-by-task in the written order (Steps
1–7 already applied before reaching Step 10), the "fails first" run above
is not meaningful — the constructor parameter already exists. In that
case it is enough to run once after Step 10 and confirm PASS; the
regression check in Step 9 already proved the wrapping doesn't change
existing behavior, and Step 10's job is only to prove the new
instrumentation calls happen at all.

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
- Create: `test/application/auth/observability_user_context_effect_test.dart`

There is no `test/application/auth_providers_test.dart` — auth tests live
in `test/application/auth/`, one file per concern (see
`test/application/auth/identity_persistence_wiring_test.dart` for the
closest existing analog: it tests another `ref.listen`-based effect
provider, `lastKnownIdentityPersistenceProvider`, driven through a real
`AppAuthController` plus a fake `AuthRepository` inside a
`ProviderContainer`). This task creates a new file in that directory
rather than appending to a file that doesn't exist.

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
            // organizationId is best-effort: `lastKnownIdentity` may not
            // be populated yet at this exact instant (it is written by a
            // separate persistence effect reacting to the same signedIn
            // transition, with no ordering guarantee relative to this
            // listener) -- this is not re-synced later in this slice. See
            // docs/specs/2026-08-28-observability-foundation.md, "Sign-in
            // is not a root trace in this slice".
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
          return;
        case AppAuthStatus.sessionExpired:
          // Deliberate no-op, not an oversight: sessionExpired is
          // offline-authenticated access, not sign-out (ADR-020) -- the
          // same user is still using the app without a live session, so
          // clearing their identity here would misrepresent telemetry for
          // that entire offline-authenticated window as anonymous.
          return;
      }
    },
    fireImmediately: true,
  );
});
```

This provider is defined in the same file (`auth_providers.dart`) that
already needs `observabilityProvider`, but that provider lives in a
different file (`observability_providers.dart`) that `auth_providers.dart`
does not otherwise import — the `providers.dart` barrel *exports*
`auth_providers.dart`'s own symbols outward for other files to consume,
it does not inject symbols *into* `auth_providers.dart`. Add the import
directly:

```dart
import 'package:lyron_app/src/application/observability/observability.dart';
import 'package:lyron_app/src/application/observability/observability_providers.dart';
```

(`observability.dart` supplies the `AppAuthState`-independent
`Observability` type used in the provider body's static analysis of
`observability.setUserContext(...)`/`.clearUserContext()`;
`observability_providers.dart` supplies `observabilityProvider` itself.
Both are new imports for this file.)

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

- [ ] **Step 4: Write the failing test**

Create `test/application/auth/observability_user_context_effect_test.dart`:

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/app_auth_controller.dart';
import 'package:lyron_app/src/application/auth/auth_repository.dart';
import 'package:lyron_app/src/application/observability/observability.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/auth/sign_in_method.dart';

void main() {
  late _FakeAuthRepository authRepository;
  late AppAuthController authController;

  setUp(() {
    authRepository = _FakeAuthRepository();
    addTearDown(authRepository.dispose);
    authController = AppAuthController(authRepository);
  });

  test('signedIn attaches the pseudonymized user id', () async {
    final recorder = _RecordingObservability();
    authRepository.currentSession = const AppAuthSession(
      userId: 'user-1',
      email: 'user@example.com',
    );
    final container = ProviderContainer(
      overrides: [
        appAuthControllerProvider.overrideWith((_) => authController),
        observabilityProvider.overrideWithValue(recorder),
      ],
    );
    addTearDown(container.dispose);

    container.read(observabilityUserContextEffectProvider);
    await authController.restoreSession();
    await Future<void>.delayed(Duration.zero);

    expect(recorder.lastUserId, 'user-1');
  });

  test('signedOut clears the user context', () async {
    final recorder = _RecordingObservability();
    authRepository.currentSession = const AppAuthSession(
      userId: 'user-1',
      email: 'user@example.com',
    );
    final container = ProviderContainer(
      overrides: [
        appAuthControllerProvider.overrideWith((_) => authController),
        observabilityProvider.overrideWithValue(recorder),
      ],
    );
    addTearDown(container.dispose);

    container.read(observabilityUserContextEffectProvider);
    await authController.restoreSession();
    await Future<void>.delayed(Duration.zero);
    expect(recorder.lastUserId, 'user-1');

    await authController.signOut();
    await Future<void>.delayed(Duration.zero);

    expect(recorder.userContextCleared, isTrue);
  });
}

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

// Minimal fake covering every method on the real AuthRepository interface,
// copied in shape from the equivalent fake in
// test/application/auth/identity_persistence_wiring_test.dart -- kept
// local (not shared) per this codebase's existing convention of one
// private test-double class per test file rather than a shared fakes
// module.
class _FakeAuthRepository implements AuthRepository {
  final _controller = StreamController<AppAuthSession?>.broadcast();
  AppAuthSession? currentSession;

  void dispose() {
    _controller.close();
  }

  @override
  Future<AppAuthSession?> restoreSession() async => currentSession;

  @override
  Stream<AppAuthSession?> watchSession() => _controller.stream;

  @override
  Future<void> signInWithOAuth(
    SignInMethod method, {
    required String redirectTo,
  }) async {}

  @override
  Future<void> sendMagicLink({
    required String email,
    required String redirectTo,
  }) async {}

  @override
  Future<void> signOut() async {
    currentSession = null;
    _controller.add(null);
  }

  @override
  Future<void> deleteAccount() async {}
}
```

- [ ] **Step 5: Run test to verify it fails**

```bash
flutter test test/application/auth/observability_user_context_effect_test.dart
```

Expected: FAIL — `observabilityUserContextEffectProvider` does not exist
yet (Step 1 hasn't been applied) or, if run after Step 1, verify it was
genuinely failing before Step 1 by checking out the file at its
pre-Step-1 state — do not skip this check just because Steps 1-2 are
already in place by the time you reach this step in a strict top-to-bottom
run.

- [ ] **Step 6: Run test to verify it passes**

```bash
flutter test test/application/auth/observability_user_context_effect_test.dart
```

Expected: PASS (2 tests).

- [ ] **Step 7: Run analyzer on the modified files**

```bash
flutter analyze lib/src/application/auth_providers.dart lib/src/app/lyron_app.dart test/application/auth/observability_user_context_effect_test.dart
```

Expected: no errors.

- [ ] **Step 8: Commit**

```bash
git add lib/src/application/auth_providers.dart lib/src/app/lyron_app.dart test/application/auth/observability_user_context_effect_test.dart
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
