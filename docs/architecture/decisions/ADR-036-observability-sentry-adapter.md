# ADR-036: Observability foundation via a thin adapter over Sentry

## Status

Accepted. Revised 2026-08-28 after an adversarial opus review of the
first draft found several blocking defects (see "Revision notes" at the
end) — the decisions below reflect the corrected design, not the
original.

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

2. **Span propagation uses a dedicated Dart `Zone` value for
   parent/child resolution, not Sentry's own ambient `Scope`.** The app is
   expected to grow concurrent independent root operations (the unified
   sync overview can run song and planning sync concurrently, though that
   is not yet instrumented). Sentry's `Scope`-based "current span" is a
   single mutable reference; two concurrent root traces would otherwise
   misattribute each other's child spans once both are instrumented.
   Zone-scoped propagation gives each async call tree its own
   parent-span reference. The underlying Sentry transaction is created
   with `bindToScope: false` — the app never relies on Sentry's scope
   stack for parent/child resolution. `startChild` on a span does not
   enter a Zone (non-ambient nesting); `runInSpan` does (ambient nesting)
   and is the primitive used everywhere this slice needs a nested span to
   be visible to code with no direct span reference (e.g.
   `TracingHttpClient`).

   **Accepted consequence:** `bindToScope: false` also means Sentry's own
   automatic unhandled-error hooks (which read `Scope.span`) never see an
   active trace, so SDK-auto-captured unhandled errors are never
   trace-linked. Explicit `observability.captureException(...)` calls
   *are* linked, via `withScope: (scope) => scope.span = <the current
   span>` on that one call — scoped to that single report, never mutating
   the global scope. Setting `Scope.span` globally in `runInSpan` was
   considered and rejected: it would reintroduce the exact cross-trace
   attribution bug this Zone design exists to avoid, in exchange for
   linking a category of error (unhandled/auto-captured) that is already
   fully reported, just without a `trace_id`.

3. **Business operations are root traces; Drift and Supabase operations
   are child spans under them**, not free-standing spans. Every child
   span in this slice is created via `runInSpan` (not the non-ambient
   `startChild`) specifically so it becomes the Zone-ambient current span
   for the duration of the network/DB call it wraps. `currentSpan` is
   never null — it resolves to `NoopObservabilitySpan` when nothing is
   active (Sentry disabled, or code outside any `runInSpan`) — so callers
   never need to branch on whether tracing is active.

4. **"Handled" error capture is opt-in per call site, not automatic per
   span.** `runInSpan`'s catch block sets span status and rethrows; it
   does not call `captureException`. The codebase already uses typed
   exceptions as control flow (`SongNotFoundException`,
   `SongAccessDeniedException`, `ConnectivityFailure` classification).
   Auto-capturing every exception that passes through a span would report
   expected outcomes as if they were bugs. "Unhandled" errors are captured
   by `sentry_flutter`'s bundled `FlutterError.onError` /
   `PlatformDispatcher.onError` hooks with no code change required (see
   the trace-linkage caveat in point 2).

5. **A missing Sentry DSN disables telemetry rather than failing startup.**
   `SentryConfig.fromEnvironment()` mirrors `SupabaseConfig`'s dart-define
   pattern but fails soft (`isEnabled == dsn.isNotEmpty`), because
   telemetry is not a correctness-critical dependency the way Supabase
   configuration is. Because `Observability` must exist before
   `Supabase.initialize` (needed for `TracingHttpClient`), which itself
   runs before any `ProviderScope` exists, the instance is held in a
   package-level singleton set once during `bootstrap()` and read by
   `observabilityProvider` — the same pattern `supabaseClientProvider`
   already uses for `Supabase.instance.client`. Tests override the
   provider directly rather than touching the global setter.

6. **No W3C `traceparent` header is emitted by Sentry's SDK itself** — it
   emits its own `sentry-trace`/`baggage` headers. Sentry's trace ID (32
   hex) and span ID (16 hex) are format-compatible with W3C's
   `trace-id`/`parent-id` (verified against the installed SDK's
   `SentryId`/`SpanId` source), so `w3c_trace_context.dart` builds a
   compliant header manually from the active span's actual sampling
   decision, injected into every Supabase request via a custom
   `http.Client` passed to `Supabase.initialize(httpClient: ...)`.
   **The header is only injected on non-web platforms** (`!kIsWeb`):
   `traceparent` is not a CORS-safelisted header, and sending it on web
   without first confirming Supabase's CORS configuration allows it would
   break web requests outright rather than merely losing correlation.

