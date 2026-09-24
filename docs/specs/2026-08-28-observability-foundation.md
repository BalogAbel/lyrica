# Spec: Observability Foundation (Sentry-backed, backend-swappable)

## Status

Approved for implementation, and implemented. Revised after an adversarial
opus review found several blocking design defects in the first draft
(broken interface signature, error-to-trace linkage silently defeated by
`bindToScope: false`, a web CORS hazard, unsound root-trace placement,
and a bootstrap dependency-injection ordering gap). That revision fixed
all of them — see "Revision notes" at the end for the full list and
rationale. Execution and PR review then changed several details (installed
SDK version, PII scrub policy, finished-span and telemetry-delivery
behavior, bootstrap structure, ANR); this document has been synced to the
as-built code, and "Revision 2" in the revision notes lists what changed
and why.

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
  Supabase request (native platforms; see the web caveat below).
- No tokens/credentials or personal identifiers (email, display name,
  etc.) ever reach Sentry. `user_id`/`organization_id` may be attached as
  pseudonymized context. ChordPro content, lyrics, plan/session text, and
  other business/domain content — including RPC parameter values that
  carry it — are **not** treated as sensitive: they may appear in
  span/breadcrumb data or exception context when it helps debugging (per
  explicit product direction — this is a narrower policy than PII
  scrubbing convention elsewhere might suggest, and deliberately so).
- Application code depends only on a thin first-party `Observability`
  abstraction, never directly on the Sentry API, so a future swap to
  OpenTelemetry does not require touching call sites.

## Non-goals (explicit, per direction from product/architecture)

- OpenTelemetry Dart SDK, OTLP gateway, Supabase Log Drain, or self-hosted
  Grafana/Loki/Tempo. These may arrive in a later slice; Sentry is the only
  telemetry backend introduced here.
