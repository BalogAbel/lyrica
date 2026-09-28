# Client-Abandoned-But-Server-Committed Write (LF-T5b)

**Slice:** fix/offline-catalog-local-first-visibility (R1 review follow-up)
**Related:** `docs/deferred/2026-07-31-occ-divergence-lf-t5.md` (LF-T5) — same
family of "OCC conflict surfaces because two copies diverged", but a
different trigger mechanism; kept as a separate entry because LF-T5's
mitigations (mutation budget, footprint monitor) bound *how much* unsynced
intent can diverge over a long offline span, while this entry is about a
single request's outcome being lost client-side despite succeeding
server-side, which those mitigations do not address.
**Files:**
- `apps/lyron_app/lib/src/infrastructure/observability/tracing_http_client.dart`
  (the 60s response backstop timeout this entry is about)
- `supabase/migrations/202604100001_planning_write_contract.sql`
  (`base_version` OCC check every write RPC is subject to)

## Problem

`TracingHttpClient`'s response-backstop timeout (60s, added alongside a
10s native connect timeout in the R1 review follow-up to
`docs/specs/2026-09-28-offline-catalog-local-first-visibility.md`) bounds
how long the app waits for any single request's response — except
`/auth/v1/token`, which is exempted so an in-flight refresh is never
abandoned mid-rotation. Every other request, including a planning or song
write RPC, can still be abandoned client-side by this timeout after the
server has already committed the write. When that happens, the client's
own local mutation record is still `pending` (the write was never
acknowledged), so the next sync attempt resends the identical logical
write — and the resend's `base_version` now targets a row whose version the
first, successful-but-abandoned attempt already advanced, producing a
false OCC conflict against the client's own prior write, not a real
concurrent edit from anyone else.

## Deferred Because

This is not a new failure class this timeout introduces — an OS-level
connection drop between "server received the request" and "client
received the response" already produced the identical shape before this
timeout existed, since nothing in the client-side mutation/sync machinery
distinguishes "the server never saw this write" from "the server saw it,
committed it, and the acknowledgement was lost." Closing this genuinely
would mean either (a) an idempotency-key scheme so a resend of an
already-applied write is recognized and no-opped rather than OCC-conflicting,
or (b) a reconciliation step that, on an OCC conflict, checks whether the
conflicting server state matches what the client's own abandoned attempt
would have produced (a much harder correctness reasoning: distinguishing
"conflicts with my own lost write" from "conflicts with someone else's
edit"). Either is a protocol-level change to the write-contract RPCs and
the sync reconciler, well beyond a client-side HTTP timeout tuning
follow-up.

## What Covers It Instead

The false-conflict outcome this produces is not silent: an OCC conflict
already surfaces through the same conflict-resolution UI (`keep mine`/
`discard`) as a genuine concurrent-edit conflict, so the user sees *a*
conflict prompt, just with a "conflicts with yourself" cause the UI cannot
currently distinguish from "conflicts with someone else." The 60s bound
also makes this rarer than the pre-existing unbounded-hang shape it
replaces: before this timeout existed, a request could hang indefinitely
with the local mutation record neither confirmed nor released back to a
retriable state, which is a worse user-facing outcome (stuck pending
forever, not just an extra conflict prompt) than what this residual risk
produces.

## Trigger Condition

Address when either of these holds:

- A real user reports (or telemetry surfaces) a conflict-resolution prompt
  where "keep mine" and the server's stored value are byte-identical or
  near-identical — concrete evidence of a self-conflict from an abandoned
  write, rather than a genuine concurrent edit from another device/user.
- A future slice adds idempotency keys to the write-contract RPCs for an
  independent reason (e.g. exactly-once delivery over an unreliable
  transport, or a broader retry-safety hardening pass) — at that point,
  resolving this entry comes largely for free as a side effect.
