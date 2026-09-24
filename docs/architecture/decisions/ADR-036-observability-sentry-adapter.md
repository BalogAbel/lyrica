# ADR-036: Observability foundation via a thin adapter over Sentry

## Status

Accepted. Revised 2026-08-28 after an adversarial opus review of the
first draft found several blocking defects (see "Revision notes" at the
end), and again after execution and PR review ("Revision 2" in the
revision notes), and again after two further scrub reviews ("Revision 3" and
"Revision 4", the latter replacing the URL heuristics by a small rule set) —
the decisions below reflect the as-built implementation, not the original
draft.

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
   span, when it never crosses a `runInSpan` boundary, or when its span
   never finishes. There is no capture-before-finish window in the current
   configuration: `SentrySpan.finish` reaches `Hub.setSpanContext`
   synchronously (its only earlier `await` iterates
   `options.performanceCollectors`, which is empty here), and `runInSpan`
   calls `_finishQuietly` in its `finally`, before the rethrow completes, so
   the association exists before any handler can capture the error. A
   window would appear only if frames tracking is adopted
   (`SentryWidgetsFlutterBinding` instead of `WidgetsFlutterBinding`
   registers a `PerformanceContinuousCollector`,
   `frames_tracking_integration.dart:36-41`): `SentrySpan.finish` would then
   await the collector before recording the association
   (`sentry_span.dart:72-86`) and, because the finish is unawaited, a fast
   handler could capture first. The behavior is pinned by the
   `error to trace linking` tests in `sentry_observability_test.dart` (a
   plain `Sentry.captureException` in a zone handler) and, for the real
   web path, by `report_uncaught_zone_error_sentry_test.dart` (the same
   escaping error captured through `reportUncaughtZoneError`'s default
   capture carries the span's trace id, level `fatal`, `handled: false`).
   Setting `Scope.span` globally in `runInSpan` was considered and
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
   used, so no spans are created against a half-initialized SDK. Sentry
   stays on its `NoOpHub` only when the failure happens before the hub
   exists (a bad DSN: `_setDefaultConfiguration` throws in
   `options.parsedDsn`, `sentry.dart:150-152`, `:305-314`); a later throw
   leaves a live hub behind the no-op adapter, which is harmless because no
   spans are created and the SDK's global error hooks still capture. Because `Observability` must exist before
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
   whose handler prints the error locally and then reports it to Sentry
   the way the SDK's own zone does: `Mechanism(type: 'runZonedGuarded',
   handled: false)`, level `fatal` (the SDK default
   `markAutomaticallyCollectedErrorsAsFatal`; the option is not readable
   without `@internal` API, so it is hard-coded), and the scope span (if
   any; none is bound in this app, so this SDK-parity marking is currently
   a no-op) marked `internalError`.
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
   and drops those equal to a small exact set (`jwts`, `tokens`,
   `accesstokens`, `refreshtokens`, `idtokens`, `codeverifier`, `tokenhash`,
   `otp`, `totp`, `csrf`, `xsrf`, `sig`, `signature`, `auth`, `authheader`,
   `creds`, `nonce`, `pwd`, `pin`, `passcode`, `bearer`, ...) or ending in
   `token`, `jwt`, `secret(s)`,
   `password(s)`, `passwd`, `passphrase`, `cookie(s)`, `apikey(s)`,
   `authorization`, `privatekey(id)`, `secretkey`, `accesskey`,
   `servicerolekey`, `supabasekey`, `credential(s)`, `passwordhash`,
   `authcode`, `authorizationcode`, `mfacode`, `otpcode`, `verificationcode`
   or `recoverycode(s)` (a suffix match, so `token_count`, `tokenizer` and
   `max_tokens` are kept; the plural `tokens` and the short generic names are
   exact-only for that reason, so `time_signature`, `author` and a bare
   `code` (an HTTP status) are kept; `session_id`/`sessionid` are generic
   correlation ids, not credentials in this app, and are kept too). Two exceptions keep an otherwise matching key: a `bool` value
   is never a secret (`has_password: true`), and opaque pagination /
   cancellation cursors (`page_token`, `next_page_token`, `prev_page_token`,
   `cancel_token`, `sync_token`) are allowlisted. Kept keys are themselves
   string-scrubbed (a key holding a URL or JWT); keys that collide
   afterwards overwrite each other, the later wins. It traverses any `Map` and
   `Iterable`, bounded (depth 16, 256 elements per collection, a
   2048-container and a 2048-element budget per call; beyond the depth or
   container budget the value becomes the string `[truncated]`, extra
   elements are dropped) so a cyclic or hostile structure cannot overflow
   the stack or hang the caller. `null`, numbers and bools pass through;
   everything else (a `String`, `Uri`, exception, enum, any object) is
   scrubbed as its `toString()` (`[unprintable]` if that throws), because the
   SDK's JSON serialization falls back to exactly that and an object holding
   a URL or token must not bypass the string scrub. `scrubPii` never throws
   (any failure yields `{'scrub_error': true}` with no data), so scrubbing can
   never break an instrumented operation. Strings are size-capped: only the
   first 64 KB is scrubbed (trimmed back to the last whitespace when cut, so a
   partial token at the boundary is dropped, never emitted half-redacted),
   the scrubbed result is cut to 8 KB plus the marker `…[truncated]` (an
   unscrubbed tail is never emitted), and a 64 KB total of key and string
   characters per call turns later strings into `[truncated]`; this bounds
   both main-isolate time and the encoded size Sentry has to accept. In
   strings the scrub is a **small, conservative rule set** (the URL rules are
   deliberately not a heuristic: see "Revision 4"). It redacts JWTs anywhere
   in the string (a linear-time scan — an unanchored regex is quadratic on
   hostile input) and `sb_secret_...` Supabase keys, then works per
   whitespace-delimited token: (A) a token holding a scheme URL (the first
   `://` preceded by a scheme of two or more characters) keeps what precedes
   the scheme verbatim; an `@` after the first `/`, `?` or `#` following
   `://` is ambiguous (path/query `@`, or userinfo holding one of those) and
   replaces everything after `://` by `[redacted]`; otherwise userinfo (up to
   the last `@` of the authority) is dropped and everything from the first
   `?` — or from an earlier `#` whose fragment holds a `=`, the implicit-flow
   `#access_token=...` — to the end of the token is dropped (a plain
   `#fragment` without a query is kept), at most 8 URLs per token; (B) a
   token without a scheme URL is cut at its first `?` (or `#=`) when it is a
   non-hierarchical scheme URI (`mailto:a@b?subject=hi`) or when the text
   before it is host-shaped or contains a `/` AND the query/fragment holds a
   `=` (`example.co/rest/v1/x?apikey=S`), so ChordPro such as
   `[C/G]Why?[Am]Because` and prose are not mangled; and (C) the value of
   credential key/value text (`refresh_token=abc`, `"access_token":"abc"`,
   `password: x`, `Authorization: Bearer x`, for a fixed list of credential
   names) is replaced by `[redacted]`, run after the URL rules and followed by
   one more URL pass so the result is idempotent. Email addresses are a
   documented non-goal of the scrub. (An earlier draft
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
  JWTs, a quadratic JWT regex, `key=value` fragments) and again by a later
  re-review (greedy userinfo, bare-host URLs, more key names, JSON-wrapped
  URLs, bounded traversal, never-throwing `scrubPii`).
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

