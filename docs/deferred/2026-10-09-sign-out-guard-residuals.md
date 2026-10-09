# Sign-Out Guard Residuals (R1–R13)

**Slice:** `fix/sign-out-pending-work-guard`
(`docs/specs/2026-10-07-sign-out-pending-work-guard.md`). Found by the
per-task reviews and the adversarial whole-diff review (2026-10-09).
**Related:** ADR-020 (amendment 2026-10-09), ADR-029, ADR-035, ADR-037
(current-user ownership), `docs/deferred/2026-10-05-gate-cross-user-leaks.md`
(O2, O3).

**Status:** none of these is reachable through an ordinary user action, and
none was judged to delete unsynced work without a confirmation or to touch
another user's data from a reachable sequence (the review exit criterion).
R1 and R2 are the closest: both need a second sign-in to land inside a
window of one local storage call or of an in-flight reauth cancel.

**Line references** are to the branch head when this entry was written.
Re-verify them before editing.

## R1 - a sign-in inside `AppAuthController.signOut()` before gotrue's signedOut event

- **Sequence:** the command's last check passes; `AppAuthController.signOut()`
  starts, gotrue drops A's session and awaits a local storage call (the code
  verifier) before it emits `signedOut`. If B's session lands in that await
  (a web sign-in in another tab, broadcast across tabs), the holders follow
  B; gotrue's `signedOut` then maps to `signedOut` (`_isSigningOut` is true),
  and the `signedOut` listeners purge B and SO4 clears B's identity row.
- **Why non-blocking:** the window is one local storage call (milliseconds)
  and needs a completed sign-in of another user in another tab inside it.
- **Fix sketch:** in `_processSessionUpdate`, map a null that arrives during a
  sign-out to `signedOut` only while the current user is still the user the
  sign-out started for; otherwise apply the D2 rule. Needs a fake gotrue
  ordering test.
- **Trigger:** the next change to `AppAuthController.signOut()` or a gotrue
  upgrade that changes `_signOut`'s ordering.

## R2 - a sign-out overlapping an in-flight reauth cancel

- **Sequence:** a sign-out starts while a different-user reauth cancel is
  still in flight (the cancel's pending record has a newer generation). The
  sign-out's null is consumed by the cancel branch; the app ends
  `sessionExpired(prior)`, and the sign-out completes only when its backend
  revocation settles (up to the 60 s response backstop), holding the command
  lock.
- **Why non-blocking:** a sign-out supersedes the reauth prompt, so a cancel
  cannot start after it; the reverse order needs a tap within the cancel's
  own sign-out call. Nothing is deleted that was not confirmed; the prior
  user's own offline view comes back.
- **Fix sketch:** complete the pending local sign-out in the cancel branch
  too, or refuse a sign-out while a cancel is pending.
- **Trigger:** the next change to the reauth cancel path.

## R3 - the sign-out identity clear can be late or skipped

- **Sequence:** the `signedOut` identity clear is queued on the resolution
  chain behind a still-running `signedIn` resolution (its membership RPC can
  take up to the 60 s backstop), and it is skipped if another auth
  notification invalidates the epoch before it runs. If the app is killed in
  that window, or the clear is skipped, the signing-out user's identity row
  outlives their purged data: the next cold start shows `sessionExpired` with
  nothing cached, or a later different-user sign-in asks about work that is
  already gone.
- **Why non-blocking:** pre-existing ordering; no data of anyone else is
  touched and nothing unsynced is lost (it was purged after confirmation).
- **Fix sketch:** run the sign-out clear ahead of a pending signedIn
  resolution (supersede it), keyed on the captured user.
- **Trigger:** the next change to `lastKnownIdentityPersistenceProvider`.

## R4 - the command can create the catalog controller

- **Sequence:** when nothing else listens to `songCatalogControllerProvider`,
  the command's subscription creates it; its build may start a refresh with
  the signing-out session (stale-guarded by the sign-out's generation bump).
  The catalog's own `signedOut` listener starts an idempotent second purge
  that can outlive the subscription.
- **Why non-blocking:** in the app the controller is alive anyway (the
  active planning context listens to it); writes are generation-checked; the
  second purge targets the same user.
- **Trigger:** the next change to the catalog controller's lifetime.

## R5 - the identity provider's ownership resets on a rebuild

`lastKnownIdentityPersistenceProvider`'s `CurrentUserOwnership` lives in the
provider closure. A rebuild while `signedOut` would lose the observed user and
skip the clear. Nothing invalidates the provider today. **Trigger:** any
change that invalidates it.

## R6 - a second `signOut()` after the local sign-out

A `signOut()` call after the local sign-out but before the revocation settles
does not join the first one and calls the repository again. gotrue then has
no session and sends no second `/logout`. **Trigger:** none.

## R7 - the pending-work count has no timeout

If the local database never answers, `SignOutCommand.run` waits on the count
and holds its lock; later taps return `alreadyRunning` silently. A database
that does not open breaks the whole app, so this is not a separate dead end
today. **Fix sketch:** a bounded count that becomes `null` (asks) on timeout.

## R8 - no feedback for refused sign-outs

`superseded`, `failed`, `alreadyRunning`, and a sign-out refused during an
import (`cancelled`, SO7) show nothing; on the Account screen the tap does
nothing visible. **Fix sketch:** a snackbar per outcome. **Trigger:** the next
UX pass on the account screen.

## R9 - the reauth host pops a stacked sign-out dialog

If the sign-out warning is open when a different-user reauth prompt arrives,
`ReauthPromptHost._closeOpenDialog` pops the top route: the sign-out warning
answers Cancel (the safe direction) and the reauth dialog can stay open until
answered. **Trigger:** the next change to `ReauthPromptHost`.

## R10 - import rows of a signed-out user

An import started inside the count's await (milliseconds) is not seen by SO7.
It cannot write before the sign-out ends (writing needs the user to pick
files first); its rows are then written with the signed-out user's captured
context and stay as orphans. Not a loss. **Fix sketch:** the import re-reads
the catalog context per row and stops when it changed.

## R11 - single-row writes that finish after their screen popped

The song editor's save and the planning reorder tails
(`plan_session_card.dart`, `plan_detail_screen.dart`) can finish a single row
after their screen was popped, inside milliseconds. Not the background-batch
class SO7 covers. **Trigger:** none unless reported.

## R12 - planning state after a superseded sign-out (unverified)

If the sequence stops after the planning purge started (SO6), planning is
left `accessStatus: signedOut` while the new user is signed in. It should
recover through the active-context path exactly as after a sign-out followed
by a sign-in; not verified by a test. **Fix sketch:** a wiring test.

## R13 - a duplicate-resolution answer dropped when the song list unmounts

`SongListScreen` returns on `!mounted` after the duplicate dialog, so an
answer given while the screen is being replaced is dropped and the import
stays in `ImportAwaitingDuplicateResolution` until the next import. Nothing
is written and, since Task 10c, nothing is blocked.

## Trigger

No fixed slice. Pick each up with its own trigger above, or earlier if
reported from the field.
