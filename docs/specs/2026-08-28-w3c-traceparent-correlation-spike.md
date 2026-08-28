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

`test/infrastructure/observability/w3c_trace_context_test.dart` proves,
without any network access or real Sentry project:

1. `buildTraceParent(traceId: ..., spanId: ...)` produces a string matching
   `^00-[0-9a-f]{32}-[0-9a-f]{16}-0[01]$`.
2. The `trace-id` segment of the header exactly equals the span's Sentry
   `traceId` (hex, no dashes, 32 chars — Sentry's own trace ID format is
   already W3C-compatible).
3. The `parent-id` segment exactly equals the span's Sentry `spanId` (hex,
   16 chars).
4. `TracingHttpClient` attaches this header to every outgoing request when
   `Observability.currentTraceParent` is non-null, and omits it cleanly
   (no empty header) when there is no active span.

This proves the **header contract** is correct. It does not prove Supabase
Cloud actually surfaces that header value somewhere queryable — that
requires a live project.

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
