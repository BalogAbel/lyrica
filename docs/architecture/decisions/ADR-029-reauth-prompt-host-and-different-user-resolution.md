# ADR-029: Reauth Prompt Host and Different-User Resolution

- Status: Accepted
- Date: 2026-07-30
- Extends: [ADR-020-non-destructive-session-and-offline-authenticated-state.md](ADR-020-non-destructive-session-and-offline-authenticated-state.md)
- Related: [ADR-022-active-organization-resolver.md](ADR-022-active-organization-resolver.md)
- Spec: `docs/specs/2026-07-30-recovery-actions-that-outlive-their-widget.md`
- Plan: `docs/plans/2026-07-30-recovery-actions-that-outlive-their-widget.md`
- Closes: `docs/deferred/2026-06-28-reauth-different-user-live-wiring.md`

## Context

ADR-020 specified that a different-user sign-in while a prior user is
offline-authenticated must confirm before wiping the prior user's local data,
and built the pieces for it: `resolveReauth`
(`application/auth/reauth_resolution.dart`) is a pure, fully tested
coordinator, and `showReauthDifferentUserDialog`
(`presentation/auth/reauth_different_user_dialog.dart`) is a fully tested
dialog. Neither was called by anything in `lib/`. There was also nowhere for
either to run from: no `GlobalKey<NavigatorState>`, no `builder:` on
`MaterialApp.router`, no shell route wrapping the authenticated routes.

What the live `signedIn` edge actually did instead, before this slice, was
three independent listeners, none of which compared the new user to the
prior one:

1. `lastKnownIdentityPersistenceProvider` unconditionally overwrote the
   single `LastKnownIdentity` row with the new user, without ever reading
   the old value first;
2. the song catalog controller swapped to the new user's context;
3. the active planning context controller refreshed.

The practical consequence: signing in as a different user on a device
holding another user's unsynced work silently switched context and stranded
that work, invisibly, with the prior identity already gone by the time
anything could have noticed it was different.

## Decision

### D2 — A `ReauthPromptController` with a host widget, not a navigator key

Two ways to give the dialog somewhere to run were considered:

- **A `GlobalKey<NavigatorState>` on `MaterialApp.router`.** Less code — any
  caller could `showDialog` from anywhere without a widget in the tree.
  **Rejected**: it introduces global mutable navigation state, is harder to
  isolate in tests, and its `currentContext` can be null across lifecycle
  boundaries — the exact class of bug (`ref`/`context` outliving or not
  outliving the thing that created it) this slice exists to remove, not a
  different flavor of it.
- **Chosen: `ReauthPromptController` plus `ReauthPromptHost`.**
  `ReauthPromptController` (`application/auth/reauth_prompt_controller.dart`)
  is a `ChangeNotifier` holding at most one pending `ReauthPrompt { email,
  pendingCount }` and a `Completer<bool>`; `requestConfirmation` publishes
  the prompt and returns a future that resolves when `answer` is called.
  `ReauthPromptHost` (`presentation/auth/reauth_prompt_host.dart`) is mounted
  in `MaterialApp.router`'s `builder:`
  (`app/lyron_app.dart`), wrapping the routed child. It `ref.listen`s to the
  controller's `pending` field — never `ref.watch`, so a new prompt never
  rebuilds the routed child or anything below it — and imperatively shows
  `showReauthDifferentUserDialog`, feeding the boolean result back into
  `answer`. The decision logic (`resolveReauth`) stays testable with no UI
  at all; the host is testable as an ordinary widget; no route needed
  restructuring into a shell.

The controller is registered on `reauthPromptControllerProvider` as a plain
`ChangeNotifierProvider` — app-scoped, not `autoDispose` — because a pending
prompt has to survive whatever screen happens to be on top when the
different-user sign-in is detected, not get torn down along with it.

Only one prompt may be pending at a time. `resolveReauth` awaits a single
`confirmDifferentUser` call per `signedIn` transition before doing anything
else, so a second concurrent request would mean two different-user
resolutions racing — something this app never does by design.
`requestConfirmation` throws a `StateError` on a second call while one is
still pending, leaving the first prompt untouched, rather than silently
queueing or dropping a confirmation that guards data deletion.

A barrier dismissal of the dialog must reach `answer` as `false`, exactly
like `showReauthDifferentUserDialog` already returns on dismissal — the host
must not turn a missing answer into a confirm, since confirm is what
authorises deleting another user's local data.

