# Cross-User Local Data Leaks Found in the Gate Review

**Slice:** fix/offline-first-startup-gate (found by the adversarial review of
PR 1 on 2026-10-05; both are pre-existing, neither is introduced or worsened
by the gate change)
**Related:**
- `docs/specs/2026-10-05-offline-first-startup-gate.md` (SG1, SG3)
- `docs/plans/2026-10-05-offline-first-startup-gate.md` (Task 8b fixed F1 to
  F4, Task 8c reverted F5; F6 and F7 are the leaks below, C4, F5, N1 and N2
  are the gate residuals after them)
- `docs/architecture/decisions/ADR-020-non-destructive-session-and-offline-authenticated-state.md`
  (`sessionExpired` is offline-authenticated access, not sign-out)
- `docs/architecture/decisions/ADR-029-reauth-prompt-host-and-different-user-resolution.md`

**Status:** both entries are PLAUSIBLE from a code read. Neither has a
reproducing test yet; the first step of the fix slice is to write that test
and watch it fail.

**Sequencing:** the fix PR follows the merge of PR 1 of the startup gate and
lands before PR 2 (capabilities and the last-synced indicator). Both leaks
show one user's local data to another user, so they must not wait for the
trigger-gated entries.

**Line references** are to the tree at the Task 8c commits of this branch.
Re-verify them before editing.

## F6 - the catalog reads the unfiltered last known identity (leak class (a))

### Problem

User B can see user A's songs when B's session is lost while a different-user
reauth is pending.

### Event sequence

1. The identity store holds user A (with pending local work).
2. B signs in. The auth state is `signedIn(B)`. The different-user reauth
   dialog is pending (`lastKnownIdentityPersistenceProvider`,
   `apps/lyron_app/lib/src/application/auth_providers.dart`), so the identity
   is still A.
3. B's membership resolves to `selected`, so the gate shows home.
4. B's catalog organization lookup fails (connectivity), so the catalog
   context stays null.
5. B's session goes to null (a non-retryable refresh failure) with
   `_isSigningOut` false.
6. `AppAuthController._stateForSession`
   (`apps/lyron_app/lib/src/application/auth/app_auth_controller.dart:356`)
   computes `lastKnownSession = _state.session ?? ...` at `:375-382`. That is
   B's session, so the state becomes `sessionExpired(B)`. The identity is
   still A.
7. The gate: current user B, known organization null (the identity belongs
   to A), live result for B `selected`, so home.
8. The catalog listener calls `handleOfflineAuthenticated`
   (`apps/lyron_app/lib/src/application/song_catalog_providers.dart:126`;
   method at
   `apps/lyron_app/lib/src/application/song_library/song_catalog_controller.dart:728`).
   Its context is null, so it runs `_tryEstablishLocalFirstContext` with
   `sessionUserId: null` (`:733-738`).
9. There, `userId = sessionUserId ?? identityUserId` (`:778`) is A, because
   the catalog's `lastKnownIdentityReader` returns the identity without
   filtering by the current user
   (`apps/lyron_app/lib/src/application/song_catalog_providers.dart:106-113`).
10. A's catalog context is established, and the song list shows A's songs
    to B.

### Fix sketch

Either:

- In `_stateForSession`, when `identity.userId != _state.session?.userId`,
  build the `sessionExpired` state from the identity (as A) instead of from
  the lost session, so the app never claims offline-authenticated access as
  B over A's data; or
- filter the catalog and planning `lastKnownIdentityReader` closures by
  `authController.state.currentUserId`, so a context is only ever
  established for the current user.

The second is the more general guard; the first fixes the state that makes
the mismatch possible. Decide in the fix slice's design step.

### Test sketch

- Unit: identity A, `signedIn(B)`, emit a null session: expect
  `lastKnownSession.userId == A` (first option).
- Wiring: with the same setup, the catalog context is never established for
  `(A, anything)` while the current user is B (second option).

## F7 - planning state established for A survives B's sign-in (leak class (a))

### Problem

User B can see user A's plans when the app was cold-started into
`sessionExpired(A)` and B then signs in while B's planning organization
lookup fails.

### Event sequence

1. Cold start into `sessionExpired(A)`. The planning listener calls
   `handleOfflineAuthenticated`
   (`apps/lyron_app/lib/src/application/planning_providers.dart:363-365`;
   method at
   `apps/lyron_app/lib/src/application/planning/planning_sync_controller.dart:404`).
