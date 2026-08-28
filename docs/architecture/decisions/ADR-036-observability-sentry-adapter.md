# ADR-036: Observability foundation via a thin adapter over Sentry

## Status

Accepted.

## Context

`apps/lyron_app` had no crash reporting, error telemetry, or tracing.
Debugging depended on user reports and uncollected `debugPrint` calls.
There was no way to correlate a client failure with the corresponding
Supabase Cloud request.

The accepted direction (product/architecture decision, not derived from
the code) is: `sentry_flutter` as the primary telemetry/crash SDK, 100%
error and trace sampling given current low traffic, and a W3C
`traceparent` header on Supabase requests so a Sentry `trace_id`
correlates with Supabase Cloud logs. OpenTelemetry, an OTLP gateway,
Supabase Log Drain, and self-hosted Grafana/Loki/Tempo are explicitly out
of scope for now — Supabase/Postgres metrics may reach Grafana Cloud Free
later, independent of this decision.

## Decision

1. **Application code depends on a first-party `Observability` interface,
   never on the Sentry API directly.** `SentryObservability` is the sole
   adapter today; a future OpenTelemetry adapter can implement the same
   interface without touching call sites. This mirrors the existing
   repository-contract pattern (`SongRepository` → `SupabaseSongRepository`).

2. **Span propagation uses a dedicated Dart `Zone` value, not Sentry's own
   ambient `Scope`.** The app has concurrent independent root operations
   by design (the unified sync overview can run song and planning sync
   concurrently). Sentry's `Scope`-based "current span" is a single
   mutable reference; two concurrent root traces would otherwise
   misattribute each other's child spans. Zone-scoped propagation gives
   each async call tree its own parent-span reference. The underlying
   Sentry transaction is created with `bindToScope: false` — the app never
   relies on Sentry's scope stack for parent/child resolution.

3. **Business operations are root traces; Drift and Supabase operations
   are child spans under them**, not free-standing spans. Where there is
   no active root trace (Sentry disabled, or a call site outside the
   instrumented paths), child-span calls are no-ops on
   `NoopObservabilitySpan` — callers never need to branch on whether
   tracing is active.

4. **"Handled" error capture is opt-in per call site, not automatic per
   span.** `runInSpan`'s catch block sets span status and rethrows; it
   does not call `captureException`. The codebase already uses typed
   exceptions as control flow (`SongNotFoundException`,
   `SongAccessDeniedException`, `ConnectivityFailure` classification).
   Auto-capturing every exception that passes through a span would report
   expected outcomes as if they were bugs. "Unhandled" errors are captured
   by `sentry_flutter`'s bundled `FlutterError.onError` /
   `PlatformDispatcher.onError` hooks with no code change required.

5. **A missing Sentry DSN disables telemetry rather than failing startup.**
   `SentryConfig.fromEnvironment()` mirrors `SupabaseConfig`'s dart-define
   pattern but fails soft (`isEnabled == dsn.isNotEmpty`), because
   telemetry is not a correctness-critical dependency the way Supabase
   configuration is.

6. **No W3C `traceparent` header is emitted by Sentry's SDK itself** — it
   emits its own `sentry-trace`/`baggage` headers. Sentry's trace ID (32
   hex) and span ID (16 hex) are format-compatible with W3C's
   `trace-id`/`parent-id`, so `w3c_trace_context.dart` builds a compliant
   header manually from the active span, injected into every Supabase
   request via a custom `http.Client` passed to
   `Supabase.initialize(httpClient: ...)`.

7. **PII/secret redaction is layered, not single-point:**
   `sendDefaultPii = false`, a key-name denylist scrub on span/breadcrumb
   `data` (`authorization`, `apikey`, `access_token`, `refresh_token`,
   `chordpro_source`, `lyrics`, `token`), and `setUserContext` accepting
   only pseudonymized `userId`/`organizationId` (Supabase UUIDs) — never
   email or display name. **No span, breadcrumb, or exception `extra` may
   ever carry ChordPro source, lyrics, request/response bodies, tokens, or
   RPC parameter values.** This is a hard rule for every future call site,
   not just the ones added in this slice.

## Consequences

- Swapping to OpenTelemetry later means writing one new adapter behind
  the existing `Observability` interface; no application call site
  changes.
- Only one vertical slice (song catalog refresh + sign-in) is instrumented
  initially. Remaining use cases are tracked in
  `docs/deferred/2026-08-28-observability-remaining-use-cases.md` and are
  not silently forgotten.
- Native crash *symbolication* (readable native stack traces) is deferred
  until a CI/CD pipeline exists to upload Android/iOS debug symbols
  (roadmap Phase 9). Native crash *capture* itself ships now via
  `sentry_flutter`'s bundled native SDKs — crashes are reported, but
  native frames may be unsymbolicated until that pipeline lands.
- Live validation of the Sentry↔Supabase trace correlation requires a
  provisioned Sentry DSN and Supabase Cloud log access, neither available
  in the environment that authored this decision. This slice ships an
  offline unit-level proof of the header contract and a manual runbook
  (`docs/specs/2026-08-28-w3c-traceparent-correlation-spike.md`) rather
  than a live-verified result.

## Alternatives considered

- **Static `Observability` facade** — rejected: not DI-friendly, harder to
  substitute a `NoopObservability`/test double, inconsistent with the
  codebase's existing contract-plus-provider pattern.
- **Sentry's own ambient scope for span propagation** — rejected: breaks
  under the app's existing concurrent-sync design (ADR risk: silent
  cross-attribution of spans from unrelated concurrent operations).
- **Auto-capturing every exception that crosses a span as a Sentry issue**
  — rejected: would report expected typed control-flow outcomes
  (not-found, access-denied, connectivity classification) as bugs.
