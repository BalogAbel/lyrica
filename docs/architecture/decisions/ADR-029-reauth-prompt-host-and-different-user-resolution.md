# ADR-029: Reauth Prompt Host and Different-User Resolution

- Status: Accepted
- Date: 2026-07-30
- Extends: [ADR-020-non-destructive-session-and-offline-authenticated-state.md](ADR-020-non-destructive-session-and-offline-authenticated-state.md)
- Related: [ADR-022-active-organization-resolver.md](ADR-022-active-organization-resolver.md)
- Spec: `docs/specs/2026-07-30-recovery-actions-that-outlive-their-widget.md`
- Plan: `docs/plans/2026-07-30-recovery-actions-that-outlive-their-widget.md`
- Closes: `docs/deferred/2026-06-28-reauth-different-user-live-wiring.md`
- Amended: 2026-08-06 — a human review of PR #64 found three defects on the
  destructive wipe path this ADR governs, after the D1–D5 decisions below had
  already landed. See "PR #64 Review Remediation (2026-08-06)" below; closed
  by commits `92692de`/`c2b2835` (Finding 2), `93bbb04`/`0323e57` (Findings 1
  and 3), `2bd1a8c` (M4), `d1d6d5c` (M5).
- Amended: 2026-08-06 — a second human review found that Round 1's own
  Finding 1 fix had scoped its `try` too widely and mis-described one of its
  own failure branches. See "PR #64 Review Remediation, Round 2 (2026-08-06)"
  below; closed by commits `7e68c78`/`6734244` (Finding A).

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
  is a `ChangeNotifier` holding at most one pending `ReauthPrompt { requestId,
  email, pendingCount }` and a completer for a typed `ReauthPromptResult`;
  `requestConfirmation` publishes the prompt and returns a future that resolves
  as confirmed, cancelled, or superseded.
  `ReauthPromptHost` (`presentation/auth/reauth_prompt_host.dart`) is mounted
  in `MaterialApp.router`'s `builder:`
  (`app/lyron_app.dart`), wrapping the routed child. It listens to the
  controller's `pending` field — never `ref.watch`, so a new prompt never
  rebuilds the routed child or anything below it — and imperatively shows
  `showReauthDifferentUserDialog`, feeding the boolean result back into
  `answer`. The host is a `ConsumerStatefulWidget` that installs one Riverpod
  2.6 `listenManual(..., fireImmediately: true)` subscription. It captures the
  current prompt immediately, including one published before host attachment,
  and schedules presentation post-frame exactly once for that request id. The
  request id is carried back with the dialog result, so completion of an
  obsolete dialog cannot answer a newer prompt. The decision logic
  (`resolveReauth`) stays testable with no UI at all; the host is testable as
  an ordinary widget; no route needed restructuring into a shell.

The controller is registered on `reauthPromptControllerProvider` as a plain
`ChangeNotifierProvider` — app-scoped, not `autoDispose` — because a pending
prompt has to survive whatever screen happens to be on top when the
different-user sign-in is detected, not get torn down along with it.

Only one prompt may be pending at a time. Each `signedIn` notification claims
a new persistence generation and synchronously calls `supersedePending`
before its captured session is appended to the asynchronous work queue. This
clears any open prompt and completes its future with the typed superseded
result before the newer edge waits behind older work. The old resolution then
returns `ReauthSuperseded` and invokes neither the destructive callback nor the
cancel callback. `requestConfirmation` still rejects an uncoordinated second
call while a prompt is pending; normal auth-edge overlap is handled by
synchronously invalidating obsolete work before the newer edge is queued.

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
clears `LastKnownIdentityStore`, then persists the new identity. The scope is
user-wide, across every locally retained organization for that user. This is
an ordered application workflow, not a claim of one atomic transaction across
the separate local databases. Three hazards were found and closed while
wiring and hardening this path; all are the kind of bug that comes back
silently if fixed by ordering luck instead of structure.

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

