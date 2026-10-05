# Cross-User Local Data Leaks Found in the Gate Review

**Slice:** fix/offline-first-startup-gate (found by the adversarial review of
PR 1 on 2026-10-05; both are pre-existing, neither is introduced or worsened
by the gate change)
**Related:**
- `docs/specs/2026-10-05-offline-first-startup-gate.md` (SG1, SG3)
- `docs/plans/2026-10-05-offline-first-startup-gate.md` (Task 8b fixed F1 to
  F5; these are F6 and F7)
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

**Line references** are to the tree at the Task 8b commits of this branch.
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
