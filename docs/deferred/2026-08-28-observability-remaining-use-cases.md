# Deferred: Remaining observability instrumentation

## Context

`docs/specs/2026-08-28-observability-foundation.md` (ADR-036) introduces
the `Observability` abstraction and `SentryObservability` adapter, and
instruments exactly one vertical slice end-to-end (song catalog refresh +
sign-in) to prove the pattern. This document tracks what is intentionally
left uninstrumented so it stays visible for future slice planning, per
AGENTS.md.

## Deferred instrumentation targets

- **Planning mutation sync** (`PlanningMutationSyncController._run` and
  the single-flight sync scheduler) — root trace per sync batch, child
  spans per mutation send and per full-refresh call.
- **Song mutation sync / discard** — root trace per sync/discard run,
  including the context-wide ownership-lease acquisition described in
  `docs/architecture/architecture.md`'s Offline Strategy section.
- **Storage eviction** (`SongCatalogEvictor`, `LocalStorageWriteRecovery`)
  — span around the evict-once/retry-once recovery path, since this is a
  failure-triggered path worth seeing in traces when it fires.
- **Unified sync overview / `UnifiedManualSyncController`** — root trace
  for the aggregated `syncNow` command that fans out to song and planning
  sync.
- **Planning read/write repository methods** beyond the catalog slice
  (plan/session/session-item CRUD RPC calls) — child spans analogous to
  `SupabaseSongRepository`.
- **Membership/invitation redemption** (`redeem_invitation` RPC) — root
  trace, given this is a security-sensitive, backend-enforced boundary
  worth tracing distinctly from ordinary reads.

## Trigger

Pick up in the phase immediately following this one, or sooner if a
production incident in one of the above areas makes the missing trace
data costly. No hard deadline — this is debt visibility, not a blocking
gap, since the app still functions identically to before this slice for
every uninstrumented path.

## Non-triggers

Do not instrument a use case just because it is on this list without a
concrete reason (an incident, a planned reliability push, or the next
scheduled phase reaching it) — instrumenting ahead of need adds
maintenance surface (test doubles, span-name bookkeeping) with no
observed benefit yet.