**Hazard 3 — stale queued work acting after a newer auth edge.** Serializing
the asynchronous handlers does not make an older handler current. The auth
listener therefore advances a generation and supersedes the open prompt
synchronously for every `signedIn` notification, before queueing that edge.
Queued work carries the captured generation and session. Its currentness
predicate requires both the generation and the live signed-in session's exact
`userId` and `email` to match. The predicate is rechecked after awaited
identity, membership, count, prompt, deletion, and clear boundaries, and
immediately before song/planning deletion, backend sign-out, identity clear,
and every identity write. No `await` is inserted between a destructive
currentness check and obtaining its deletion future. If a last-moment check
prevents a callback from running, the callback reports that fact and
`resolveReauth` returns the typed `ReauthSuperseded` outcome rather than
claiming a wipe or cancellation that did not occur.

### D4 — The pending count is songs **and** plans

The confirmation prompt has to state everything a wipe would destroy. The
wipe deletes both subsystems, so a planning-only number would understate
it — worse than no number, because it is a specific number that is wrong.
`PendingLocalWorkCounter` (`application/auth/pending_local_work_counter.dart`)
sums two injected integer readers: actionable planning work and unsynced or
conflicted song work. Both readers are user-wide, filtering by prior `userId`
across every organization because the destructive cleanup is also user-wide.
Planning counts all actionable statuses (`pending`, `accepted`, failed
authorization, failed dependency, failed remote delete, and conflict); songs
count pending create/update/delete and conflict, but not synced rows. It is a
counting seam over injected readers, not a new subsystem, and a throw from
either source propagates rather than being folded into an undercount of zero.

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

## PR #64 Review Remediation (2026-08-06)

A human review of this PR, after D1–D5 above had already landed and this ADR's
status was `Accepted`, found three defects concentrated on exactly the
destructive wipe path D5 says is the one place this ADR deliberately crosses
ADR-020's non-destructive boundary. All three are decision-logic gaps in the
failure paths around that boundary, not in the boundary's placement itself.

### Finding 1 — `wipePriorAndProceed` had no failure path

Before this round, `wipePriorAndProceed`'s body — the song and planning
deletions, `identityStore.clear()`, and the terminal identity write — ran
with none of it inside a `try`. A throw from any step (a `SongCatalogStore`
or `PlanningLocalStore` deletion failing, or the identity-store clear/write
failing) rose straight through `resolveReauth` to the outer fire-and-forget
`catchError`, which only prints in `kDebugMode`. In a release build this
meant a **partial wipe**: the identity store never cleared, nothing shown to
the user, and — because the live Supabase session is owned outside this
listener — the device left presenting as the new user
(`AppAuthStatus.signedIn`) with the prior user's leftover local data still on
disk. That is precisely the stranding this ADR exists to prevent, reached
through a storage/deletion failure instead of a decision-logic bug.

`wipePriorAndProceedFor` (renamed by M4 below) now wraps its body in
`try`/`catch`. On any failure it falls back to exactly the state an explicit
cancel produces — `sessionExpired` carrying the **prior** user's session —
by calling the same `cancelToPriorUserFor` a real user cancel uses. Two other
responses were weighed and rejected:

- **Proceed as if the wipe had succeeded.** This is the stranding itself, not
  a mitigation of it — rejected outright.
- **Leave the resolution incomplete and retryable, without converging
  state.** Rejected as the *primary* response — not because retryability is
  unwanted, but because the live backend session is owned outside this
  listener and keeps presenting the device as the new user regardless of
  what this function does; doing nothing here does not stop that
  presentation, while falling back to cancel does.

Retryability still falls out of the chosen fallback as a property, not the
goal: the only write `wipePriorAndProceedFor` ever makes to
`LastKnownIdentityStore` is the `clear()` + `persistNewIdentity()` pair
immediately before a successful return, so whenever the `catch` is reached
before that pair completes, the store is left exactly as it was found —
still naming the prior user — and the next real `signedIn` edge for that
user retries the wipe cleanly. The failure itself is reported
unconditionally via `FlutterError.reportError`, not gated on `kDebugMode`
the way the generic backstop it used to fall through to was, since nothing
else is queued to retry it automatically.

**Residual window, closed by Finding A below.** The paragraph that originally
stood here described a sub-case where `identityStore.clear()` succeeds and
the very next step — `persistNewIdentity()`'s write of the new identity — is
what throws: the `catch` still ran and still called `cancelToPriorUserFor`,
converging `AppAuthController`'s in-memory state to `sessionExpired`/prior
session, without repairing `LastKnownIdentityStore` (left cleared). That
combination is exactly the misleading state a second human review round
flagged directly — asserting "offline-authenticated as the prior user" while
that user's local data had just been confirmed wiped is a false claim, not
merely an incomplete repair — and is now a compile-and-test-pinned separate
branch. See "PR #64 Review Remediation, Round 2 (2026-08-06)" below.

