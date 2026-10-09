# Sign-Out Pending-Work Guard

> Status: approved 2026-10-09 with two additions (W3 offline sign-out, the
> explicit catalog lifetime in SO1)

**Branch:** `fix/sign-out-pending-work-guard`
**Roadmap:** a small fix PR after the cross-user ownership PR (#86) and
before S0 PR 2 in `docs/plans/2026-10-01-delivery-roadmap.md`
**Resolves:** W1 and W2 below (found at the end of #86, not recorded in the
repository before this spec), W3 (found at the design gate), and O1 of
`docs/deferred/2026-10-05-gate-cross-user-leaks.md`
**Builds on:** ADR-020, ADR-029 (D4, D5, honest null count), ADR-035
(unchanged; D2, D5.4 and D5.5), ADR-037 (current-user ownership amendment,
XU5)
**Plan:** `docs/plans/2026-10-07-sign-out-pending-work-guard.md`
**Reproduction suites:**
`apps/lyron_app/test/integration/sign_out_pending_work_guard_test.dart` (W1,
W2) and the O1 group of
`apps/lyron_app/test/integration/cross_user_local_first_leak_test.dart`

## Problem

An explicit sign-out deletes the signing-out user's local data, including
unsynced work. That is the product decision of 2026-08-19
(`docs/specs/2026-08-19-local-data-durability-contract.md`, D1) and it stays.
The warning in front of it is not reliable, and the identity clear behind it
is not scoped to the signing-out user.

### W1 — the Account sign-out never warns (reproduced, data loss)

`AccountScreen`'s Sign out tile calls `AppAuthController.signOut()` directly
(`apps/lyron_app/lib/src/presentation/account/account_screen.dart`,
`onTap: () => controller.signOut()`). The `signedOut` edge then runs the
catalog and planning sign-out purges through their auth listeners. No
warning is shown.

Reproduced with the whole app (`LyronApp`, real router, gate, auth
controller, lifecycle, listeners, Drift in-memory stores; only the network
is replaced): cold start into `sessionExpired(A)` with A's songs, plans and
one pending planning mutation; go to `/account`; tap Sign out. Observed: no
dialog, `signedOut`, A's pending mutation 1 → 0.

### W2 — the song-list warning is context-scoped (reproduced, data loss)

`SongListScreen._signOut` warns when
`unifiedSyncOverviewProvider.hasUnsyncedWork` is true. That flag is built
from the mutation rows of the **active** catalog and planning contexts. A
context exists only when a cached snapshot (catalog) or projection
(planning) exists for the current user and organization. The purge, however,
is user-wide: `purgeSongCatalog` and `purgePlanningData` delete every
organization of the user, with or without a context.

Since #86 (XU5) the explicit sign-out purges the user who signed out, taken
from `CurrentUserOwnership.userId`. In `sessionExpired(A)` with no context
the old purge target chain fell through to nobody, so nothing was deleted;
that was accidental, and XU5 closed the "purges nobody" branch on purpose.
The warning did not follow.

Reproduced with the same harness: cold start into `sessionExpired(A)` with
one pending planning mutation of A's and neither cached songs nor a cached
projection, so no catalog and no planning context is established. Song
list, overflow menu, Sign out. Observed: no dialog, `signedOut`, A's pending
mutation 1 → 0.

The same class (code read): pending work of the same user in an organization
other than the active one, and pending song work while no catalog context
is established, are deleted without a warning.

A guard in the same suite pins the harness: with a planning context
established, the song list's current check warns, and Cancel deletes
nothing. Green today.

### W3 — an offline sign-out raises an unhandled error (reproduced)

gotrue 2.27.2 signs out in two steps (`gotrue_client.dart:1085-1108`,
`_signOut`): it drops the local session (`_removeSession()`), emits
`signedOut`, and only then calls `admin.signOut` on the backend. A failure of
that call is rethrown unless it is a 401, 403 or 404, and gotrue's fetch
turns any failure to send (`fetch.dart:188-190`) into an
`AuthRetryableFetchException` without a status code.

`AppAuthController.signOut()` awaits the whole repository call. Offline, the
`signedOut` event has already made the state `signedOut` (the app initiated
the sign-out), and the sign-out purges have already run, but `signOut()`
then throws. Both sign-out controls start it with `unawaited`, so the error
is unhandled (on native, Sentry records it as an unhandled event). On a
network that never answers, the call runs until the response backstop of
`TracingHttpClient` (60 s for this request,
`infrastructure/observability/tracing_http_client.dart`); a command lock
held for the whole call (SO3) would block every further sign-out for that
long.

Reproduced with the whole app and a client whose every request fails at
once (a dropped connection), a persisted valid session for A (so the app
starts `signedIn(A)` and the sign-out calls the backend), and the song
list's confirmed sign-out: `AuthRetryableFetchException(message:
ClientException: network is unreachable, statusCode: null)` escaped
unhandled; the state was `signedOut` and the purge had run.

### O1 — an explicit sign-out clears another user's identity row (reproduced)

`lastKnownIdentityPersistenceProvider`'s `signedOut` case calls
`lifecycle.clearIdentity(reason: PurgeReason.userSignOut)` with no user
(`apps/lyron_app/lib/src/application/auth_providers.dart`), so it clears
whatever `LastKnownIdentity` row is on file.

Reproduced in the ownership suite (real auth controller, lifecycle, reauth
providers):

1. Cold start into `sessionExpired(A)`; A has pending work, so B's sign-in
   leaves the different-user prompt pending and A's identity on file.
2. (a) B loses the session (`sessionExpired(B)`) and signs out, or (b) B
   signs out while A's prompt is still pending.
3. Observed in both: the identity row is gone (expected A's).

A's songs, plans and pending work stay on disk (XU5 purges B), but A's next
offline cold start lands on `signedOut` instead of `sessionExpired(A)`. A
guard in the same group (A's own sign-out clears A's row) is green today.

### Sign-out entry points (mapped with graphify, then grep)

| Entry point | Today | After this spec |
|---|---|---|
| Song list, overflow menu, Sign out (`SongListScreen._signOut`) | context-scoped warning (W2), then `handleExplicitSignOut` on catalog and planning, then `AppAuthController.signOut()` | `SignOutCommand` (SO1) |
| Account, Sign out tile | `AppAuthController.signOut()`, no warning (W1) | `SignOutCommand` (SO1) |
| Account, Delete account | its own confirmation dialog, whose message already names "any pending offline changes"; then `deleteAccount()` → `signedOut` | unchanged; SO4 applies through the same edge |
| `AppAuthController.cancelReauthToPriorSession` | backend sign-out of the cancelled user, state `sessionExpired(prior)`; non-destructive (ADR-029 D5) | unchanged |
| A null session with no identity on file (ADR-035 D2) | `signedOut` without an explicit act | unchanged, out of scope |

The `signedOut` edge drives three listeners: the catalog
(`song_catalog_providers.dart`, `handleExplicitSignOut`), planning
(`planning_providers.dart`, `handleExplicitSignOut`) and the identity
(`lastKnownIdentityPersistenceProvider`, `persistIdentity`). The Account
screen has no in-app link; it is reachable at `/account` (by URL on web).

## Invariant

> An explicit sign-out deletes unsynced work only after the user confirmed
> it, whenever the signing-out user's user-wide pending count is nonzero or
> unknown. The count, the purge and the identity clear all target the same
> user: the user who signed out. No sign-out touches another user's data or
> identity row. A sign-out completes at the local sign-out, whatever the
> network does, and never raises an unhandled error.

## Constraints (from the task, all kept)

- No new purge, no new `PurgeReason`, no new store delete; ADR-035 is not
  changed. The `userSignOut` purges (targets per XU5) and the
  `LocalDataLifecycle.clearIdentity` gate are reused as they are.
- A confirmed explicit sign-out still deletes (2026-08-19). Only the warning
  becomes reliable.
- XU1–XU6 of the ownership spec are untouched.
- Authorization stays backend-enforced; nothing here is an authorization
  decision.

## Decisions

### SO1 — one application-layer sign-out command for every entry point

`SignOutCommand` (`application/auth/sign_out_command.dart`) holds the
sign-out rule once. It has no `Ref`; its inputs are injected:

```dart
enum SignOutOutcome { signedOut, cancelled, superseded, alreadyRunning, failed }