### D3 — All four outcomes, wired to the live `signedIn` edge, with the ordering hazard closed structurally

`resolveReauth` is now called from inside `lastKnownIdentityPersistenceProvider`'s
`signedIn` case in `auth_providers.dart` — the same listener that used to
overwrite the identity unconditionally, now gated by the resolution instead
of replacing it. All four outcomes run:

| case | outcome |
|---|---|
| same user | `flushSameUser` (the existing identity-persist path) — proceed, nothing destroyed |
| different user, **zero** pending work | `wipePriorAndProceed`, no dialog |
| different user, **nonzero or unknown** pending work | `confirmDifferentUser`; on confirm, `wipePriorAndProceed`; on cancel, `cancelToPriorUser` |
| cancel | new session signed out, app stays offline-authenticated as the prior user, nothing deleted |

`wipePriorAndProceed` runs `SongCatalogStore.deleteCatalogsForUser` and
`PlanningLocalStore.deletePlanningDataForUser` for the **prior** user id,
clears `LastKnownIdentityStore`, then persists the new identity. Two hazards
were found and closed while wiring this in; both are the kind of bug that
comes back silently if fixed by ordering luck instead of structure.

**Hazard 1 — the identity-overwrite race.** Before this slice,
`lastKnownIdentityPersistenceProvider` overwrote the prior identity
unconditionally on the same edge the resolution now needs to read it from.
Had that write ever landed before the read, the different-user case would
have been undetectable — the "prior" identity would already be the new
user's. The fix is not "run the resolution's listener before the other
one": `persistIdentity` (the function that handles the `signedIn` case) is
the *sole* writer to `LastKnownIdentityStore` on this edge — the `signedOut`
case clears it, `sessionExpired` touches nothing, and there is no other
listener. That function now reads the prior identity as its first action,
before the membership-resolution `await` and before any write or clear that
follows. Because there is nothing else that could reach the store first, the
read happening first is guaranteed by control flow inside one function, not
by provider registration order. A regression test
(`identity_persistence_wiring_test.dart`, "hazard: the prior identity is
read before anything on this edge can overwrite it") asserts the store's
call log starts with the read and that the read value was actually used to
drive a real wipe, not just that a read happened.

**Hazard 2 — cancel converging on the wrong state.** The natural
implementation of "cancel signs the new session out" is to call the
existing `signOut()`. That would have been wrong: `signOut()` drives
`lastKnownIdentityPersistenceProvider`'s `signedOut` case, which **clears**
`LastKnownIdentityStore` — destroying the very identity cancel exists to
preserve. `AppAuthController.cancelReauthToPriorSession` (a new method, not
a reuse of `signOut`) signs out at the repository level directly and sets
`AppAuthState(status: sessionExpired, lastKnownSession: priorSession)`
itself. It also has to converge correctly regardless of whether its own
`_setState` call or the auth stream's own `null` event (a side effect
`_repository.signOut()` may itself trigger, at a time this class does not
control) lands first — both paths must land on the same target state, not
whichever happens to run last. `_pendingReauthCancelSession` records the
in-flight cancel so `_handleSessionUpdate` recognizes and preserves the
target state if the stream's `null` arrives while a cancel is pending,
instead of falling through to its ordinary null-session mapping. Pinned by
two tests in `app_auth_controller_test.dart`, one of which forces the stream
to also emit `null` as a side effect of the sign-out call, specifically so
the outcome cannot be "correct by luck about which one wins."

### D4 — The pending count is songs **and** plans

The confirmation prompt has to state everything a wipe would destroy. The
wipe deletes both subsystems, so a planning-only number would understate
it — worse than no number, because it is a specific number that is wrong.
`PendingLocalWorkCounter` (`application/auth/pending_local_work_counter.dart`)
sums `readPendingMutations(...).length` (planning) with `readPendingSongs(...)`
and `readConflictSongs(...)` (songs). It is a counting seam over injected
readers, not a new subsystem, and none of the three sources is caught
internally — a throw from any of them propagates rather than being folded
into an undercount of zero.

### D5 — ADR-020's non-destructive boundary is not relaxed

This is the distinction a future reader will most need, stated precisely
because it is easy to misremember as "this slice made a wipe safer" instead
of "this slice made an already-decided wipe finally get wired in":

Deleting another user's local data on an explicit, **confirmed**
different-user sign-in is **not** the destructive-on-uncertainty behaviour
ADR-020 forbids. The two are opposites, not variations on each other:

- an **unknown** or **connectivity-failed** session stays non-destructive —
  nothing is deleted, and the app stays offline-authenticated as the prior
  user (unchanged from ADR-020);
- **only** explicit sign-out, authoritative verified-empty-membership
  revocation, and now an explicitly **confirmed** different-user sign-in
  delete local data immediately;
- **cancel deletes nothing** and returns the app to being
  offline-authenticated as the prior user — the same shape of state ADR-020
  already treats as safe;
- an **unreadable pending count** is uncertainty about how much would be
  lost, not uncertainty about *whether* to ask — `resolveReauth` treats
  `null` the same as a nonzero count and still requires confirmation before
  anything is deleted (see "Honest pending count" below). Uncertainty is
  never allowed to authorise a wipe on its own; it is only ever allowed to
  force the question to be asked.

### Honest pending count: `null` stays `null` end to end

An earlier draft of the wiring substituted `1` for the pending count when it
could not be read, reasoning that forcing the confirm path was the important
part. That was wrong in a way worth recording, because it is the same
failure shape the design rejected once already in D4: a fabricated number is
not a safe approximation, it is a specific wrong answer, and the user is
about to authorise deleting another account's unsynced work based on it.
`ReauthPrompt.pendingCount` and `showReauthDifferentUserDialog`'s
`pendingCount` parameter are both `int?`. `resolveReauth` passes the count
it received straight through without substitution. When it is `null`, the
dialog shows an explicit "the exact number could not be determined" message
(`AppStrings.reauthDifferentUserUnknownPendingMessage`) instead of a count.
Zero still skips the prompt entirely (nothing to lose, nothing to confirm);
unknown never skips it; a number is only ever shown when one was actually
read.

## Testing

- `reauth_prompt_controller_test.dart` — publishing a prompt with a known or
  `null` pending count, `answer` completing the returned future with the
  supplied value, a second `requestConfirmation` while one is pending
  throwing and leaving the first prompt untouched, and listener notification
  on both request and answer.
- `reauth_prompt_host_test.dart` — the host renders its child unchanged when
  no prompt is pending, shows the dialog and feeds a confirm back, feeds a
  cancel back, and a barrier dismissal reaches the controller as `false`.
- `identity_persistence_wiring_test.dart` — all four outcomes on the live
  `signedIn` edge (same user; different user with zero pending; different
  user with pending, confirmed; cancel), plus the two hazard regression
  tests described under D3.
- `app_auth_controller_test.dart` — `cancelReauthToPriorSession` returns
  `sessionExpired` carrying the *prior* user's session (not `signedOut`, not
  the cancelled new user), and converges on that state even when the auth
  stream also emits `null` as a side effect of the sign-out call.
- `reauth_resolution_test.dart` — the pure coordinator's four outcomes,
  including that a `null` pending count is treated the same as a nonzero one
  (never as zero) and that `wipePriorAndProceed` is never called before
  `confirmDifferentUser` resolves `true`.
- `reauth_different_user_dialog_test.dart` — confirm, cancel, and barrier
  dismissal returning `false`; the known-count message; and the
  unknown-count message shown when `pendingCount` is `null`, including that
  cancel still returns `false` in the unknown case.
- `pending_local_work_counter_test.dart` — zero when all three sources are
  empty, the sum when each contributes, and that a throw from either the
  planning or the conflict-songs source propagates instead of being counted
  as zero.

## Consequences

- The authenticated shell now always hosts a `ReauthPromptHost`; any future
  confirmation dialog with the same "must survive whatever is on screen"
  requirement has a working pattern to copy instead of reinventing a
  navigator key.
- `lastKnownIdentityPersistenceProvider` is now doing more than persistence:
  it is also the sole place the different-user resolution runs. This was a
  deliberate reuse of "the one function that owns the write," not a
  layering violation — introducing a second listener on the same edge would
  have reintroduced exactly the ordering hazard this ADR closes.
- A second concurrent different-user prompt is a thrown `StateError`, not a
  queued or dropped request. If a future flow legitimately needs to queue
  reauth confirmations, that is a new decision, not an extension of this
  one.
- The pending count can still be `null` in production whenever the prior
  identity has no cached organization id or the count read throws; the UI
  and the resolution both have to keep handling that case honestly rather
  than it being a theoretical branch only tests exercise.