- Native crash symbol upload wiring (Sentry Android Gradle plugin, iOS
  dSYM upload in CI) **and** Dart-level obfuscation/`--split-debug-info`
  symbolication (`sentry_dart_plugin`). Both modify the CI/CD pipeline and
  belong to the roadmap's Phase 9 (production readiness / release
  pipeline), not this slice. Dart-side native crash *capture* (via
  `sentry_flutter`'s bundled native SDKs) ships now; *readable*
  (symbolicated) stack traces — native and Dart-obfuscated alike — are
  deferred until that pipeline work lands.
- Instrumenting every use case in the app. This slice instruments one
  root trace end-to-end (song catalog refresh, with the Supabase
  network call, the membership/session RPCs, and the Drift write each as
  a child span) to prove the pattern. Sign-in contributes only
  pseudonymized user-context tagging, not a root trace of its own — see
  "Business ops = root traces" below for why. Remaining use cases
  (planning mutation sync, discard, storage eviction, unified sync
  overview) are explicitly deferred — see
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
  observability_providers.dart  # observabilityProvider + the bootstrap-time
                                 # singleton holder (see "Sentry configuration")

lib/src/infrastructure/observability/
  sentry_observability.dart     # SentryObservability adapter
  w3c_trace_context.dart        # pure traceparent builder
  tracing_http_client.dart      # http.Client wrapper injecting traceparent

lib/src/infrastructure/config/
  sentry_config.dart            # SentryConfig.fromEnvironment()
```

`Observability` surface:

```dart
abstract class Observability {
  /// Runs [body] as a span named [name] with operation [operation]. If
  /// there is already an active span in the current Dart Zone, the new
  /// span is its child; otherwise it is a new root trace (Sentry
  /// transaction). An ambient span that has already finished does not
  /// count as active: a new root is started instead (see the Zone
  /// caveats below). The span is finished automatically when [body]
  /// completes or throws, without the returned future waiting for
  /// telemetry delivery; on throw,
  /// [ObservabilitySpanStatus.internalError] is set before the exception
  /// is rethrown unmodified.
  ///
  /// [body] is executed inside a new Zone in which this span is the
  /// ambient "current span" ([currentSpan], [currentTraceParent]) for the
  /// duration of [body] — including for code called deep inside [body]'s
  /// call stack that has no explicit reference to the span (e.g.
  /// `TracingHttpClient`, invoked from inside Supabase's own internals).
  ///
  /// Caveat for future call sites: `unawaited(observability.runInSpan(...))`
  /// fired from inside another `runInSpan`'s [body] inherits that Zone and
  /// becomes its child, not a new root — this is correct when the
  /// fired-and-forgotten operation is genuinely a sub-step of the
  /// enclosing business operation, and wrong if it is meant to be an
  /// independent root trace. This slice has no call site where that
  /// ambiguity arises (see "Business ops = root traces" for why sign-in
  /// was deliberately kept out of the root-trace set for this reason); a
  /// future instrumentation pass that adds one must make the call
  /// explicitly outside any enclosing `runInSpan` body.
  ///
  /// A second caveat: a Zone value outlives the span it names, so work
  /// scheduled inside [body] (a `Timer`, or a microtask such as Riverpod
  /// notifying dependents after a refresh) runs later in this span's Zone,
  /// typically after the span has finished. A finished ambient span is
  /// treated as absent: `runInSpan` there starts a new root,
  /// [currentSpan] is a no-op span, [currentTraceParent] is null and
  /// [captureException] attaches no span.
  Future<T> runInSpan<T>(
    String name,
    String operation,
    Future<T> Function(ObservabilitySpan span) body, {
    Map<String, Object?>? data,
  });

  /// The active span in the current Zone. Never null — returns a
  /// [NoopObservabilitySpan] when there is no active span (no enclosing
  /// `runInSpan`, the enclosing span already finished, or telemetry
  /// disabled), so callers never need to branch on whether tracing is
  /// active.
  ObservabilitySpan get currentSpan;

  /// W3C `traceparent` header value for the current span, or null if there
  /// is no active span (including a finished one) or the span has invalid
  /// all-zero ids (a no-op span: Sentry not initialised, or the span was
  /// dropped) — an invalid all-zero header is never emitted. Backend-agnostic
  /// name (W3C term, not a Sentry term) so an OpenTelemetry adapter can
  /// implement it the same way.
  String? get currentTraceParent;

  /// Reports a handled error, explicitly linked to the current span (see
  /// "Error reporting semantics" for why this must be explicit rather than
  /// automatic, and how far SDK-auto-captured unhandled errors are linked).
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

  /// [organizationId] is optional because it is not always resolved at the
  /// point a session becomes available (see the sign-in wiring in
  /// "Business ops = root traces"). Both values are pseudonymized Supabase
  /// UUIDs; this method must never be passed an email or display name.
  void setUserContext({required String userId, String? organizationId});

  void clearUserContext();
}

abstract class ObservabilitySpan {
  /// Non-ambient nested span: useful when the caller already holds a span
  /// reference and needs one more level of nesting under it without
  /// wanting that nested span to become the Zone-ambient "current span"
  /// for further code. Most call sites in this slice use
  /// [Observability.runInSpan] instead, specifically because they need the
  /// ambient behavior (e.g. so `TracingHttpClient` sees the network-call
  /// span as current). Prefer `runInSpan` unless you have a concrete
  /// reason not to propagate ambiently.
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
unit tests. They are also the fallback when `SentryFlutter.init` throws (for
example a malformed DSN): the failure is reported through
`FlutterError.reportError` and the app starts without telemetry. This mirrors the project's existing fail-soft pattern for
optional infrastructure rather than the fail-fast `SupabaseConfig` pattern,
because neither a missing nor a broken telemetry DSN may crash the app.

### Span propagation: Dart `Zone`, not Sentry's ambient `Scope`

Sentry's Dart SDK exposes an ambient "current span" via a mutable `Scope`
object (`Sentry.getSpan()`, backed by `Scope.span`). This app has
concurrent independent root operations by design (the unified sync
overview can run song-catalog sync and planning sync at the same time,
though that is not yet instrumented — see the deferred doc). A single
mutable ambient scope would let one root trace's child spans attach to
the other's transaction once that instrumentation lands; getting the
propagation primitive right now, even though this slice's own code paths
never actually exercise two concurrent roots, avoids re-architecting it
later.

`SentryObservability.runInSpan` propagates the active span through a
dedicated `Zone` value, scoped per async call tree. Concurrent
`runInSpan` calls each fork their own zone and cannot clobber each
other's *parent-resolution* (which span is the parent of a new child
span). The underlying Sentry transaction/span is created via
`Sentry.startTransaction`/`ISentrySpan.startChild`, with
`bindToScope: false` — the app's zone-based propagation is authoritative
for parent/child resolution, and Sentry's own scope stack (`Scope.span`)
is deliberately left untouched by `runInSpan`.

This has one real, accepted consequence, spelled out in "Error reporting
semantics" below: Sentry's scope-based trace linkage reads `Scope.span`,
not our Zone key, so an error captured by Sentry's global
`FlutterError.onError`/`PlatformDispatcher.onError` hooks is never linked
to a trace *through the scope*. (The SDK's second, independent route, a
throwable-to-span association, still links errors that propagated through
a `runInSpan`; see below.) We chose this over the alternative (setting
`Scope.span` globally) because the alternative reintroduces exactly the
cross-attachment bug this whole design exists to avoid: two concurrent
`runInSpan` trees mutating the one global `Scope.span` would let a
later-starting root silently steal the earlier one's "current span" out
from under it, which is strictly worse than the accepted gap (an unlinked
unhandled error is still fully reported — it just may not carry a
`trace_id`).

An alternative considered and rejected for *this* propagation problem
(not for the wider SDK): `sentry` 9.x ships a newer "v2" tracing API
(`Sentry.startSpan`/`SentrySpanV2`) with built-in Zone-based ambient
propagation that also avoids scope clobbering. In the 9.28.0 source
reviewed while drafting this spec it has no public API to read "whatever
span is currently active" from arbitrary code that isn't inside its own
callback (only `hub.getActiveSpan()`, marked `@internal`), which is
exactly what `TracingHttpClient` needs (it runs deep inside Supabase's
call stack, with no reference to any span). v1 plus our own Zone key gives
us that read. That API is not available to this slice in any case: the
installed version is `sentry`/`sentry_flutter` 8.14.2 (see "Revision 2"),
and the 8.14.2 sources contain no `SentrySpanV2` or `Sentry.startSpan`.
Revisit v2 once the dependency constraints allow 9.x and it has a public
ambient accessor.

`startChild` on an `ObservabilitySpan` does **not** enter a new Zone — it
creates a Sentry child span but does not make it the Zone-ambient
"current span". Use `runInSpan` for anything that must be visible to
`currentSpan`/`currentTraceParent` from code with no direct span
reference (this is why every child span in this slice, including the one
around each Supabase call, is created via `runInSpan`, not `startChild` —
see "Business ops = root traces" for the concrete call sites).

**Zone values outlive the span they name.** A `Timer` or microtask created
inside a span's body (for example Riverpod notifying dependents after a
refresh) runs later in that span's Zone, usually after the span has
finished. `SentryObservability` therefore ignores a *finished* ambient span
(`runInSpan` marks its handle ended synchronously, before the SDK's
asynchronous finish completes): `runInSpan` called from such a Zone starts
a new root instead of a child of a dead span (the SDK's `startChild` on a
finished transaction silently returns a no-op span with all-zero ids),
`currentSpan` resolves to `NoopObservabilitySpan`, `currentTraceParent` is
null, and `captureException` attaches no span. Without this guard, requests
issued from such deferred work would carry a stale or all-zero
`traceparent` and mis-correlate with a trace that had already ended.
`currentTraceParent` also returns null whenever the trace id or span id is
all zeros (a no-op span: Sentry not initialised, or the span was dropped),
because W3C declares that value invalid.

