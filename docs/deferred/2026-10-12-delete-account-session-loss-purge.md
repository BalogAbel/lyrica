# Delete Account Purges Local Data When the Session Is Lost During the Call

**Found:** 2026-10-12, by the Task 4 review of S6a
(`docs/specs/2026-10-12-sync-and-account-feedback.md`, FB9).
**Related:**
- `docs/specs/2026-10-07-sign-out-pending-work-guard.md` (SO3, SO8)
- `docs/architecture/decisions/ADR-035-local-data-purge-contract.md`
- `docs/deferred/2026-10-09-sign-out-guard-residuals.md` (R1: the same flag,
  the sign-out side)

**Files:**
- `apps/lyron_app/lib/src/application/auth/app_auth_controller.dart`
  (`deleteAccount`, `_stateForSession`, `_isSigningOut`)
- `apps/lyron_app/lib/src/presentation/account/account_screen.dart` (the
  Delete account tile, which shows the failure message)

**Status:** pre-existing; reachable but narrow. S6a changed feedback only and
left the purges as they were. Not implemented.

## Problem

`AppAuthController.deleteAccount` sets `_isSigningOut` before it awaits the
`delete_account` RPC and holds it for the whole call. `_stateForSession` maps a
null session to `signedOut` while that flag is set. A session that is lost
while the RPC runs is therefore reported as `signedOut`:

- a non-retryable token-refresh failure, or
- a sign-out in another tab (gotrue broadcasts it across tabs).

`signedOut` is the edge every purge listens to: the catalog and planning
handlers purge the user's local songs, plans and pending work, and the identity
row is cleared. If the RPC then rejects (the lost session is a plausible
reason), `deleteAccount` rethrows, the account survives, and the local data is
already gone.

The failure message of S6a (FB9) makes no claim about local data, so the
message stays true. What is wrong is the purge that ran for a deletion that did
not happen.

## Why it was deferred

- It needs the session to be lost inside one RPC round trip.
- The user confirmed a dialog that says pending offline changes are removed
  with the account, and the purged data is the confirming user's own (XU5, SO4:
  the purge and the identity clear target the observed user, never another).
- Closing it changes the auth state mapping, which is outside the
  copy-and-feedback scope of S6a (its guarantees: no change to the purges or
  the Delete-account semantics).

## Fix sketch

Do not let the call's flag turn a session loss into `signedOut`: a null session
that arrives while `deleteAccount` is in flight maps to `sessionExpired` (the
D2 rule), and `signedOut` is applied only after the RPC returned
successfully. The existing generation check after the call (SO8) already
applies `signedOut` only when no newer auth event arrived.

## Requirements for the slice that picks this up

- ADR-035 purge semantics are unchanged: the purge reasons, targets and the D5
  gate stay as they are. Only which edge fires, and when, changes.
- A confirmed and successful deletion still ends in `signedOut`, with the same
  purges and the same identity clear.
- Red test first, with the real stack: a repository double that emits a null
  session and then throws. Assert that no `signedOut` is emitted, nothing is
  purged, and the state is `sessionExpired`. A companion test keeps the
  success path.
- Coordinate with R1 of the sign-out residuals: it needs the same change to
  how `_isSigningOut` maps a null session.

## Trigger

The next change to `AppAuthController.deleteAccount` or `_isSigningOut`
(including the R1 fix), or a field report of data missing after a failed
Delete account.

Roadmap (2026-10-12): trigger-gated (S9).
