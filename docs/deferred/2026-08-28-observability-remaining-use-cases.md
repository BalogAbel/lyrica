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

## Known gap: stale cross-user `organizationId` in telemetry context

Found in code review of Task 12 (`observabilityUserContextEffectProvider`,
`lib/src/application/auth_providers.dart`), deliberately deferred rather
than fixed inline.

**The gap:** on a `signedIn` transition, the provider reads
`authController.lastKnownIdentity?.organizationId` synchronously, in the
same notify cascade that flips `AppAuthState.status` to `signedIn`. The
spec's own framing ("organizationId is best-effort: `lastKnownIdentity`
may not be populated yet at this exact instant") understates the real
risk: this is not merely "sometimes null" — `lastKnownIdentity` can hold a
**different, prior user's** identity in two real code paths this app
already builds for:

1. Cold start: `_loadIdentity()` reloads whatever `LastKnownIdentity` was
   persisted from the *previous* app session, which may belong to a
   different user (shared device, account switch across a restart).
2. Mid-session different-user reauth: `wipePriorAndProceedFor`/
   `cancelReauthToPriorSession` in `lastKnownIdentityPersistenceProvider`
   exist specifically because this app supports user B signing in while
   user A's identity is still cached. `signedIn` fires for user B before
   that reauth resolution decides anything.

The correct `organizationId` is eventually written by
`lastKnownIdentityPersistenceProvider` (a separate effect reacting to the
same `signedIn` transition), but that write happens after at least one
`await` (often an RPC round trip), and `noteLastKnownIdentity` does not
call `notifyListeners()` — so `observabilityUserContextEffectProvider`'s
listener never re-fires to pick up the corrected value. The stale
(possibly wrong-user) `organizationId` stays attached to
`scope.setContexts('organization', ...)` for the rest of the session,
riding along on every subsequent Sentry event.

**Impact:** telemetry-only (Sentry's `organization` context tag), not a
user-facing or data-integrity bug — no backend authorization decision
reads this value (per AGENTS.md rule 5, authorization is backend-enforced
regardless). But it is a real cross-tenant identifier leak into
observability data, silent and non-self-healing for the rest of the
session.

**Suggested fix**, when this is picked up: only trust the cached
`organizationId` when its `userId` matches the new session's `userId`,
else pass `null`:

```dart
final cached = authController.lastKnownIdentity;
final orgId = cached?.userId == session.userId ? cached?.organizationId : null;
observability.setUserContext(userId: session.userId, organizationId: orgId);
```

Add a regression test for the `sessionExpired` no-op branch at the same
time (currently untested — only `signedIn`/`signedOut` are covered in
`test/application/auth/observability_user_context_effect_test.dart`).

**Trigger:** next observability-focused slice, or sooner if this
surfaces as noisy/wrong `organization` tags in real Sentry data once a
DSN is provisioned.
