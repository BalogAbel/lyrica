# ADR-036: Observability foundation via a thin adapter over Sentry

## Status

Accepted. Revised 2026-08-28 after an adversarial opus review of the
first draft found several blocking defects (see "Revision notes" at the
end), and again after execution and PR review ("Revision 2" in the
revision notes) — the decisions below reflect the as-built implementation,
not the original draft.

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

   **Accepted consequence, and its actual extent:** `bindToScope: false`
   means Sentry's scope-based trace linkage (which reads `Scope.span`)
   never sees an active trace. Explicit `observability.captureException(...)`
   calls *are* linked, via `withScope: (scope) => scope.span = <the current
   span>` on that one call — scoped to that single report, never mutating
   the global scope. SDK-auto-captured unhandled errors are linked only
   through the SDK's second route, a throwable-to-span association: in
   `sentry` 8.14.2, when a span whose `throwable` is set finishes,
   `SentrySpan.finish` calls `Hub.setSpanContext`, which records the
   throwable (by object identity, first association wins) in an `Expando`;
   when the hub later captures an event for that same throwable it copies
   that span's trace context onto the event. `runInSpan` sets
   `span.throwable`, so an error that propagated through a `runInSpan` and
   is later captured automatically **is** trace-linked, to the innermost
   span it crossed. It is **not** linked when it is thrown outside any
   span, when it never crosses a `runInSpan` boundary, or when the SDK
   captures it before the (unawaited) span finish has recorded the
   association. This is derived from the SDK source; no committed test pins
   it. Setting `Scope.span` globally in `runInSpan` was considered and
   rejected: it would reintroduce the exact cross-trace attribution bug
   this Zone design exists to avoid, in exchange for linking a remaining
   category of error (unhandled errors that never crossed a span) that is
   already fully reported, just without a `trace_id`.

   **Zone values outlive their span.** A `Timer` or microtask scheduled
   inside a span's body runs later in that span's Zone, usually after the
   span finished. `SentryObservability` treats a finished ambient span as
   absent: `runInSpan` starts a new root (the SDK's `startChild` on a
   finished transaction silently returns a no-op span with all-zero ids),
   `currentSpan` is a no-op span, `currentTraceParent` is null and
   `captureException` attaches no span.

   **Span finish is fire-and-forget.** `runInSpan` sets status and
   `throwable`, then finishes the span without awaiting it and swallows
   any error, because finishing a root span awaits the transaction's
   transport send (an HTTP POST on web) and a slow collector must never
   stall the instrumented operation.

3. **Business operations are root traces; Drift and Supabase operations
   are child spans under them**, not free-standing spans. Every child
   span in this slice is created via `runInSpan` (not the non-ambient
   `startChild`) specifically so it becomes the Zone-ambient current span
   for the duration of the network/DB call it wraps. `currentSpan` is
   never null — it resolves to `NoopObservabilitySpan` when nothing is
   active (Sentry disabled, or code outside any `runInSpan`) — so callers
   never need to branch on whether tracing is active.

4. **"Handled" error capture is opt-in per call site, not automatic per
   span — and this is a distinct thing from span *status*.** `runInSpan`'s
   catch block sets `ObservabilitySpanStatus.internalError` on the span
   and rethrows for *every* exception, including expected, classified
   ones like a `ConnectivityFailure` during an offline refresh — this is
   fine: a span status is a trace attribute (this span didn't complete
   normally), not a Sentry issue. It does not call `captureException`, so
   it never files an issue. It does record the error as the span's
   `throwable`, which is what lets the SDK link a later automatic capture
   of that same error to the trace (point 2). The codebase already uses typed exceptions as
   control flow (`SongNotFoundException`, `SongAccessDeniedException`,
   `ConnectivityFailure` classification); what `runInSpan` deliberately
   avoids is auto-*reporting* (issue creation) for those, which would
   flood Sentry with "bugs" that are actually expected outcomes — it does
   not avoid marking the span itself as failed, which is accurate and
   useful trace data regardless of why the exception was thrown.
   "Unhandled" errors are captured by `sentry_flutter`'s bundled
   `FlutterError.onError`/`PlatformDispatcher.onError` hooks with no code
   change required (see the trace-linkage note in point 2 for how far they
   are linked to a trace).

