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
  (the 60s general response backstop and the separate, longer 120s
  token-refresh backstop this entry is about)
- `supabase/migrations/202604100001_planning_write_contract.sql`
  (`base_version` OCC check every write RPC is subject to)
- `apps/lyron_app/lib/src/infrastructure/auth/supabase_auth_repository.dart`
  (`deleteAccount` — a committed-then-abandoned call here reports failure
  to the user even though the account is genuinely gone)
- `apps/lyron_app/lib/src/infrastructure/auth/supabase_invitation_repository.dart`
  (`redeemInvitation` — a retry after an abandoned-but-committed first
  attempt returns `already_redeemed` instead of success, since the
  migration's `redeemed_at` check runs before the already-member check)
- gotrue's `/auth/v1/otp` (magic-link send) — a retry after an
  abandoned-but-committed first attempt can send a duplicate email or hit
  a rate limit, surfacing as a spurious failure to the user

## Problem

`TracingHttpClient`'s response-backstop timeout (60s general, 120s for
`/auth/v1/token` specifically — see ADR-037's "Amendment: three-tier HTTP
timeout", I1) bounds how long the app waits for any single request's
response. `/auth/v1/token` gets the longer 120s bound rather than no bound
at all, because gotrue-2.27.2 dedups concurrent refresh attempts for the
same token into one shared completer (`_pendingRefreshes`,
`GoTrueClient._callRefreshToken`) that every subsequent REST/RPC call
awaits before proceeding (`SupabaseClient._getAccessToken`) — an
unbounded hang there would stall the whole app, not just the refresh, so
it cannot be left unbounded even though it is the request most sensitive
to being abandoned mid-commit. Every other request, including a planning
or song
write RPC, can still be abandoned client-side by this timeout after the
server has already committed the write. When that happens, the client's
own local mutation record is still `pending` (the write was never
acknowledged), so the next sync attempt resends the identical logical
write — and the resend's `base_version` now targets a row whose version the
first, successful-but-abandoned attempt already advanced, producing a
false OCC conflict against the client's own prior write, not a real
concurrent edit from anyone else.

**Beyond the OCC write-contract RPCs**, the same abandon-after-commit shape
applies to three other one-shot calls that are not OCC-guarded, so each
fails in its own way rather than producing a conflict prompt (found during
the PR #79 adversarial review, I2):

- `deleteAccount` (`supabase_auth_repository.dart`): an abandoned-but-
  committed call reports failure to the user even though the account is
  genuinely gone.
- `redeemInvitation` (`supabase_invitation_repository.dart`): a retry after
  an abandoned-but-committed first attempt returns `already_redeemed`
  instead of success — the migration's `redeemed_at` check runs before the
  already-member check.
- `/auth/v1/otp` (magic-link send): a retry after an abandoned-but-
  committed first attempt can send a duplicate email or hit a rate limit.

None of these were newly introduced by the timeout work — they are the
same class of narrowing (bounding a previously-unbounded hang) applied
uniformly, not a defect specific to any one of them — but they are recorded
here explicitly since none is covered by the mutation-budget/footprint
mitigations "What Covers It Instead" describes below, which are specific
to the planning/song mutation stores.

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