**Span finish is fire-and-forget.** `runInSpan` sets the span's status and
`throwable` first, marks the handle ended, and then starts `span.finish()`
without awaiting it (`unawaited(_finishQuietly(...))`, which swallows any
error). Finishing a root span awaits the transaction's transport send — on
web an HTTP POST inside the SDK's `HttpTransport` — so awaiting it stalled
the caller (a slow sentry.io delayed `refreshCatalog()`). Accepted
consequences: telemetry delivery failures are silent, and an in-flight
transaction can be lost if the process exits before it is delivered.

### Business ops = root traces, Drift/Supabase = child spans

`runInSpan` starting with no parent in the current zone creates a new
Sentry transaction (root trace). The one root trace in this slice:

- `SongCatalogController._refreshCatalog()` — root trace
  `song_catalog.refresh` / operation `business.refresh`. Pinned
  specifically to the private `_refreshCatalog()` method (the one actually
  gated by the generation/staleness machinery and invoked at most once per
  real refresh attempt), **not** the public `refreshCatalog()` coalescing
  wrapper — wrapping the public method would produce an empty duplicate
  root trace for every caller that gets coalesced onto an in-flight
  refresh instead of triggering a new one.

Nested inside that root trace's body, five separate `runInSpan` calls,
each with a distinct name so they're distinguishable in the Sentry UI
(ambient, so each becomes `currentSpan` for the duration of its own body
— this matters for the two Supabase calls, so `TracingHttpClient` picks
up the *specific* network-call span as the current span, not the root):

- `runInSpan('membership.resolve', 'http.client', ...)` around the
  organization-id RPC lookup (`_resolveOrganizationId()`).
- `runInSpan('auth.verify_session', 'http.client', ...)` around the
  session-verifier's `auth.getUser()` call.
- `runInSpan('song_catalog.list_songs', 'http.client', ...)` around
  `_remoteRepository.listSongs()`.
- `runInSpan('song_catalog.fetch_sources', 'http.client', ...)` around the
  `Future.wait` over `_remoteRepository.getSongSource(...)` calls. This
  span covers the whole fan-out as one unit — if N songs need sources, all
  N Supabase requests share this span's single `parent-id`, so per-request
  correlation granularity is limited to "which refresh", not "which
  specific song fetch", within that batch.
- `runInSpan('song_catalog.write_snapshot', 'db.write', ...)` around
  `_store.replaceActiveSnapshot(...)`.

(Operation strings use Sentry's own convention — `http.client`/`db.write`
— rather than a business-specific string like `business.refresh`, which
was this draft's earlier, since-corrected choice; the root trace itself
keeps `business.refresh` as its operation, since it genuinely is the
top-level business operation.)

None of `SupabaseSongRepository` or `DriftSongCatalogStore` need any
`Observability` dependency injected — the controller already owns every
one of these call sites directly, so wrapping happens at the call site,
not inside the leaf classes. This keeps the blast radius to one file
(`song_catalog_controller.dart`) plus its two provider-wiring call sites,
instead of touching the repository/store constructors (and their
`.testing()` factories) that many other, uninstrumented call sites also
depend on.

A breadcrumb is recorded at the start of `_refreshCatalog()`'s body
(`'song_catalog.refresh started'`, category `song_catalog`) and at the
terminal outcome of the one try/catch block that performs the actual
network refresh and write (`'song_catalog.refresh succeeded'` /
`'song_catalog.refresh failed'`). **Coverage caveat:** `_refreshCatalog`
has roughly a dozen other early-return branches ahead of that try/catch
(session expired, verified-empty-membership resolution, connectivity
fallback with no cached organization, staleness checks) that leave a
`started` breadcrumb with no matching terminal one. These represent "there
was nothing to refresh" or "the session/membership state itself changed"
outcomes, not a failed refresh attempt, and instrumenting each of them
individually was judged out of scope for this slice — the two breadcrumbs
that exist cover the actual network-refresh attempt, which is the
error-prone leg this instrumentation exists to illuminate.

**Sign-in is not a root trace in this slice.** Sign-in in this app is
OAuth-redirect/magic-link based: the call that starts it
(`signInWithOAuth`) returns immediately, and the actual session arrives
later via a stream/deep-link callback that runs in a different async
context entirely — there is no single in-process call tree to wrap in
`runInSpan` the way there is for a refresh. Forcing a root trace around
it would either wrap nothing useful or, worse, wrap the auth-state
listener in `song_catalog_providers.dart` that fires
`unawaited(controller.refreshCatalog())` on the `signedIn` transition —
which would make every post-sign-in refresh an accidental *child* of the
sign-in trace instead of its own root (see the Zone caveat on
`runInSpan` above). Sign-in still gets the pseudonymized identity
attached to every subsequent event: `observabilityUserContextEffectProvider`
(new, in `auth_providers.dart`) is a `ref.listen`-based side-effect
provider — structurally identical to the existing
`membershipRefreshEffectProvider` — that calls
`observability.setUserContext(userId: ..., organizationId: ...)` on the
`signedIn` transition and `observability.clearUserContext()` on
`signedOut`, using the session's `userId` and (best-effort)
`authController.lastKnownIdentity?.organizationId`. It does not touch
`AppAuthController`'s own state machine at all.