typedef SignOutConfirmation = Future<bool> Function(int? pendingCount);

class SignOutCommand {
  SignOutCommand({
    required String? Function() currentUserIdReader,
    required Future<int> Function({required String userId}) countPendingWork,
    required Future<void> Function() signOut,
    required void Function(Object error, StackTrace stackTrace) reportError,
  });

  Future<SignOutOutcome> run({required SignOutConfirmation confirmDiscard});
}
```

`signOutCommandProvider` (`auth_providers.dart`) wires it:

- `currentUserIdReader`: `AppAuthController.state.currentUserId`.
- `countPendingWork`: `pendingLocalWorkCounterProvider` (SO2).
- `signOut`: the song list's current sequence, unchanged:
  `songCatalogControllerProvider.handleExplicitSignOut()`, then
  `planningSyncControllerProvider.handleExplicitSignOut()`, then
  `AppAuthController.signOut()`.
- `reportError`: `FlutterError.reportError` (a handled error, SO3).

The provider is app-scoped (not `autoDispose`), like
`reauthPromptControllerProvider`: the command awaits a count and a dialog,
and in Riverpod 3 a `Ref` used after its provider was disposed throws
(checked with context7).

**The catalog controller's lifetime is held explicitly.**
`songCatalogControllerProvider` is `autoDispose`. In the running app it
happens to live as long as the app (`LyronApp` holds planning, whose active
planning context listens to the catalog context), but the command does not
rely on that chain. For the duration of the sign-out sequence it holds a
`ref.listen(songCatalogControllerProvider, …)` subscription, reads the
controller through it, and closes it in a `finally`. The catalog purge and
the catalog's own `signedOut` listener therefore run from whichever screen
started the sign-out, and the controller is released afterwards. Riverpod
3.4.3 allows `Ref.listen` outside a provider's build while the ref is
mounted (`ref.dart`, `_throwIfInvalidUsage`), and a non-`autoDispose`
provider may listen to an `autoDispose` one; a listen subscription keeps an
`autoDispose` provider alive until it is closed (context7).

Presentation (`presentation/auth/sign_out_flow.dart`):

- `showUnsyncedSignOutDialog(context, pendingCount:)`, shaped like
  `showMembershipRevocationPurgeDialog`: a known count is named, `null`
  shows the unknown message, a barrier dismiss is Cancel.
- `signOutWithPendingWorkGuard(context, ref)`: reads the command once,
  before any await, and runs it with a confirmation that shows the dialog,
  or answers `false` if the context is no longer mounted. The command
  outlives the widget (the router may replace the screen meanwhile).

`SongListScreen` and `AccountScreen` call `signOutWithPendingWorkGuard`;
neither calls `AppAuthController.signOut()` or a sign-out handler any more.

### SO2 — the warning is decided from the signing-out user's user-wide count

The command reads `currentUserId` once at the start and counts with
`PendingLocalWorkCounter.count(userId:)`, the counter ADR-029 D4 already
uses for the different-user wipe. Its scope is the purge's scope: every
planning mutation row of the user in any status and any organization
(`deletePlanningDataForUser`), and every non-synced song mutation row of
the user in any organization (`deleteCatalogsForUser`). No context is
needed.

- `0` → sign out without asking.
- `> 0` → ask, naming the count.
- the count throws, or there is no current user → `null` → ask with the
  unknown message (ADR-029 honest null, ADR-035 D5.4: uncertainty only ever
  forces the question; it never authorises a deletion and never becomes a
  fabricated number).

The count user, the purge user (XU5: `CurrentUserOwnership.userId` of the
catalog and planning holders) and the identity-clear user (SO4) are the
same: each is the last non-null `AppAuthState.currentUserId`, and sign-out
controls exist only in `signedIn` and `sessionExpired`.

The new rule warns in every case the old check warned in: the old rows
belonged to the current user's active context, a subset of what the
user-wide count counts.

### SO3 — confirmation, re-validation, one run at a time, offline completion

- Cancel, a barrier dismiss, or an unmounted context → `cancelled`. Nothing
  is deleted and no state changes.
- Before signing out (after a zero count, and again after a confirmation)
  the command re-reads `currentUserId`. If it is no longer the counted
  user → `superseded`, nothing is deleted: the other user's work was never
  counted or shown. The same user proceeds: nothing can add work behind the
  modal dialog, and sync only removes rows.
- A second `run` while one is in flight → `alreadyRunning`, no dialog (a
  double tap on the Account tile). The lock is held until the **local**
  sign-out, not until the backend answers (next bullet).
- The dialog is awaited outside every lifecycle chain (ADR-035 D5.5 rule 2
  holds trivially: the command is not on the chain).

**Offline completion (closes W3).** `AppAuthController.signOut()` completes
at the local sign-out:

- It starts the repository's sign-out and completes as soon as either the
  auth stream reports the null session of this sign-out (gotrue emits it
  after dropping the local session and before any network call) or the
  repository call settles, whichever is first. It then applies `signedOut`
  and resets `_isSigningOut` (the existing "signedOut is sticky" rule covers
  a late null event). The backend revocation keeps running on its own.
- The revocation's result is handled exactly once, after the local sign-out
  has been applied, so the state is already `signedOut` by construction:
  a connectivity failure (`isConnectivityFailure`, which includes
  `AuthRetryableFetchException`) is not an error and is not reported; any
  other failure is reported once through `FlutterError.reportError` as a
  handled error. `signOut()` never throws a revocation failure, and its
  caller's outcome is `signedOut`.
- A failure that lands before gotrue's `signedOut` event (for example a
  local storage failure while gotrue clears its code verifier) still ends in
  `signedOut`: gotrue drops the in-memory session synchronously before its
  first await. It is not a connectivity failure, so it is reported once.
- Offline, the server-side session is not revoked. That is unchanged: before
  this spec the revocation failed the same way and nothing retried it.

**Errors in the command.** No sign-out control may raise an unhandled
error. An error from the sign-out sequence (for example a failed local
purge) is reported once through `reportError`; the outcome is `failed` and
the lock is released, so the user can try again. An error while asking (the
confirmation callback throws) is reported once and counts as not confirmed
(`cancelled`). An unreadable count is not an error; it becomes `null`
(SO2).

### SO4 — the identity clear targets the user who signed out (closes O1)

`lastKnownIdentityPersistenceProvider` holds one `CurrentUserOwnership`.
`scheduleIdentityResolution` feeds it every non-null `currentUserId`
synchronously, before queueing the resolution, and for a `signedOut`
notification captures `ownership.userId` as the signing-out user at that
moment. The capture must be synchronous: the resolution chain can be
blocked behind a pending different-user prompt.

`persistIdentity`'s `signedOut` case passes that user:
`lifecycle.clearIdentity(reason: PurgeReason.userSignOut, userId: …)`. The
existing gate in `LocalDataLifecycle._clearIdentityLocked` clears only a row
that belongs to that user (D5.5 rule 5). With no observed user, nothing is
cleared: an unknown signing-out user never authorises the clear.

Account deletion reaches the same `signedOut` edge and gets the same
target.

### SO5 — what does not change

The purges and their targets (XU5), `PurgeReason.userSignOut` for both
sign-out and account deletion (the known ADR-035 gap), the
`LocalDataLifecycle` chain, the auth state machine (ADR-020 D2, ADR-035 D2),
the different-user reauth flow (ADR-029) and XU1–XU6.

ADR-035's D1 table lists `userSignOut` with confirmation "none". That column
is the purge's own gate, which stays none: the purge runs when the user
activates sign-out. The warning precedes that act. The song list showed it
before this spec too, under the same table. No ADR-035 change.

## Rejected alternatives

- **Keep the context-scoped check and add a dialog to Account only.**
  Leaves W2 and the other-organization case open.
- **Decide the warning in each screen.** The rule would be duplicated per
  entry point; a third entry point would repeat W1. It is behaviour, so it
  belongs in the application layer.
- **Gate the purge itself on confirmation** (in the handlers or the
  `signedOut` listeners). Changes ADR-035's contract and the listener-driven
  edge, and handlers cannot show UI.
- **O1 via an auth-state discriminator** (a `signedOut` state carrying the
  previous user). Changes `AppAuthState`'s shape, which ADR-035 already
  scoped out; the capture is local to the one listener.
- **O1 via `AppAuthController.lastKnownIdentity`.** That is the stored row's
  user, not the signing-out user: exactly O1's defect.
- **W3 by catching in the screens.** The error would no longer be unhandled,
  but the command would still wait for the backend, holding its lock for up
  to 60 s on a network that never answers.
- **W3 by applying `signedOut` before calling the repository.** It would
  rely on the order of gotrue's internals instead of on gotrue's own
  `signedOut` event; waiting for that event (or the call settling) is the
  local sign-out itself.
- **Keep the catalog controller alive through the planning chain.** The
  chain is an accident of the provider graph; an explicit subscription
  states the requirement where it is needed.

## Intentional behaviour changes

1. The song list warns from the user-wide count: also without a context, for
   other organizations, and when the count cannot be read. The message names
   the count or says it is unknown (`AppStrings.unsyncedSignOutMessage` is
   replaced by `unsyncedSignOutPendingMessage(count:)` and
   `unsyncedSignOutUnknownPendingMessage`).
   `apps/lyron_app/test/presentation/song_library/song_list_screen_test.dart`:
   "shows a warning before sign out when unsynced changes exist" and "shows a
   warning before sign out when planning mutations are unsynced" drive the
   old source (an overview override and the old message). They are rewritten
   to seed pending rows and to expect the count message.
2. The Account sign-out warns.
3. B's sign-out keeps A's identity row; A's next offline cold start returns
   to `sessionExpired(A)`, A's own view (ownership spec, XU4).
4. `apps/lyron_app/test/application/auth/identity_persistence_wiring_test.dart`,
   "stale signedIn persistence does not rewrite after signedOut clears
   identity": `clearCount` 1 → 0. User-1's identity was never written, so the
   user-scoped clear finds no row of user-1 and clears nothing. The test's
   subject (no rewrite after sign-out) is unchanged.
5. The audit row of a sign-out identity clear carries the user id (was null).
6. `AppAuthController.signOut()` completes at the local sign-out and never
   throws a backend revocation failure (W3). No existing test expects it to
   throw (checked: `app_auth_controller_test.dart` uses `signOutError` only
   with `cancelReauthToPriorSession`).

## Out of scope (pre-existing, unchanged)

- ADR-035 D2's no-identity branch: a null session with no identity on file
  maps to `signedOut`, and the listeners purge. Not an explicit sign-out
  entry point; accepted in ADR-035 D2 (PR #73 review finding 4).
- `accountDeleted` versus `userSignOut` (ADR-035 known gap).
- The organization switch that drops pending planning mutations (S5b,
  `docs/deferred/2026-10-01-org-switch-drops-pending-planning-mutations.md`).
- O2, O3, C4, F5, N1 and N2 of the deferred entry.

## Acceptance criteria

Each criterion is a test. The reproduction tests are committed skipped with
the spec and are red before their task and green after.

- **AC1 (W1):** Account, Sign out with A's pending planning mutation and
  pending song mutation: the warning shows, the state stays
  `sessionExpired`, both stay.
- **AC2 (W2):** song list, Sign out in `sessionExpired(A)` with no catalog and
  no planning context and A's pending work: the same.
- **AC3 (confirmed sign-out still deletes):** in AC1 and AC2, confirming
  signs out, deletes A's pending planning and song work and clears A's
  identity row.
- **AC4 (guard):** song list with a planning context: the warning shows and
  Cancel deletes nothing (green today, stays green).
- **AC5 (O1, SO4):** B's sign-out after losing the session, and while A's
  prompt is pending, leaves A's identity row; A's own sign-out clears it
  (guard). A `signedOut` edge with no observed user clears nothing (a
  documenting wiring test).
- **AC6 (SO2, SO3 units):** the command signs out without asking on zero,
  asks with the count on nonzero, asks with `null` when the count throws or
  there is no current user, deletes nothing on cancel, returns `superseded`
  when the user changes during the count or the dialog, and
  `alreadyRunning` for a second run; a failing sign-out sequence gives
  `failed`, is reported once and releases the lock; a throwing confirmation
  is reported once and gives `cancelled`.
- **AC7 (SO1 catalog lifetime):** with nothing else listening to the catalog
  controller, it stays alive through the whole sign-out sequence and is
  released after it.
- **AC8 (W3, whole app):** with a failing network and a persisted session,
  the song list's confirmed sign-out raises no unhandled error, ends
  `signedOut`, purges and clears the identity row.
- **AC9 (W3, command, whole app):** with a failing network and with a
  network that never answers, a run's outcome is `signedOut` with no
  unhandled error, and a second run is not held (`signedOut`, not
  `alreadyRunning`) while the first run's backend request is still open.
- **AC10 (W3 units):** `AppAuthController.signOut()` completes at the
  stream's null event while the revocation never answers; a connectivity
  failure of the revocation is not reported; any other failure is reported
  exactly once and never thrown; a revocation result landing after a new
  sign-in does not change the new user's state.
- **AC11:** `flutter test` (full suite) and `flutter analyze` are green after
  every task. No existing test changes except the two named in
  "Intentional behaviour changes" (items 1 and 4). The ownership suite
  (XU1–XU6) stays green.

## Review exit criterion

The adversarial Opus review blocks only on unconfirmed data loss, a
cross-user effect (one user's sign-out touching another user's data or
identity), or a view with no way out. Everything else goes to the deferred
entry.

## Documentation updates (in the implementation PR)

- ADR-020: amendment line on the explicit sign-out row: destructive after a
  warning whenever the signing-out user's user-wide count is nonzero or
  unknown; one command for every entry point; the sign-out completes at the
  local sign-out, and an offline backend revocation failure is not an error
  (W3).
- ADR-037: the current-user ownership amendment's explicit sign-out bullet
  also covers the identity clear (SO4).
- `docs/architecture/architecture.md`: the offline-authenticated paragraph
  states the sign-out warning rule and the identity-clear target.
- `docs/testing/testing-strategy.md`: the "Sign-out warning routing through
  `unifiedSyncOverviewProvider.hasUnsyncedWork`" line is replaced; the new
  suite is listed.
- `docs/deferred/2026-10-05-gate-cross-user-leaks.md`: O1 removed (title,
  status, section, trigger).
- `docs/specs/2026-10-06-cross-user-local-first-ownership.md`: the
  out-of-scope bullet on B's sign-out clearing A's identity points here.
- `LocalDataLifecycle.clearIdentity`'s doc comment: the explicit sign-out
  now passes the user.
- Roadmap: this PR between #86 and S0 PR 2 (at the design gate).
- No ADR-035 change; no new ADR (the decision narrows ADR-020's explicit
  sign-out row and ADR-037's ownership amendment).