2. `_tryEstablishLocalFirstContext` (`:417`) sets `userId` from the identity
   (`:437`) and writes the sync state `(A, X, hasLocalPlanningData: true)`
   (`:481-488`). The active planning context controller stays null
   (`planning_providers.dart:285-286`, `sessionExpired` does nothing there).
3. B signs in. The gate resolves B to `selected`, so home.
4. B's planning organization lookup fails (connectivity). The active
   planning context stays null, so no change event reaches
   `handleActiveContextChanged`.
5. The `signedIn` case of the planning sync listener does nothing
   (`planning_providers.dart:367-368`). The sync state is still
   `(A, X, hasLocalPlanningData: true)`.
6. `_readPlanningOrThrow`
   (`apps/lyron_app/lib/src/presentation/planning/planning_providers.dart:86-103`)
   skips `refreshPlanning` because `hasLocalPlanningData` is true. That
   refresh is the only place with the I3 ownership guard
   (`planning_sync_controller.dart:219-232`, in `_refreshPlanning`).
7. `PlanList` reads A's plans for B.

### Fix sketch

In the `signedIn` case of the planning sync listener, reset the sync state to
initial when `state.userId != null && state.userId != session.userId`, the
same reset the I3 guard performs, but at the auth edge instead of inside a
refresh that may never run.

### Test sketch

`sessionExpired(A)` with a planning projection cached for `(A, X)`, then
`signedIn(B)` with a planning organization reader that fails: expect
`planningSyncState.userId != A` (and `hasLocalPlanningData` false).

## C4 - sessionExpired(A) loses its cache-only result after a cancelled reauth (gate residual, not a leak)

### Problem

A user in `sessionExpired(A)` with no known organization can see the
connectivity failure screen again after a different user's reauth is
cancelled, although Retry had already opened home for A.

### Event sequence

1. `sessionExpired(A)`, A has no known organization (identity organization
   null). A taps Retry; `membershipRetryProvider`
   (`apps/lyron_app/lib/src/application/auth_providers.dart:810`) resolves
   from the cache only and records `selected(X)` for A. The gate shows home.
2. B starts signing in. The auth state becomes `signedIn(B)`; the status
   listener in `membershipRefreshEffectProvider`
   (`auth_providers.dart:858-862`) starts B's resolution, so
   `ActiveMembershipController.beginResolution(B)`
   (`apps/lyron_app/lib/src/application/auth/active_membership_controller.dart:101`)
   runs. Its `_lastUserId != userId` branch (`:103-105`) clears A's stored
   result.
3. The different-user reauth is cancelled and the app returns to
   `sessionExpired(A)`. The listener starts a resolution only for a
   `signedIn` edge (`auth_providers.dart:858`), so nothing refreshes A.
4. A has no known organization and no live result, so the gate shows the
   connectivity failure screen.

### Why it is low

No other user's data is shown, and A's own data is untouched. Retry
recovers in one tap (it reads the cache again). The screen is a status, not
a loss.

### Fix sketch

Start a cache-only resolution on a `sessionExpired(user)` edge when the user
has no known organization (the same reader Retry uses), or keep per-user
results instead of one slot. Decide in the slice that picks this up.

### Test sketch

Wiring: `sessionExpired(A)` without a known organization and a cached
organization for A, Retry, then `signedIn(B)`, then back to
`sessionExpired(A)`: expect home for A without a Retry.

## F5 - the invite-required screen can flash after a redemption (cosmetic, old)

### Problem

With no known organization, a live `verifiedEmpty` and a pending invite, a
successful redemption refreshes membership but the same-user `verifiedEmpty`
stays until the answer arrives. `RedeemEffect` clears the pending invite
first, so the invite-required screen shows for the length of the RPC.

### Where

`auth_providers.dart:880-882` (the redeem-success listener only calls
`scheduleRefresh()`); the stored result survives `beginResolution` for the
same user (`active_membership_controller.dart:103-106`).

### Why it is deferred

Task 8b added `membershipController.reset()` before the refresh. Task 8c
reverted it (`91057dc`): the reset let a late pre-redeem result be accepted
over the post-redeem resolution (C3) and could wipe another user's live
result when a user switch happened during the redeem RPC (C5). With the
per-resolution token (Task 8c) the first of those is closed independently,
but the flash itself is old and cosmetic, so it stays deferred.