**Known gap (found in Task 12 code review, deliberately deferred, not
fixed in this slice):** "best-effort" understates the actual risk —
`lastKnownIdentity` can hold a *different, prior* user's identity (cold
start reloading yesterday's session, or a different-user reauth
mid-session), not merely be null, and the correction written later by
`lastKnownIdentityPersistenceProvider` never re-fires this listener (no
`notifyListeners()` on that write path). The wrong `organizationId` can
therefore stay attached to Sentry's `organization` context for the rest
of the session — a telemetry-only, silent, cross-tenant identifier leak,
not a backend-authorization issue (AGENTS.md rule 5 keeps authorization
backend-enforced regardless of this tag). See
`docs/deferred/2026-08-28-observability-remaining-use-cases.md` for the
full analysis and the suggested userId-match-guard fix.

If `currentSpan` has no active span underneath it (Sentry disabled, or a
call outside any `runInSpan`), it resolves to `NoopObservabilitySpan` —
see the interface note above; nothing in the call sites above needs a
null check.

### Error reporting semantics

- **Unhandled**: `SentryFlutter.init`'s bundled `FlutterError.onError` hook
  and, on native, `PlatformDispatcher.onError` (via `OnErrorIntegration`)
  capture these automatically; on web bootstrap supplies a guarded zone
  instead (see "Sentry configuration"). No application code changes this
  behavior. **Trace linkage is partial.** `sentry` 8.14.2 has two routes
  from a captured event to a trace:
  1. The scope's span (`Scope.span`) at capture time. This design never
     sets it (`bindToScope: false`), so this route never applies.
  2. A throwable-to-span association. When a span whose `throwable` is set
     finishes, `SentrySpan.finish` calls `Hub.setSpanContext`, which records
     `throwable -> (span, transaction name)` in an `Expando` keyed by object
     identity (the first association wins). When the hub later captures an
     event for that same throwable and the event has no trace context yet
     (and tracing is enabled, which it is: `tracesSampleRate = 1.0`), it
     copies that span's trace context and transaction name onto the event.

  `runInSpan` sets `span.throwable = error` for every error that propagates
  out of a body, so an error that crossed a `runInSpan` and is later
  captured by the SDK's automatic hooks **is** trace-linked, to the
  innermost span it crossed (inner spans finish first). It is **not**
  linked when it is thrown outside any `runInSpan`, when it never passes
  through a `runInSpan` boundary (for example a failure inside an unawaited
  future or `Timer` started in a body), or when the SDK captures it before
  the span's finish has recorded the association (`runInSpan` does not
  await the finish). This is derived from reading the SDK source; no
  committed test pins it. The remaining gap is accepted: the alternative
  (mutating `Scope.span` globally) reintroduces cross-trace attribution
  bugs under concurrent root operations.
- **Handled**: explicit `observability.captureException(error, stackTrace)`
  calls at true-bug boundaries. Internally, `SentryObservability` calls
  `Sentry.captureException(error, stackTrace: stackTrace, withScope: (scope) => scope.span = <the Zone's current ISentrySpan, if any>)`
  — this explicitly links the reported error to the correct span *without*
  touching the global ambient scope for anyone else, sidestepping the
  cross-trace risk that ruled out doing this globally in `runInSpan`.
  `runInSpan`'s internal catch block sets
  `ObservabilitySpanStatus.internalError` on the span and rethrows — it
  does **not** call `captureException` itself. Typed control-flow
  exceptions already used throughout the app (`SongNotFoundException`,
  `SongAccessDeniedException`, `ConnectivityFailure`-classified errors)
  are expected outcomes, not bugs; auto-capturing every thrown exception
  inside a span would flood Sentry with noise. Callers decide, at their
  existing error-classification boundary, whether a caught error is
  reportable.