### Revision 3 (independent re-review of the scrub, 2026-09-24)

A further independent review (verified by probes) found regressions and
gaps in the previous round. The URL items below describe what Revision 3
did; **Revision 4 supersedes them** (the URL handling is now the rule set in
point 7), while the key, size-cap and map-key items still stand:

- Greedy userinfo removal swallowed the `?` when an `@` sat in the query
  (`?email=a@b.c&token=S` leaked the token). The drop is now per URL, ends at
  the last `@` before the first `?`/`#`, and reads a later `@` as query
  content unless the text before the delimiter is not `host[:port]`.
- A quote or unbalanced closer inside a query value leaked later params.
  A URL now ends only at the closer matching its own wrapper; an unwrapped
  URL is stripped to the end of its token.
- The first-`?` classification was reused for later URLs in the same token
  (`why?https://h/x?token=S`); each `?`/`#` is now classified on its own.
- Key denylist gaps (`passwd`, `otp`, `csrf`, `sig`, `signature`, `auth`,
  `service_role_key`, plurals, ...) closed with exact-only short names, and
  benign cases kept (bool values, pagination/cancel cursors).
- No size caps: added the per-string 64 KB scrub prefix / 8 KB result cap,
  64 KB total string budget and 2048-element budget.
- Schemeless `/` tokens need a `key=value` query/fragment, so ChordPro slash
  chords are no longer mangled; map keys are string-scrubbed.
- The zone-error handler's scope-span marking is SDK-parity code and a no-op
  in this app (nothing binds a scope span); the error-to-trace link for an
  error escaping a nested span into the guarded zone is now pinned through
  `reportUncaughtZoneError` itself.

### Revision 4 (freeze of the URL heuristics, 2026-09-25)

Four review rounds in a row, each fixing the URL heuristic state machine
(userinfo removal, opener/closer tracking, per-`?` classification, a
no-`=` shortcut: about a dozen interacting states), introduced a new leak
class; example tests could not catch combinations, and an independent fuzzer
still found 255 failing signatures (out of 1.5M cases) after Revision 3. The
decision was to **stop patching**: the state machine is replaced by the small,
auditable rule set in point 7 (A scheme URL, B schemeless URL shape, C
credential key/value text) plus a committed seeded property fuzzer
(`test/infrastructure/observability/sentry_pii_scrub_fuzz_test.dart`) that
states the properties (a planted secret never survives, benign text is
unchanged, the scrub is idempotent, it never throws).

Accepted trade-offs, in exchange for a rule set a reviewer can read in
minutes: text after a URL in the same whitespace-free token (JSON, brackets,
quotes) is dropped; an `@` in a path or query over-redacts the whole URL to
`scheme://[redacted]`; a few look-alikes with a `=` after a `?` are cut
(`foo.bar?baz=qux`, `Dr.Who?name=x`, `1.5?x=2`, `[G/B]Love?[C]=joy`,
`v1.2?x=1`). Documented residuals that cannot be told from prose: a bare
`?SECRET` without `=`; a schemeless URL after an earlier non-URL `?` in the
same token or glued after a `=`/`,` unless its key is a credential name
(rule C); the words of a quoted credential value after the first. Exception
messages passed to `captureException` never go through `scrubPii`
(`docs/deferred/2026-08-28-observability-remaining-use-cases.md` records the
centralized `beforeSend*` scrub as the recommended long-term path).

Other fixes in the round: non-String objects (an exception holding a URL) are
scrubbed as their `toString()` instead of bypassing the scrub;
`span.setData` forwards the value when key scrubbing rewrites the key (it was
silently dropped); keys `pin`, `passcode`, `bearer`, `otpcode` and
`verificationcode` are denied (`code`, `session_id` and `sessionid` stay: too
generic); the exact 8 KB output / 64 KB input cap boundaries are pinned.
