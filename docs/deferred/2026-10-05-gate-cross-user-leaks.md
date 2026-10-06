# Startup Gate Review Residuals (C4, F5, N1, N2)

**Slice:** fix/offline-first-startup-gate (found by the adversarial review of
PR 1 on 2026-10-05). The two cross-user leaks of that review, F6 and F7, were
closed by `docs/specs/2026-10-06-cross-user-local-first-ownership.md`
(ADR-037 amendment, 2026-10-06) and removed from this entry.
**Related:**
- `docs/specs/2026-10-05-offline-first-startup-gate.md` (SG1, SG3)
- `docs/plans/2026-10-05-offline-first-startup-gate.md` (Task 8b fixed F1 to
  F4, Task 8c reverted F5; F6 and F7 were the cross-user leaks (closed
  2026-10-06), C4, F5, N1 and N2 are the gate residuals after them)
- `docs/architecture/decisions/ADR-020-non-destructive-session-and-offline-authenticated-state.md`
  (`sessionExpired` is offline-authenticated access, not sign-out)
- `docs/architecture/decisions/ADR-029-reauth-prompt-host-and-different-user-resolution.md`

**Status:** C4, F5, N1 and N2 are low-severity gate cases that show only the
user's own state. None is a cross-user leak.

**Line references** are to the tree at the Task 8c commits of this branch.
Re-verify them before editing.

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

They show only the current user's own state, Retry or sign-in recovers each
of them, and fixing them means changing the gate's resolution bookkeeping,
which PR 1 had just settled.

## Trigger

No fixed slice. Pick these up when a change touches the gate's retry or
resolution bookkeeping (`membershipRetryProvider`,
`ActiveMembershipController`), or when one of them is reported from the
field.
