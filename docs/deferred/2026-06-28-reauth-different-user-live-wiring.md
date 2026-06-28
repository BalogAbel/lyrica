# Different-User Re-auth: Live Dialog Wiring

**Slice:** offline-session-resilience (non-destructive-session plan, Task 9)
**Files:**
- `apps/lyron_app/lib/src/application/auth/reauth_resolution.dart` (ready, tested seam)
- `apps/lyron_app/lib/src/presentation/auth/reauth_different_user_dialog.dart` (ready, tested)
- `apps/lyron_app/lib/src/application/providers.dart` (integration point — not yet wired)

## Problem

The different-user re-auth confirmation flow has a fully tested, UI-agnostic coordinator
(`resolveReauth`) and a confirmation dialog (`showReauthDifferentUserDialog`), but they are
not yet invoked by the live sign-in path. Today a different-user sign-in while a prior user is
offline-authenticated simply loads the new user's data (keyed by the new `userId`/org); the prior
user's cached data and pending mutations remain orphaned in the local store. This is
**non-destructive** (no data loss) but does not yet present the spec's confirmation nor clean up
the prior user's data on confirm.

## Deferred Because

Presenting a confirmation dialog from the auth/provider layer requires a UI host: the app currently
shows every dialog via `showDialog(context: ...)` from widgets, and there is no
`GlobalKey<NavigatorState>` or dialog-service seam. Wiring `confirmDifferentUser` into the live
`signedIn` transition needs either (a) a navigator key on `MaterialApp.router`, or (b) a
`ReauthPromptController` (ChangeNotifier) holding a pending request that a host widget in the
authenticated shell observes and resolves. Both touch app bootstrap and the critical auth flow, and
were kept out of this slice to avoid regressions in the live sign-in path. The coordinator's
callbacks (`flushSameUser`, `wipePriorAndProceed`, `cancelToPriorUser`) must also be bound to the
real catalog/planning cleanup + sync + new-session sign-out paths.

## Expected Behavior When Wired

1. On a fresh `signedIn` after `sessionExpired`, compute `priorUserId`/`priorEmail` from
   `LastKnownIdentity` and the new `userId` from the session.
2. Same user → `flushSameUser` (existing refresh + `syncPendingMutations`).
3. Different user, no prior pending mutations → wipe prior data + identity, proceed as new user.
4. Different user, prior pending mutations exist → `showReauthDifferentUserDialog` with the prior
   email + pending count (`readPendingMutations(userId, organizationId).length`). Confirm → clear
   prior user's catalog + planning data + identity, then proceed as new user. Cancel/dismiss →
   sign out the new session and stay offline-authenticated as the prior user (safe default).

## Trigger Condition

Address before shipping the multi-account / account-switching slice. Any PR that introduces a
navigator key, a dialog-service, or touches the `signedIn` resolution in `providers.dart` must
wire `resolveReauth` through and add an integration/widget test covering confirm + cancel.
