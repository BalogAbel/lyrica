# Spike: Sentry ↔ Supabase W3C `traceparent` correlation

## Purpose

Prove that a client-side Sentry trace can be correlated with the
corresponding Supabase Cloud request log entry via a shared trace
identifier, without introducing OpenTelemetry or a log-shipping pipeline.

## Why this is a spike, not just an implementation detail

Sentry's Dart SDK does not natively emit a W3C `traceparent` header — it
propagates its own `sentry-trace`/`baggage` format (confirmed via context7
against `getsentry/sentry-dart`: `SentryHttpClient` and the tracing client
inject `sentry-trace`/`baggage`, not `traceparent`). Supabase Cloud's
request logs, however, are correlatable by whatever header the client
sends and Supabase's edge/API gateway records. Manually constructing a
W3C-shaped header from Sentry's own trace ID and span ID is the bridge —
this needs to be validated as a real mechanism, not assumed.

## What is validated automatically (this slice, offline)

Split across two test files, since claim 1 needs no Sentry dependency at
all and claims 2–4 need a real (test-mode) Sentry span:

`test/infrastructure/observability/w3c_trace_context_test.dart` — pure,
synthetic ids, no Sentry:

1. `buildTraceParent(traceId: ..., spanId: ...)` produces a string matching
   `^00-[0-9a-f]{32}-[0-9a-f]{16}-0[01]$`.

`test/infrastructure/observability/sentry_observability_test.dart` —
against a real Sentry SDK instance running in test mode:

2. `Observability.currentTraceParent`'s `trace-id` segment exactly equals
   the *actual active span's* Sentry `traceId.toString()` (hex, no dashes,
   32 chars — Sentry's own trace ID format is already W3C-compatible).
3. Its `parent-id` segment exactly equals the same span's
   `spanId.toString()` (hex, 16 chars).
4. `sampled` reflects the span's real sampling decision, not a hardcoded
   value.

`test/infrastructure/observability/tracing_http_client_test.dart`:

5. `TracingHttpClient` attaches the `traceparent` header to every outgoing
   request when `Observability.currentTraceParent` is non-null, omits it
   cleanly (no empty header) when there is no active span, and omits it
   unconditionally when the client believes it is running on web
   (`kIsWeb` simulated true), regardless of whether a span is active — see
   the web caveat below for why.

This proves the **header contract** is correct on the platforms it
applies to. It does not prove Supabase Cloud actually surfaces that
header value somewhere queryable — that requires a live project.

## Web caveat (must be resolved before lifting the `!kIsWeb` gate)

`traceparent` is not a CORS-safelisted request header. `TracingHttpClient`
does not inject it on web (`kIsWeb == true`) until someone confirms, via
step 0 below, that Supabase's CORS configuration actually allows it —
otherwise this feature would silently or loudly break every web request
depending on Supabase's exact CORS behavior for an unlisted header.

**Step 0 (web, before anything else, once a DSN exists):** open the
Network tab against a Supabase project with the `!kIsWeb` gate
temporarily removed in a local build. Confirm the browser does not block
the request (no CORS error in the console) and that the actual request
either succeeds normally or the preflight `OPTIONS` response's
`Access-Control-Allow-Headers` includes `traceparent`. If either check
fails, do not lift the gate — file it as a Supabase project configuration
change first (allow the header), then retest.

## What requires a live project (manual runbook — run this once you have a Sentry DSN)

Supabase MCP is not authenticated in the current environment, so this
cannot be automated or verified by the assistant in this session. Steps
for a human to run once a real `SENTRY_DSN` is provisioned:

1. **Provision Sentry** (you do this — account/project creation cannot be
   automated on your behalf):
   - Create a project at sentry.io (or your self-hosted instance),
     platform "Flutter".
   - Copy the DSN.
   - Run the app with `--dart-define=SENTRY_DSN=<your-dsn>`.

2. **Trigger an instrumented flow** — open the song library screen while
   signed in (triggers `SongCatalogController`'s refresh path, which is
   the root trace instrumented in this slice).

3. **Find the trace ID in Sentry:**
   - Sentry → Performance (or Traces) → find the `song_catalog.refresh`
     transaction from the run.
   - Copy its **Trace ID** (32-char hex string shown in the trace detail
     header).

4. **Find the same request in Supabase:**
   - Supabase Dashboard → Logs & Analytics → API/Postgres logs.
   - Filter/search the request log around the same timestamp for a
     `traceparent` header value containing the trace ID from step 3.
     (Supabase's log explorer supports free-text search over request
     headers — search for the raw trace ID substring if there is no
     dedicated header filter.)
   - Confirm a log row exists whose `traceparent` header's `trace-id`
     segment matches.

5. **Record the outcome** in this file (append a dated "Runbook result"
   section below) — pass/fail, and if fail, what did not line up (e.g.
   Supabase not logging the header at all, in which case the correlation
   mechanism needs rethinking before relying on it further).

## Runbook result

_Not yet run — pending a provisioned Sentry DSN. See
`docs/specs/2026-08-28-observability-foundation.md` for the `SENTRY_DSN`
dart-define contract._