5. **A missing or broken Sentry setup disables telemetry rather than
   failing startup.** `SentryConfig.fromEnvironment()` mirrors
   `SupabaseConfig`'s dart-define pattern but fails soft
   (`isEnabled == dsn.isNotEmpty`), because telemetry is not a
   correctness-critical dependency the way Supabase configuration is.
   `initObservability(config)`, called from `bootstrap()`, initialises
   Sentry when enabled and returns the `Observability` to use; if
   `SentryFlutter.init` throws (for example a malformed DSN, which
   `Dsn.parse` rejects before any integration is installed) the error is
   reported through `FlutterError.reportError` and `NoopObservability` is
   used — Sentry then stays on its `NoOpHub`, so keeping the Sentry adapter
   would only do pointless work. Because `Observability` must exist before
   `Supabase.initialize` (needed for `TracingHttpClient`), which itself
   runs before any `ProviderScope` exists, the instance is held in a
   package-level singleton set by `initObservability` through
   `setCurrentObservability` and read by `observabilityProvider` — the same
   pattern `supabaseClientProvider` already uses for
   `Supabase.instance.client`. Tests override the provider directly rather
   than touching the global setter.

   Sentry is initialised **without `appRunner`**. With it, the SDK would run
   `Supabase.initialize` and `runApp` inside its own `runZonedGuarded` on
   web, and that zone swallows a failure of the closure: a Supabase
   initialisation error would leave `runApp` unreached and a blank screen,
   where the pre-Sentry behavior was a loud crash. `Supabase.initialize`
   and `runApp` therefore run after `initObservability`, outside any
   Sentry-managed zone. The price is that on web the SDK installs neither a
   zone nor an `OnErrorIntegration` (`isOnErrorSupported = !isWeb && ...`),
   so uncaught asynchronous errors would be lost;
   `runBootstrapGuarded`, called from `main()`, supplies the zone: when
   `kIsWeb` it runs the whole `bootstrap()` in one `runZonedGuarded`
   whose handler prints the error locally and then reports it to Sentry.
   On native, `PlatformDispatcher.onError` (via `OnErrorIntegration`)
   already covers asynchronous errors, and a `bootstrap()` failure
   propagates as an uncaught error like before. Android ANR detection is
   enabled explicitly (`anrEnabled = true`) because it defaults to `false`
   in the installed SDK.

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
   `currentTraceParent` is null when there is no active span (a finished
   span does not count) or when the span's trace or span id is all zeros (a
   no-op span), so an invalid all-zero W3C header is never emitted.