- `bootstrap.dart`'s `closeSharedDatabases().catchError` continues to call
  `FlutterError.reportError` (already auto-captured by Sentry's hook). That
  call site runs during widget disposal, outside any span, so its error is
  never trace-linked — no change needed there.

### PII and secret redaction

Layered, not relying on a single control:

1. `options.sendDefaultPii = false`. (Sentry's actual default is already
   `false` as of this SDK version — verified against the installed
   `sentry_options.dart` source, correcting an earlier draft of this spec
   that claimed the opposite. Setting it explicitly here is still
   worthwhile: it is a security-relevant flag, and stating it inline
   means a future SDK upgrade that changes the default cannot silently
   flip our behavior.)
2. A recursive scrub, `scrubPii` in `sentry_pii_scrub.dart`, applied by
   `SentryObservability` to every span `data` map, breadcrumb `data` map,
   and `captureException` `extra` map before it reaches the Sentry SDK.
   The file's dartdoc is authoritative; in summary:
   - **Keys** are normalized (lower-cased, with `-`, `_`, `.` and
     whitespace removed) and dropped when equal to `authorization`, `jwt`
     or `codeverifier`, or when they end in `token`, `secret`, `password`,
     `cookie` or `apikey` (so `refresh_token`, `x-api-key`,
     `client_secret` and `set-cookie` are all caught). The match is on the
     suffix, not a substring: `token_count` and `tokenizer` are ordinary
     metrics and are kept. ChordPro content, lyrics, and other
     business/domain content are deliberately **not** treated as sensitive
     — per explicit product direction, that content may aid debugging.
   - **Traversal** is recursive over any `Map` (keys stringified), any
     `Iterable` (returned as fixed-length lists) and `Uri` values
     (stringified, then scrubbed as strings).
   - **Strings**: JWTs (`eyJ<seg>.<seg>.<seg>`) anywhere in the string —
     including embedded ones such as `Bearer eyJ...` — and Supabase secret
     keys (`sb_secret_...`) are replaced with `[redacted]`, regardless of
     key. JWT detection is a linear-time scan, deliberately not one regex:
     an unanchored regex is quadratic on hostile input such as
     `'eyJ' * 30000` and would block the main isolate. The string is then
     scrubbed per whitespace-delimited token, preserving the original
     whitespace, so a URL inside an error message is handled while ordinary
     prose is untouched. In a URL-shaped token the userinfo (`user:pass@`)
     is dropped, the whole query string is dropped, and a `key=value`
     fragment (implicit-flow `#access_token=...` deep links) is dropped; a
     plain fragment is kept. A token counts as URL-shaped only with a
     scheme of two or more characters or a `/` before the `?`/`#`, so
     `[C]Hello?[G]World`, `a?b` and `C:\dir\file?.txt` are never mangled.
   - **Email addresses are a documented non-goal**: they are not redacted
     (`mailto:foo@bar.com?subject=hi` keeps the address; only its query is
     dropped). Call sites must not pass them.
   - Policy history: the first draft stripped URL query strings on the
     assumption that PostgREST filter values were sensitive business
     content; the narrowing of the PII policy dropped that rule, leaving
     query strings unscrubbed. PR review then showed that URLs can carry
     credentials in userinfo, query strings and fragments, so URL
     scrubbing was reinstated — for credentials, not for business content.
   - This is defense-in-depth, not a substitute for discipline at call
     sites: **no call site may pass tokens/credentials or personal
     identifiers (email, display name, etc.) as span/breadcrumb data in
     the first place.** ChordPro source, lyrics, and other business
     content are explicitly exempt from this rule — see the Goals section
     above.
   - The **free-text fields** (`runInSpan`'s `name`, a span's
     `description`, a breadcrumb's `message`) are not run through the
     scrub — they are supplied by our own instrumentation code, not by
     arbitrary caller data, so they are reviewed at the call site instead
     (every span name/description added by this slice is a static
     string, never interpolated from request content).
3. `setUserContext` only ever accepts `userId`/`organizationId` — both are
   Supabase UUIDs already opaque/pseudonymous, never email or display
   name. There is no code path to attach email or name to Sentry scope.
   `clearUserContext` removes both the user and the `organization` scope
   context it set (`Scope.setUser(null)` and `Scope.removeContexts
   ('organization')`) — clearing only the user and leaving a stale
   organization id attached to later events would be its own small leak
   of pre-sign-out tenant identity.
4. Documented explicitly in ADR-036: what must never be passed as
   span/breadcrumb `data` values (the same list as point 2's rationale).

(An earlier draft of this section also set `options.captureFailedRequests
= false`, reasoning that it would stop Sentry's automatic failed-request
reporting from double-reporting an already-classified connectivity
failure. That integration only applies to `SentryHttpClient`/the native
HTTP-instrumentation integrations, neither of which this design installs
— `TracingHttpClient` is a plain `http.BaseClient` subclass Sentry's
failed-request integration never sees. The option is harmless either way,
but setting it implied a protection this design doesn't actually need;
dropped rather than kept as a no-op with a misleading rationale attached.)

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

**Bootstrap ordering.** `TracingHttpClient` must exist *before*
`Supabase.initialize` runs, and `Supabase.initialize` must run *before*
`ProviderScope` exists (it runs in `bootstrap()`, ahead of `runApp`) — so
the `Observability` instance cannot be resolved through a Riverpod
provider at the point it is first needed. `observability_providers.dart`
instead holds a plain package-level singleton, set once by
`initObservability` (called from `bootstrap()`), exactly mirroring how `supabaseClientProvider` already
reads the static `Supabase.instance.client` rather than constructing it:

```dart
Observability _currentObservability = const NoopObservability();

void setCurrentObservability(Observability observability) {
  _currentObservability = observability;
}

final observabilityProvider = Provider<Observability>((ref) {
  return _currentObservability;
});
```

`main()` calls `runBootstrapGuarded(bootstrap)`, and `bootstrap()` is:

```dart
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  final observability = await initObservability(
    SentryConfig.fromEnvironment(),
  );

  final supabaseConfig = SupabaseConfig.fromEnvironment();
  await Supabase.initialize(
    url: supabaseConfig.url,
    publishableKey: supabaseConfig.anonKey,
    httpClient: TracingHttpClient(http.Client(), observability),
  );
  runApp(const _BootstrapScope(child: LyronApp()));
}
```

`initObservability` (trimmed; `init` is a test seam defaulting to
`SentryFlutter.init`) initialises Sentry when the config is enabled and
returns the `Observability` the rest of the app must use, also publishing
it through `setCurrentObservability`:

```dart
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
        options.anrEnabled = true;
      });
      observability = const SentryObservability();
    } catch (error, stackTrace) {
      FlutterError.reportError(/* library: 'bootstrap', ... */);
    }
  }
  setCurrentObservability(observability);
  return observability;
}
```

Three decisions are baked into this structure:

- **Sentry is initialised without `appRunner`.** With `appRunner` the SDK
  would run `Supabase.initialize` and `runApp` inside its own
  `runZonedGuarded` on web, and that zone swallows any error the closure
  throws — a `Supabase.initialize` failure would leave `runApp` never
  reached and a blank screen with no visible error, where the pre-Sentry
  behavior was a loud crash. `Supabase.initialize` and `runApp` therefore
  run after `initObservability`, outside any Sentry-managed zone, and a
  Supabase failure stays loud.
- **Fail soft.** If `SentryFlutter.init` throws (for example a malformed
  DSN: `Dsn.parse` throws an `ArgumentError` before any integration is
  installed), the error is reported through `FlutterError.reportError`, the
  app continues, and `NoopObservability` is used. Sentry then stays on its
  `NoOpHub`, so keeping `SentryObservability` would only do pointless work
  against a disabled hub. `TracingHttpClient` is built from the returned
  value, never from a value picked before init.
- **Web error capture is supplied by `runBootstrapGuarded`.** On web
  (`kIsWeb`) `sentry_flutter` installs no `OnErrorIntegration`
  (`isOnErrorSupported = !isWeb && ...`, because Flutter Web does not
  deliver `Future` errors through `PlatformDispatcher.onError`), and
  without `appRunner` it installs no zone either, so uncaught asynchronous
  errors would be lost. `runBootstrapGuarded` therefore runs the whole
  `bootstrap()` (including `WidgetsFlutterBinding.ensureInitialized()` and
  `runApp`, which must share one zone) in a single `runZonedGuarded`.
  Its handler, `reportUncaughtZoneError`, first prints the error locally
  with `FlutterError.dumpErrorToConsole` (which does not re-enter
  `FlutterError.onError`, so nothing is swallowed and nothing is captured
  twice) and then calls `Sentry.captureException`, a no-op on the `NoOpHub`
  when Sentry is not initialised; a failing capture is contained. A failure
  of `bootstrap()` itself is routed to the same handler exactly once. On
  native, `PlatformDispatcher.onError` (via `OnErrorIntegration`) already
  covers asynchronous errors, so `runBootstrapGuarded` just awaits
  `bootstrap()` and a failure propagates as an uncaught error like before
  this change.

Tests that need a specific `Observability` (real or fake) use standard
Riverpod `ProviderContainer(overrides: [observabilityProvider.overrideWithValue(fake)])`
rather than the global setter — the setter exists only for the one place
(`bootstrap()`) that runs before any `ProviderScope` exists.

Release version is read from the platform package-info (Sentry's default
behavior) which already reflects `pubspec.yaml`'s `version: 0.1.0+8`; no
separate release wiring is added. `sampleRate` (error-event sampling) is
left unset, which defaults to `1.0` — satisfying "100% error sampling"
without an explicit line, but this fact is called out here so it isn't
mistaken for an oversight. Native crash handling
(`enableNativeCrashHandling`) and iOS/macOS app hang tracking
(`enableAppHangTracking`) are left at `sentry_flutter` 8.14.2's defaults,
which are both `true`. **Android ANR detection is the exception:**
`anrEnabled` defaults to `false` in 8.14.2 (Android only), so
`initObservability` sets `options.anrEnabled = true` explicitly. (An
earlier draft of this spec wrongly said ANR detection was on by default.)

### W3C `traceparent` propagation to Supabase

Sentry's Dart SDK does not emit a standard `traceparent` header — it emits
its own `sentry-trace` and `baggage` headers (confirmed via context7
against `getsentry/sentry-dart` docs and the `SentryHttpClient`/
`tracing_client` behavior). Sentry's trace ID (32 hex chars) and span ID
(16 hex chars) are format-compatible with the W3C spec's `trace-id` and
`parent-id` — confirmed against the installed SDK's `SentryId`/`SpanId`
source, both `toString()` to exactly that shape, lowercase, no dashes —
so a compliant `traceparent` header can be constructed manually from the
currently active span.

- `w3c_trace_context.dart` — pure function
  `String buildTraceParent({required String traceId, required String spanId, bool sampled = true})`
  producing `00-<trace_id>-<span_id>-<01|00>`. No Sentry dependency; unit
  testable in isolation with synthetic ids.
- `Observability.currentTraceParent` reads the active span's *actual*
  trace id/span id/sampling decision via `ISentrySpan.toSentryTrace()`
  (public API, returning a `SentryTraceHeader{traceId, spanId, sampled}`)
  rather than `ISentrySpan.context`/`.samplingDecision` directly — those
  are marked `@internal` in the SDK source and would trip
  `invalid_use_of_internal_member` under analysis. `toSentryTrace()`'s
  `sampled` is passed through to `buildTraceParent`'s `sampled`
  parameter — relevant once/if `tracesSampleRate` is ever lowered below
  1.0 — rather than a hardcoded `true`.
- `TracingHttpClient` wraps `package:http`'s `Client`, injects the
  `traceparent` header (when non-null) into every outgoing request, and is
  passed to `Supabase.initialize(httpClient: TracingHttpClient(...))`.
  `SupabaseClient`/`Supabase.initialize` accept an `httpClient` parameter
  (confirmed by reading the installed `supabase` package source,
  `supabase_client.dart`), so no monkey-patching of the Postgrest/GoTrue
  internals is required.

**Web caveat.** `traceparent` is not a CORS-safelisted request header. On
Flutter Web, adding it to every Supabase request forces a CORS preflight
on requests that might not otherwise need one, and if Supabase's
`Access-Control-Allow-Headers` response does not list `traceparent`, the
browser blocks the request outright — a correctness-breaking regression
on web, not just a missed-correlation gap. `TracingHttpClient` therefore
only injects the header when `!kIsWeb`; on web, no `traceparent` header is
sent at all, and web-originated requests are not correlatable via this
mechanism until the CORS behavior is verified against the real Supabase
project (added as an explicit step to the spike runbook) and this gate is
deliberately lifted.

Validation of this mechanism is a separate spike document — see
`docs/specs/2026-08-28-w3c-traceparent-correlation-spike.md`.

## Testing strategy

TDD, mirroring existing test layout. All paths are under
`apps/lyron_app/test/`.

**Sentry-backed tests must be offline.** `SentryClient` replaces a
`NoOpTransport` with a real `HttpTransport` as soon as a DSN is set, so a
test that initialises the SDK with a DSN would POST to sentry.io. Every
such test installs a recording fake `options.transport` (no envelope leaves
the process; the DSN only has to be syntactically valid) and a global
`HttpOverrides` guard that records or fails on any HTTP attempt, and
captures transactions/events through `beforeSendTransaction`/`beforeSend`.

- `infrastructure/observability/w3c_trace_context_test.dart` — pure
  builder: full `traceparent` regex plus exact string for a sampled span,
  flag `00` for an unsampled one (no Sentry dependency; there is no parser,
  only a builder — a real `traceparent` header is never parsed back by this
  app).
- `infrastructure/observability/tracing_http_client_test.dart` — header
  injection present when a span is active, absent when not, and absent on
  a simulated web platform regardless of an active span.
- `infrastructure/observability/sentry_pii_scrub_test.dart` — the policy
  in "PII and secret redaction": key normalization and suffix matching
  (including the kept `token_count`-style keys), nested and non-String-keyed
  maps, iterables and `Uri` values, JWT redaction (embedded, adjacent,
  glued, and linear-time on pathological input), `sb_secret_` keys, URL
  query/userinfo/fragment scrubbing per whitespace-delimited token, and
  values that must not be mangled (ChordPro, ordinary prose, `a?b`,
  `C:\dir\file?.txt`).
- `infrastructure/observability/sentry_observability_test.dart` — against a
  real in-memory Sentry SDK (offline as above): nested `runInSpan` produces
  parent/child; concurrent sibling calls do not cross-attach;
  `currentTraceParent` matches the active span's `toSentryTrace()`; ok /
  `internalError` status per outcome and no Sentry issue filed by a failing
  span; span `data` is PII-scrubbed; a `finished ambient span (zone leak)`
  group (deferred work after a span finished starts a new root, a finished
  child is not ambient, `currentTraceParent` is never all-zero and is null
  when Sentry is not initialised); a `telemetry delivery is off the critical
  path` group (a hung transport does not delay `runInSpan`, a failing or
  throwing transport surfaces no error, sync and async body throws finish
  the span exactly once); an explicit "tests are offline" guard; and
  smoke tests that breadcrumbs, user context and `captureException` do not
  throw.
- `infrastructure/config/sentry_config_test.dart` — empty DSN →
  `isEnabled == false`; non-empty DSN → `isEnabled == true`; environment
  default.
- `application/observability/observability_test.dart` — the `Noop`
  implementations (no active span, null `traceparent`, errors from `body`
  propagate).
- `application/observability/observability_providers_test.dart` — provider
  resolves to `NoopObservability` when nothing overrides it;
  `ProviderContainer` override with a fake `Observability` works.
- `bootstrap/init_observability_test.dart` — `initObservability`: disabled
  config → `NoopObservability` and `init` never called; enabled →
  `SentryObservability` published through `setCurrentObservability`; the
  options callback sets DSN, environment, `tracesSampleRate = 1.0`,
  `sendDefaultPii = false` and `anrEnabled = true`; an `init` that throws →
  `NoopObservability` returned and published, error reported, nothing
  rethrown.
- `bootstrap/bootstrap_guarded_zone_test.dart` — `reportUncaughtZoneError`
  (captures and dumps locally, still dumps when capture throws, a failing
  capture future does not become an unhandled error, prints loudly with
  Sentry disabled) and `runBootstrapGuarded` (guarded: async failure,
  synchronous throw and stray unawaited async error each reach the handler
  once, continuations stay in the guarded zone; native: no zone wrap, the
  error propagates to the caller).
- `application/auth/observability_user_context_effect_test.dart` —
  `observabilityUserContextEffectProvider`: `signedIn` → `setUserContext`,
  `signedOut` → `clearUserContext`, `fireImmediately` when already signed
  in, nothing while initializing, `sessionExpired` a deliberate no-op,
  `signedIn(A)` → `signedIn(B)` sets again without a clear, and
  `signedIn` → `signedOut` → `signedIn` clears then sets in order. The
  `organizationId` value is intentionally not asserted (known gap, see
  the deferred doc).
- `application/song_library/song_catalog_controller_test.dart`
  (`observability instrumentation` group, recording double) — a successful
  refresh records the start and success breadcrumbs; a failed refresh
  records the failure breadcrumb instead. The dozen other early-return
  branches in `_refreshCatalog` are not individually asserted (see the
  breadcrumb-coverage caveat under "Business ops = root traces").
- `application/song_library/song_catalog_controller_sentry_instrumentation_test.dart`
  — the real `SentryObservability` driving a real `SongCatalogController`
  (offline as above): a successful refresh yields one transaction, a
  `business.refresh` root with the five documented child spans with their
  exact names and operations, all ok, no issue events; when `listSongs`
  fails and the controller classifies and swallows the error,
  `song_catalog.list_songs` is `internalError`, the root stays ok, later
  spans never start and no Sentry issue is captured. It waits for the
  transaction through a completer fired from `beforeSendTransaction`,
  because span finish is fire-and-forget.

## Documentation impact

- `docs/architecture/architecture.md` — "Observability" section (kept in
  sync with this revision).
- `docs/architecture/decisions/ADR-036-observability-sentry-adapter.md`.
- `docs/deferred/2026-08-28-observability-remaining-use-cases.md`.
- `docs/specs/2026-08-28-w3c-traceparent-correlation-spike.md`.

## Open questions

None outstanding. DSN is a placeholder (`SENTRY_DSN` dart-define, empty
by default) until the user provisions a real Sentry project; the runbook
in the spike doc tells them exactly what to do at that point, including
the web-CORS check called out above.

## Revision notes

An adversarial opus review of the first draft found the following, all
addressed in this revision:

- **Broken interface signature**: `runInSpan<T>` returned
  `ObservabilitySpan` instead of `Future<T>`, making the generic
  parameter unusable and leaving span ownership/finishing ambiguous.
  Fixed — see the interface block above.
- **Error-to-trace linkage silently defeated**: `bindToScope: false` means
  neither Sentry's auto-captured unhandled errors nor a naive
  `Sentry.captureException` call would carry a `trace_id` — undermining
  the stated goal of correlating errors with traces. Fixed for the
  handled-error path via explicit `withScope` linkage; the unhandled-error
  gap is now a documented, deliberate trade-off rather than a silent
  defect.
- **Web CORS hazard**: unmitigated `traceparent` injection would have
  broken (or silently no-op'd, depending on Supabase's CORS config) every
  web request. Fixed via the `!kIsWeb` gate.
- **Root-trace placement unsound**: sign-in has no single in-process call
  tree to wrap, and wrapping it risked turning the very next refresh into
  an accidental child span via Zone inheritance through an `unawaited()`
  call. Fixed by dropping sign-in as a root trace and keeping only
  user-context tagging there.
- **Ambient child-span bug**: the original design created child spans via
  `startChild`, which does not enter a Zone, so `TracingHttpClient` would
  have seen the *root* span as current instead of the actual HTTP-call
  span. Fixed by using `runInSpan` (Zone-entering) for every nested span
  that needs to be ambient, and narrowing `startChild`'s documented use
  to non-ambient nesting.
- **Understated blast radius**: injecting `Observability` into
  `SupabaseSongRepository`/`DriftSongCatalogStore` would have touched
  shared infrastructure classes with many other, uninstrumented call
  sites. Fixed by moving every span-creation call site into
  `SongCatalogController`, which already owns the calls being wrapped —
  the leaf classes need no changes at all.
- **Bootstrap DI ordering gap**: `Observability` needed to exist before
  `Supabase.initialize`, which runs before any `ProviderScope`. Fixed via
  a package-level singleton set in `bootstrap()`, read by
  `observabilityProvider` — mirroring the existing
  `supabaseClientProvider`/`Supabase.instance.client` pattern.
- **`sendDefaultPii` default claim was backwards**: corrected; the SDK's
  actual default is already `false`. The explicit line stays for defense
  against a future default change.
- **PII scrub gaps**: denylist was key-only, top-level-only, and missed
  URL query strings (where PostgREST embeds filter values). Fixed via the
  recursive, URL-aware, JWT-pattern-aware scrub described above.
- **Missing breadcrumb call site**: the original draft named the
  capability but instrumented none. Fixed — two breadcrumbs added to the
  refresh flow.
- **Ambiguous instrumentation target**: "the guarded refresh path" could
  have meant the public coalescing `refreshCatalog()` or the private
  `_refreshCatalog()`. Fixed by pinning explicitly to the latter.

### Revision 2 (execution and PR review, 2026-09-24)

Implementing the plan and reviewing the resulting PR changed the points
below. The sections above describe the as-built result; this list records
what moved and why.

- **Installed SDK is `sentry`/`sentry_flutter` 8.14.2, not 9.28.0.**
  `flutter pub add` resolved 8.14.2. A dry run of `sentry_flutter:^9.28.0`
  (resolving to 9.30.1) succeeds only by downgrading the transitive
  packages `jni` (1.0.3 to 0.14.2) and `path_provider_android` (2.3.1 to
  2.2.23), so 9.x was not adopted in this slice. Every API this design
  uses (`Sentry.startTransaction(bindToScope:)`, `ISentrySpan.toSentryTrace()`,
  `SpanStatus`, `Sentry.captureException(withScope:)`,
  `Scope.setUser`/`setContexts`/`removeContexts`, `Breadcrumb`) exists in
  8.14.2. The "v2" tracing API mentioned above is a 9.x API and is not
  present in 8.14.2.
- **PII scrub policy**: PR review found credential leaks in the first
  implementation (URL userinfo, schemeless URLs, header-style key names, a
  fully anchored JWT pattern that missed embedded JWTs, and later a
  quadratic JWT regex and `key=value` fragments). The scrub is now the
  policy in "PII and secret redaction" above; query strings, userinfo and
  credential-bearing fragments are scrubbed again, per whitespace-delimited
  token.
- **Finished ambient spans** are ignored by `SentryObservability`
  (`runInSpan` starts a new root, `currentSpan` is a no-op span,
  `currentTraceParent` is null, `captureException` attaches no span), and
  `currentTraceParent` never emits an all-zero header. See "Zone values
  outlive the span they name".
- **Span finish is fire-and-forget**: `runInSpan` no longer awaits
  `span.finish()`, so telemetry delivery cannot stall the instrumented
  operation. See "Span finish is fire-and-forget".
- **Unhandled-error trace linkage restated**: the earlier text said
  SDK-auto-captured unhandled errors are never trace-linked. That is false
  for errors that propagate through `runInSpan` (the SDK's
  throwable-to-span association); see "Error reporting semantics".
- **Bootstrap restructured**: no `appRunner` (it would have hidden a
  `Supabase.initialize` failure on web), `initObservability` extracted
  (fail soft to `NoopObservability`), `runBootstrapGuarded` added for web
  error capture, `anrEnabled` set explicitly. See "Sentry configuration".
- **Android ANR** detection is not on by default in 8.14.2 (`anrEnabled`
  defaults to `false`); it is now enabled explicitly.
- **Tests are offline**: the SDK swaps `NoOpTransport` for `HttpTransport`
  as soon as a DSN is set, so Sentry-backed tests install a recording
  `options.transport` and a global `HttpOverrides` guard. See "Testing
  strategy".