### Fix sketch

Hold the redeem screen until the refresh answers: let `beginResolution` take
a flag that hides the stored result for this resolution only (a view concern,
not a reset), or make the gate treat "redemption succeeded, refresh running"
as `resolving`. Either must not clear another user's state.

### Test sketch

The wiring test removed with the revert: live `verifiedEmpty` plus a pending
invite, then redeem success and clearing the pending invite; no recorded view
is `inviteRequired`, the final view is `resolving`, and the answer opens the
gate.

## N1 - Retry with no current user writes an ownerless result (gate residual, non-blocking)

### Problem

A Retry tapped in the window between a sign-out and the router redirect can
store a result that belongs to nobody. The late result then either shows a
failure to the next user or overwrites that user's result.

### Event sequence

1. `signedIn(A)` on the connectivity-failure view.
2. A goes to `signedOut` (explicit sign-out, or a null session with no
   identity). Retry is tapped in the window of at most one frame before the
   router redirects.
3. `currentUserId` is null, so `membershipRetryProvider` passes no token
   (`apps/lyron_app/lib/src/application/auth_providers.dart:817-819`). The
   anonymous RPC is denied (EXECUTE is granted to `authenticated` only,
   `supabase/migrations/202605160007_*.sql:25-35`), giving
   `nonConnectivity`, or `connectivity` when offline. The cached fallback is
   skipped because the user is null
   (`apps/lyron_app/lib/src/application/active_organization_resolution.dart:104`).
4. The token-less `update(userId: null)` is applied through the legacy path
   (`apps/lyron_app/lib/src/application/auth/active_membership_controller.dart:128-168`),
   and `_lastUserId` stays null (`:164-166`).
   - (5a) If the late update lands before `beginResolution(B)`: `last`
     returns it for any user (`:62`, `_lastUserId` null) and
     `beginResolution(B)` does not clear it (`:103`), so B briefly sees
     `nonConnectivity` until B's own result arrives.
   - (5b) If it lands after B's result was `verifiedEmpty`: the token-less
     path overwrites B's result and B is stuck on `nonConnectivity` with no
     Retry (that view has none).

### Why it is non-blocking

It needs a tap within one frame and an anonymous RPC that outlives B's whole
sign-in and resolution. The ownerless result is never `selected` and never
another user's organization.

### Fix sketch

`if (userId == null) return;` in `membershipRetryProvider`. Optionally make
`token` required on `update` and delete the legacy token-less branch; this is
its only production caller.

### Test sketch

Wiring: Retry with a null current user calls neither the raw reader nor the
controller.

## N2 - Session lost mid-resolution yields nonConnectivity without Retry (gate residual, non-blocking)

### Problem

A user whose session is lost while the first resolution runs ends on a
failure screen that offers sign-in but no Retry.

### Event sequence

1. `signedIn(A)` with no known organization and `refreshMembership` in
   flight.
2. A non-retryable token refresh failure moves the state to
   `sessionExpired(A)`. The token stays current because the user is
   unchanged.
3. The RPC errors with an `AuthException`, so the result is
   `nonConnectivity` with no cached fallback
   (`apps/lyron_app/lib/src/application/active_organization_resolution.dart:78-82`,
   `:104`); it is applied.
4. The `nonConnectivity` view has no Retry, only Sign in
   (`apps/lyron_app/lib/src/presentation/auth/membership_gate.dart:42-46`).

### Why it is non-blocking

Own user only, sign-in is offered, and the behaviour was the same before the
gate change.

### Follow-up

Offer the cache-only Retry on the `nonConnectivity` view when
`isSessionExpired`.

## Why these were deferred

Both leaks predate the gate change and are reachable through other,
already-existing paths (the sketches above do not involve the gate's new
decision). Fixing them in this PR would widen it into the auth controller,
the catalog controller and the planning sync controller. The user decided on
2026-10-05 to keep PR 1 to the gate and to record these here.

## Trigger

Pick this up right after PR 1 merges and before PR 2 (see Sequencing above).

## Requirements for the slice that picks this up

- Red tests first, for both sequences, before any fix.
- A different-user session must never be able to read the previous user's
  catalog or planning projection through a local-first path (SG3, ADR-029).
- No purge may be triggered by the fix: only the in-memory state and the
  context establishment change. The purge contract stays ADR-035.