### Finding 2 — `cancelReauthToPriorSession` got stuck on a `signOut()` failure

If `AuthRepository.signOut()` threw inside `cancelReauthToPriorSession`, the
state-convergence block after that `await` never ran: the state stayed
`signedIn` as the would-be new user instead of converging to
`sessionExpired` carrying the prior user's session, and
`_pendingReauthCancelSession` was left set — "live" for a later,
**unrelated** `null` session event to misapply, exactly the record Hazard 2
above (D3) says must not be misapplied.

The backend `signOut()` call is now wrapped in its own `try`/`catch` inside
`cancelReauthToPriorSession`, so the convergence block below it always runs,
whether the call succeeded or failed. `_pendingReauthCancelSession` is
deliberately left lingering exactly as before — Hazard 2's late-emission
convergence design is unchanged — but is now harmless if a later event
consumes it: this method converges to the *same target state* on both the
success and failure paths, so a stray later event lands on a state a real
failure had already reached, never one it never reached. The `signOut()`
error itself is reported via `FlutterError.reportError` rather than
vanishing once `_isSigningOut` resets in `finally`. Local recovery is chosen
over depending on the backend call succeeding because ADR-020 never requires
a live backend confirmation to stay non-destructive — convergence has to
hold locally regardless of connectivity.

### Finding 3 — `resolveReauth`'s outcome was discarded

The call site in `auth_providers.dart` used to be a bare `await
resolveReauth(...)`, with the returned `Future<ReauthOutcome>` discarded
entirely. The typed-result machinery `reauth_resolution.dart`'s own doc
argues for at length — concrete callback types instead of generic ones,
specifically so a callback that cannot report whether it ran fails to
compile — had zero production effect once it reached this call site: only
tests ever read the return value.

The outcome is now captured and switched on exhaustively over the *sealed*
`ReauthOutcome`, so a future outcome variant fails this switch to compile
instead of silently doing nothing. What each case causes in production:

- `ReauthProceededSameUser`, `ReauthWipedPriorAndProceeded`,
  `ReauthCancelledKeptPriorUser` — each is a deliberate no-op at this
  switch. All three already applied their full effect *inside* the callback
  `resolveReauth` awaited before returning them (`persistNewIdentity` /
  `wipePriorAndProceedFor` / `cancelToPriorUserFor` respectively) — the
  identity store, and for a wipe or cancel `AppAuthController`'s status too,
  are already exactly where they need to be by the time the switch runs. The
  branch is the compile-checked acknowledgement of that, not the value being
  dropped on the floor.
- `ReauthSuperseded` — traces at `kDebugMode`, deliberately not at error
  severity. The ordinary path to this case is benign self-healing: a newer
  `signedIn` edge advanced the generation and superseded the open prompt
  before this resolution finished acting, and `scheduleIdentityResolution`
  already enqueues that newer edge's own resolution directly behind this one
  on the same serial chain (D3 above), so nothing here needs to retry it.
  The one path that reaches `ReauthSuperseded` *without* a newer edge queued
  behind it is Finding 1's wipe-failure fallback — and that call site has
  already recovered (via `cancelToPriorUserFor`) and already reported the
  failure unconditionally via `FlutterError.reportError`. This switch cannot
  distinguish the two cases, so reporting again here would either
  double-report a real failure or false-alarm on every ordinary
  overlapping-auth-edge race — which this architecture treats as normal
  (D3). A debug-only trace is still useful for local debugging, so it is
  logged rather than silently dropped.

### M4 — compiler-enforced non-null identity in the destructive closures