7. **Redaction is scoped to credentials and personal identifiers, not
   business content — per explicit product direction, ChordPro source,
   lyrics, plan/session text, and other domain content (including RPC
   parameter values that carry it) are not treated as sensitive and may
   appear in span/breadcrumb/exception data when it aids debugging.**
   Only two categories stay hard-restricted: (a) tokens/credentials —
   `sendDefaultPii = false`, plus a **recursive** scrub (`scrubPii` in
   `sentry_pii_scrub.dart`) on span/breadcrumb/exception-extra data. It
   normalizes keys (lower-case, with `-`, `_`, `.` and whitespace removed)
   and drops those equal to `authorization`, `jwt` or `codeverifier` or
   ending in `token`, `secret`, `password`, `cookie` or `apikey` (a suffix
   match, so `token_count` and `tokenizer` are kept); it traverses any
   `Map`, `Iterable` and `Uri`; and in strings it redacts JWTs anywhere in
   the string (a linear-time scan — an unanchored regex is quadratic on
   hostile input) and `sb_secret_...` Supabase keys, then, per
   whitespace-delimited URL-shaped token, drops userinfo, the query string
   and `key=value` fragments (implicit-flow `#access_token=...`). Email
   addresses are a documented non-goal of the scrub. (An earlier draft
   stripped query strings on the assumption that they carried business
   content, and a later draft left them unscrubbed on the narrowed policy;
   review showed URLs carry credentials in userinfo, query string and
   fragment, so URL scrubbing was reinstated for credentials, not for
   business content.); and (b) personal
   identifiers — `setUserContext` accepts only pseudonymized
   `userId`/`organizationId` (Supabase UUIDs), never email or display
   name, with no code path that could attach either, and
   `clearUserContext` removes both the user *and* the `organization`
   scope context `setUserContext` set — clearing only the user would
   leave a stale organization id attached to events fired after sign-out.
   `captureFailedRequests` is left at its SDK default: it only governs
   `SentryHttpClient`/native HTTP-instrumentation integrations, neither of
   which this design installs, so setting it would have been a no-op with
   a misleading rationale attached (an earlier draft set it `false`
   believing it would suppress double-reporting of classified connectivity
   failures through `TracingHttpClient`, which it never would have). **No
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
- SDK-auto-captured unhandled errors are trace-linked only when the error
  propagated through a `runInSpan` (the SDK's throwable-to-span association,
  point 2); an error thrown outside any span carries no `trace_id`. If that
  later proves too costly, the fix is not "just set `bindToScope: true`" —
  that reintroduces cross-trace attribution bugs — but a more targeted
  mechanism (e.g. periodically syncing `Scope.span` to the single
  most-recently-started root, accepting that concurrent roots still race,
  only for the unhandled-error case). Not attempted in this slice.
- Span finish is fire-and-forget (point 2), so telemetry delivery failures
  are silent and an in-flight transaction can be lost if the process exits
  before it is delivered. Accepted in exchange for never blocking the
  instrumented operation on a slow or hung collector.
- Scrubbing is applied per call site inside `SentryObservability` (point 7),
  not centrally through SDK hooks, so a new code path that reaches the SDK
  without going through `scrubPii` would bypass it. Centralising it is
  tracked in `docs/deferred/2026-08-28-observability-remaining-use-cases.md`.
- The app is pinned to `sentry`/`sentry_flutter` 8.x: 9.x resolves only by
  downgrading the transitive packages `jni` and `path_provider_android`.
  Upgrading is a follow-up tracked in the same deferred document.
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
  a 9.x API — it is not present in the installed 8.14.2) — has built-in
  Zone-based ambient propagation that also avoids scope-clobbering, which
  looked like it could replace our hand-rolled Zone key. Rejected for now
  because, in the 9.28.0 source reviewed at design time, it exposes no
  public API to read "whatever span is active" from code with no direct
  span reference (`hub.getActiveSpan()` is `@internal`) — exactly what
  `TracingHttpClient` needs, since it runs inside Supabase's call stack
  with no span passed to it. Worth revisiting once the dependency
  constraints allow 9.x and it has a public ambient accessor.
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

### Revision 2 (execution and PR review, 2026-09-24)

Implementing the design and reviewing the resulting PR changed several
details; the decisions above already describe the as-built result. In
short (the spec's "Revision 2" lists each item with its rationale):

- The installed SDK is `sentry`/`sentry_flutter` 8.14.2, not the 9.28.0 the
  first plan assumed; the "v2" tracing API is a 9.x API and is not present.
- The PII scrub policy (point 7) was tightened after review found credential
  leaks (URL userinfo, schemeless URLs, header-style key names, embedded
  JWTs, a quadratic JWT regex, `key=value` fragments).
- `SentryObservability` ignores finished ambient spans, returns a null
  `traceparent` for all-zero ids, and no longer awaits span finish
  (points 2 and 6).
- The claim that SDK-auto-captured unhandled errors are never trace-linked
  was wrong for errors that propagated through `runInSpan`; point 2 and the
  consequences now state the actual extent.
- Bootstrap was restructured (point 5): no `appRunner`, `initObservability`
  with a fail-soft fallback, `runBootstrapGuarded` for web error capture,
  and `anrEnabled` set explicitly (it defaults to `false` in 8.14.2).
- Sentry-backed tests run offline (recording transport plus an
  `HttpOverrides` guard).