7. **Redaction is scoped to credentials and personal identifiers, not
   business content — per explicit product direction, ChordPro source,
   lyrics, plan/session text, and other domain content (including RPC
   parameter values that carry it) are not treated as sensitive and may
   appear in span/breadcrumb/exception data when it aids debugging.**
   Only two categories stay hard-restricted: (a) tokens/credentials —
   `sendDefaultPii = false`, `captureFailedRequests = false` (so Sentry's
   automatic native-HTTP failed-request reporting cannot auto-report an
   already-classified `ConnectivityFailure` as a bug), a **recursive**
   scrub on span/breadcrumb/exception-extra data that walks nested
   maps/lists, drops denylisted keys (`authorization`, `apikey`,
   `access_token`, `refresh_token`, `token`), strips query strings from
   any URL-shaped value, and redacts JWT-shaped string values regardless
   of key; and (b) personal identifiers — `setUserContext` accepts only
   pseudonymized `userId`/`organizationId` (Supabase UUIDs), never email
   or display name, with no code path that could attach either. **No
   span, breadcrumb, or exception `extra` may ever carry a raw
   token/credential or a personal identifier (email, display name).**
   This is a hard rule for every future call site, not just the ones
   added in this slice — but it does not extend to ChordPro/lyrics/domain
   content, which this slice deliberately treats as debuggable, not
   secret. Free-text fields (span name/description, breadcrumb message)
   are not scrubbed — they must only ever be static strings written by
   our own instrumentation code, never interpolated from request content
   (a discipline rule about *what kind* of string goes there, unrelated
   to the content-sensitivity question above).

8. **Sign-in is not a root trace.** It is OAuth-redirect/magic-link based:
   the initiating call returns immediately, and the session arrives later
   via a stream/deep-link callback in an unrelated async context, so there
   is no single call tree to wrap. Worse, wrapping it risked turning the
   very next `unawaited(controller.refreshCatalog())` (fired from the
   auth-state listener on the `signedIn` transition) into an accidental
   *child* of the sign-in trace via Zone inheritance, rather than its own
   root. Sign-in instead gets pseudonymized identity attached via a
   `ref.listen`-based side-effect provider
   (`observabilityUserContextEffectProvider`), structurally identical to
   the existing `membershipRefreshEffectProvider`, calling
   `setUserContext`/`clearUserContext` — no root trace, no changes to
   `AppAuthController`'s state machine.

## Consequences

- Swapping to OpenTelemetry later means writing one new adapter behind
  the existing `Observability` interface; no application call site
  changes.
- Only one root trace (song catalog refresh, with sign-in contributing
  user-context tagging but no root trace of its own) is instrumented
  initially. Remaining use cases are tracked in
  `docs/deferred/2026-08-28-observability-remaining-use-cases.md` and are
  not silently forgotten.
- SDK-auto-captured unhandled errors are never trace-linked (point 2's
  accepted consequence). If this later proves too costly, the fix is not
  "just set `bindToScope: true`" — that reintroduces cross-trace
  attribution bugs — but a more targeted mechanism (e.g. periodically
  syncing `Scope.span` to the single most-recently-started root, accepting
  that concurrent roots still race, only for the unhandled-error case).
  Not attempted in this slice.
- `traceparent` correlation does not cover web until someone verifies
  Supabase's CORS configuration allows the header and lifts the `!kIsWeb`
  gate; until then, web requests carry no correlation header at all.
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
- **Sentry's newer "v2" tracing API** (`Sentry.startSpan`/`SentrySpanV2`,
  available in the SDK version this slice installs) — has built-in
  Zone-based ambient propagation that also avoids scope-clobbering, which
  looked like it could replace our hand-rolled Zone key. Rejected for now
  because it exposes no public API to read "whatever span is active" from
  code with no direct span reference (`hub.getActiveSpan()` is
  `@internal`) — exactly what `TracingHttpClient` needs, since it runs
  inside Supabase's call stack with no span passed to it. Worth
  revisiting if a future SDK version adds a public ambient accessor.
- **Setting `Scope.span` globally inside `runInSpan`** (so unhandled
  errors would also get trace-linked) — rejected: reintroduces the exact
  cross-trace attribution bug the Zone design exists to prevent, the
  moment two independent root traces run concurrently. See point 2's
  "accepted consequence."

## Revision notes

Revised 2026-08-28 after an adversarial opus review of the first draft.
Full list of findings and fixes is recorded in
`docs/specs/2026-08-28-observability-foundation.md`'s own "Revision
notes" section — not duplicated here to avoid the two documents drifting
out of sync.