`countPriorPendingWork`, `wipePriorAndProceed`, and `cancelToPriorUser` each
used to unwrap `priorIdentity!` internally — safe only because of how
`resolveReauth` branches today (these three are only ever invoked on the
different-user path, which requires a non-null `priorUserId`). A future
contract change in `resolveReauth` routing one of them onto the same-user
path would have been a runtime crash on the destructive wipe path, not a
compile error. Renamed to `*For(LastKnownIdentity identity)`, with the
null-check moved to a single point at the `resolveReauth` call site (`final
identity = priorIdentity;` followed by an if/else that only builds the
non-null branch's closures over the promoted `identity`); the null branch
passes trivial stand-ins `resolveReauth` never actually calls on that
branch. No `priorIdentity!` remains in the file. Structural, not
behavioral — the existing 22-test `identity_persistence_wiring_test.dart`
suite stayed green unmodified.

### M5 — exhaustive switch inside `resolveReauth` itself

The different-user branch inside `resolveReauth` used to decide on
`ReauthPromptResult` with an if/else-if chain ending in a trailing `return
const ReauthSuperseded();` reachable only if a new enum value appeared —
true today, not enforced by the compiler the same way the file's own doc
already argues for the concrete callback types and Finding 3's outcome
switch above. Replaced with a `switch` expression exhaustive over the sealed
`ReauthPromptResult` enum, so a value added later fails this switch to
compile instead of silently falling through to the old catch-all.
Behaviorally identical for the three existing values; the guarantee gained
is compile-time exhaustiveness, which cannot be red/green tested without
adding a new enum value (out of scope here). Already fully pinned by the
existing `reauth_resolution_test.dart` suite, unmodified.

## PR #64 Review Remediation, Round 2 (2026-08-06)

A second human review, after the round above had already landed, found that
one of that round's own fixes carried a defect: `wipePriorAndProceedFor`'s
`try` was scoped too widely, and the comment describing its failure paths
was factually wrong on one branch.

### Finding A — the wipe's `try` was scoped too widely, and its comment
described a branch that could not happen the way it claimed

`wipePriorAndProceedFor`'s `try` used to wrap the destructive part (the song
and planning deletions, `identityStore.clear()`) **and** the terminal
`persistNewIdentity()` call in the same block. The comment justified this by
claiming "the only write to [the prior identity row] inside this function is
the clear+persist pair immediately before a successful return", so a `catch`
reached from anywhere in the `try` left the row "exactly as
wipePriorAndProceed found it". That is false on exactly the branch the
Round 1 "Residual window" note above already flagged as a gap: if the clear
succeeds and `persistNewIdentity()` then throws, the identity store is
**empty**, not as it was found. The consequences the old comment drew from
its own premise compounded the error: routing that branch through
`cancelToPriorUserFor` set `sessionExpired` carrying the **prior** user, but
by that point the prior user's local data had already been wiped — a cold
restart in that state reads a null identity and yields `signedOut`, never
the prior user, so the comment's claimed "next signedIn edge re-attempts the
wipe cleanly" had nothing left to detect. No data was lost on this branch
(the deletion had genuinely succeeded), but a load-bearing comment asserting
a false invariant is worse than no comment, and the state it produced
actively misrepresented what was on disk.

**Fix.** The `try` is now scoped to exactly the destructive part — the two
deletions and `identityStore.clear()` — matching what the comment always
claimed it covered. `persistNewIdentity()` runs after the `try`, in its own
`try`/`catch`, on the reasoning that a failure at that point is
categorically different from a failure inside the destructive part:

- **Destructive-part failure** (a deletion throws, or `identityStore.clear()`
  itself throws): the prior identity row is untouched (the only write this
  narrower `try` makes to the store is the `clear()` itself, so a `catch`
  reached before it completes leaves the row exactly as found). Falling back
  to `cancelToPriorUserFor` — `sessionExpired` carrying the prior user — is
  still truthful here: the prior user's data has not been confirmed wiped,
  so presenting the app as offline-authenticated as that user while
  reporting the failure is accurate, and the next real `signedIn` edge for
  that user retries the wipe cleanly. Unchanged from Round 1's Finding 1.
- **`persistNewIdentity()`-only failure** (deletions and clear all
  succeeded; only the new identity's write failed): the prior user's local
  data and identity row are genuinely gone. Falling back to
  `cancelToPriorUserFor` here would now be the misleading claim itself —
  there is no local data left to truthfully return to. Instead: report the
  failure unconditionally (same reasoning as Finding 1 — nothing else is
  queued to retry this automatically) and leave `AppAuthController`'s live
  state untouched. That state was already `signedIn` as the new user, set by
  the auth stream before this listener ever ran, and stays exactly that —
  the truthful state, since the new user genuinely is signed in.
  `LastKnownIdentityStore` is left empty: honest about there being no
  currently-persisted identity, rather than resurrecting a prior-user row
  with nothing behind it. This self-heals the same way the rest of this
  listener does: any later `signedIn` edge for the same new user (a token
  refresh, a foreground resume, a manual re-sign-in after a cold restart's
  forced `signedOut`) re-reads a null prior identity and retries
  `persistNewIdentity()` on its own same-user path.

Both branches were previously indistinguishable from inside the single wide
`try`; splitting the `try` is what makes the distinction possible at all, not
merely a refactor for clarity. `resolveReauth`'s `wipePriorAndProceed`
contract (`Future<bool> Function()`, `false` → `ReauthSuperseded`) already
had room for this: the persist-only failure returns `false` the same way the
destructive-part failure's `catch` always has, so the call site's exhaustive
switch (Finding 3, Round 1) needed no new case — only its `ReauthSuperseded`
comment updated to name two paths reaching it instead of one.

**Also fixed: the "always safe to await" claim.** The same catch's comment
justified awaiting `cancelToPriorUserFor` without a nested `try` solely by
`cancelReauthToPriorSession`'s own `signOut()` failure being handled (Round
1's Finding 2). That justification was incomplete: `_setState` inside
`cancelReauthToPriorSession` calls `notifyListeners()`, and a synchronous
listener exception there is a second, independent way the same await could
in principle fail. Verified against the vendored Flutter SDK
(`packages/flutter/lib/src/foundation/change_notifier.dart`,
`ChangeNotifier.notifyListeners`): each listener is already called inside
its own `try`/`catch`, with a caught exception reported via
`FlutterError.reportError` and iteration continuing to the remaining
listeners — the exception cannot propagate past `notifyListeners()` itself.
The comment now states both reasons the await is safe (the handled
`signOut()` failure, and Flutter's own per-listener exception handling)
instead of citing only the first and being silent about the second.

**Tests.** `identity_persistence_wiring_test.dart` gained "a wipe whose
deletions and clear succeed but the new-identity write throws leaves the
store empty and does NOT misrepresent the app as the prior user": watched
failing against the pre-fix code (`AppAuthStatus.sessionExpired` carrying
`user-1`, the misleading outcome this finding removes), passing after the
fix (`AppAuthStatus.signedIn` as `user-2`, the identity store left empty,
the failure still reported unconditionally). The existing 23-test suite
(22 plus this one) stayed green.

## Testing

- `reauth_prompt_controller_test.dart` — publishing a prompt with a known or
  `null` pending count, request-token-safe answers, synchronous supersession
  completing the old future with a typed non-confirming result, a second
  uncoordinated `requestConfirmation` while one is pending throwing and
  leaving the first prompt untouched, and listener notification on request,
  answer, and supersession.
- `reauth_prompt_host_test.dart` — the host renders its child unchanged when
  no prompt is pending, immediately captures a prompt published before host
  attachment and presents it post-frame exactly once across rebuilds, shows
  and answers current prompts by request id, ignores an obsolete dialog's
  answer, feeds a cancel back, and a barrier dismissal reaches the controller
  as a non-confirming answer.
- `identity_persistence_wiring_test.dart` — all four outcomes on the live
  `signedIn` edge (same user; different user with zero pending; different
  user with pending, confirmed; cancel), user-wide work in any retained
  organization preventing a silent wipe, plus generation/prompt supersession
  and side-effect-currentness regressions described under D3.
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
- `pending_local_work_counter_test.dart` and
  `drift_pending_local_work_reader_test.dart` — the sum of the two user-wide
  readers, failure propagation, every destructive-work status, and
  cross-organization rows for one user without crossing into another user's
  rows.

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
- Auth edges may overlap in time, but a newer edge synchronously supersedes
  the prior generation and prompt. The serial work queue remains an execution
  mechanism, not permission for stale work to act.
- The pending count can still be `null` in production when its user-wide read
  throws; the UI and the resolution both have to keep handling that case
  honestly rather than it being a theoretical branch only tests exercise.
