# Sync and Account Feedback (S6a)

> Status: design gate approved 2026-10-12 (FB1–FB12, copy table, red-test
> list); the UI-language addendum (FB13–FB15) approved the same day.
> Implemented on `fix/sync-and-account-feedback`.

**Branch:** `fix/sync-and-account-feedback` (from `main` at `c561d20`)
**Roadmap:** S6a in `docs/plans/2026-10-01-delivery-roadmap.md`, "Deferred
Triage (2026-10-12)". Copy and feedback only.
**Resolves:**
- `docs/deferred/2026-09-30-capability-gating-offline-cold-start.md`
  option (b);
- `docs/deferred/2026-10-12-sync-reason-chip-copy.md`;
- `docs/deferred/2026-10-05-membership-revoked-notice.md` option (b);
- `docs/deferred/2026-10-09-sign-out-guard-residuals.md` R8 and R15.
**Builds on:** ADR-035 (D5.6, `authorizationDenied` is terminal), ADR-036 (no
PII in telemetry), `docs/specs/2026-10-07-sign-out-pending-work-guard.md`
(SO1, SO3, SO7, SO8).
**Plan:** `docs/plans/2026-10-12-sync-and-account-feedback.md`

## Problem

Five places tell the user nothing, or something unreadable.

### P1. The sync popup shows identifiers

The reason chips of the unified sync popup are `pending_local`,
`sync_failed`, `conflict`, `dependency_blocked`, `remote_missing` and
`unknown`. `authorizationDenied` is already a phrase, but it says "Not
permitted" where the likely cause is that access ended.

### P2. A rejected delete shows the `remote_missing` chip

`_reasonFromPlanningEntry` (`unified_sync_overview.dart`) maps both
`PlanningMutationSyncStatus.failedRemoteDelete` and error code `remoteMissing`
to `UnifiedSyncReasonCode.remoteMissing`. The backend folds the capability
check into the lookup (`plan_not_found`), so the client cannot tell "removed
on the server" from "no longer allowed". The four copy constants written for
this (`planMutationPendingMessage`, `planConflictMessage`,
`planAuthorizationRevokedMessage`, `planRemoteMissingMessage`) have no reader
in `lib/` or `test/`, so the deferred doc's claim that the popup shows
`planRemoteMissingMessage` is stale: it shows the chip.

### P3. A refused or failed sign-out shows nothing

`signOutWithPendingWorkGuard` returns `SignOutOutcome.cancelled` for the SO7
import refusal, the same value as the user declining the discard dialog.
Both callers (`account_screen.dart`, `song_list_screen.dart`) call it
`unawaited` and ignore the outcome. A failed sequence and a superseded
sign-out also end silently. The song list's overflow menu has its own
`isImportRunning` early `return` in front of the flow, a third silent
refusal.

### P4. A failed Delete account is unhandled

`AccountScreen`'s delete `onTap` has `try { await controller.deleteAccount(); }
finally {...}` without a `catch`. An offline or RPC failure escapes as an
unhandled asynchronous error and the user sees no message.

### P5. Two confirmation dialogs are in Hungarian

`AppStrings.reauthDifferentUser*`, `reauthConfirmWipeAction`,
`reauthCancelAction` and `membershipRevocationPurge*` are Hungarian. The rest
of the UI is English, and the repository recorded no decision about the UI
language. The user decided on 2026-10-12: UI copy is English for now;
localization is a later product decision. These are the two dialogs that
confirm a deletion, so the translation must state exactly what the original
stated.

## Guarantees

STOP and report if a fix would need to break one:

- No change to the sign-out sequence, the purges, the D5 gate or the
  Delete-account semantics. Only feedback and copy change.
- No backend change, no migration, no change to stored data.
- No new guard, store or state machine.

## Decisions

### FB1. One generic remote-missing copy, no capability re-resolve

The chip for `remoteMissing` covers both causes in one honest phrase. The
client does not re-resolve the member's capabilities when it sees the
rejection: the backend deliberately answers `plan_not_found` for a missing
capability, a re-resolve is an extra network call and a new state, and its
answer could be a stale or offline guess. The four dead `plan*Message`
constants are deleted, not reworded (FB4).

### FB2. Reason chips are phrases

The seven reason chips of `_ReasonChip` (song rows and plan rows share it)
become short sentences, listed in the copy table. The domain reason names
(`pending_local` and so on) stay in `docs/domain/domain-vocabulary.md`, in
logic and in tests of the overview; only the displayed text changes.
`docs/product/sync-ux-contract.md` keeps its rule that the popup shows the
specific blocking reason and does not collapse reasons into one generic
conflict message: each reason has its own phrase.

### FB3. `authorizationDenied` names the likely cause

The chip says that access may have ended and keeps "retrying will not help"
(ADR-035 D5.6: the row is terminal, Keep mine is suppressed). This is the
option (b) of the membership-revoked notice: no new surface. The comment next
to the constant is updated: it no longer calls its siblings code-shaped.
Option (a), a non-blocking notice while the purge was declined, stays
trigger-gated (S9).

### FB4. Dead strings are deleted

Verified dead by grep over `lib/` and `test/`, and by `flutter analyze` after
deletion:

- `planMutationPendingMessage`, `planConflictMessage`,
  `planAuthorizationRevokedMessage`, `planRemoteMissingMessage`;
- `unifiedSyncFreshnessFresh`, `unifiedSyncFreshnessUnknown` (the header
  renders nothing for `fresh` and `unknown`);
- `unifiedSyncConnectivityOnline`, `unifiedSyncConnectivityOffline`,
  `unifiedSyncConnectivityUnknown`.

### FB5. The song side has nothing else to fix

The song rows of the popup use the same `_ReasonChip`. Their state chips
(`Created`, `Edited`, `Removed`, `... (conflict)`) are readable, and the song
dialogs (`songConflict*`, `songDeleteBlockedMessage`) are sentences. The
header tooltip word `syncing` and the popup's nested plan summaries
(`plan added`, `song removed`) are readable text, not identifiers, and are not
touched.

### FB6. The sign-out outcome splits; an error while asking is `failed`

`SignOutOutcome` gains `blockedByImport`, produced only by the presentation
flow (SO7). In `SignOutCommand`, an error thrown while asking the user to
confirm is reported once as before and now gives `failed` instead of
`cancelled`: the user never chose, and the feedback must say so. The sign-out
still does not happen; only the outcome value and its feedback change.

### FB7. One feedback point in the flow, per outcome

`signOutWithPendingWorkGuard` captures `ScaffoldMessenger.maybeOf(context)`
before its first `await` (SO1: the context can unmount while the dialog or
the sequence runs; the messenger belongs to the app and survives the screen)
and shows one snackbar for the outcomes below. The callers do not change.

| Outcome | Feedback | Why |
|---|---|---|
| `signedOut` | none | The screen changes. |
| `cancelled` | none | The user's own choice: the Cancel button or a barrier dismiss. Also the unmounted context: the screen that took the tap is gone, and whatever replaced it is the feedback. |
| `alreadyRunning` | none | A double tap. The first tap's own feedback (the dialog or the navigation) is on its way. |
| `blockedByImport` | message | Was `cancelled`, indistinguishable from the user's own Cancel. |
| `failed` | message | The sequence or the confirmation failed; reported once. |
| `superseded` | message | Another account signed in (or the current user was lost) while the sign-out ran, and it stopped. The screen does not necessarily change: the user stays on the same list with other data, and the sign-out they asked for did not happen. |

The `superseded` message states only what the command knows: the signed-in
account changed and this sign-out was stopped. It holds for both causes (a
different account, or no current user).

### FB8. The song list menu no longer returns silently

The `isImportRunning` early `return` in `song_list_screen.dart` is removed.
The flow performs the same check with the same predicate (SO7), so the
behavior is the same and the refusal now shows its message.

### FB9. A failed Delete account is caught, reported and shown

In `AccountScreen`: catch the error from `controller.deleteAccount()`; report
it once with `FlutterError.reportError` (library `AccountScreen`, a static
context; nothing of the user's data is added to the report, ADR-036) unless
`isConnectivityFailure(error)`
(an offline user is a condition, not a defect, as in
`AppAuthController._handleRevocationResult`); show one snackbar; reset
`_isDeleting` so the tile works again. The messenger is captured before the
first `await`.

The message states only what the client knows. The RPC response can be lost
after the server committed, so the copy says that the deletion could not be
confirmed. It makes no claim about the local data: a failed RPC does not by
itself emit `signedOut` (the edge every purge listens to), but a session lost
while the RPC runs is mapped to `signedOut` by `AppAuthController`, because
`deleteAccount` holds the signing-out flag for the whole call. That
pre-existing behavior is outside this slice and recorded as a residual, so
"nothing was removed from this device" would not be true in every case.

The user-switch refusal (SO8: another account signed in while the confirmation
was open) deletes nothing and now says so with its own snackbar, the same
wording pattern as FB7's `superseded`. The user's own Cancel or barrier
dismiss shows nothing.

### FB10. Pinned: a failed RPC does not change the auth state

A test pins that a failing `deleteAccount` repository call leaves
`AppAuthController` in `signedIn` for the same user, emits no `signedOut`
(the edge every purge listens to), and resets `_isSigningOut` (the next null
session is `sessionExpired`, not `signedOut`). It does not claim anything
about a session that is lost during the call (see the residual below).

### FB11. Guarantees

See "Guarantees". The sign-out sequence, the purges, the D5 gate and the
Delete-account semantics are untouched.

### FB12. Documents

- Resolve the four deferred documents as listed under "Resolves": remove
  `2026-10-12-sync-reason-chip-copy.md`; remove the capability-gating entry
  (option (a) shipped in S0, option (b) here, option (c) was rejected; its
  reason moves to `docs/architecture/architecture.md` next to the stored
  capability set, so it is not lost with the entry); mark option (b) of the
  membership-revoked notice done and keep option (a); remove R8 and R15 from
  the sign-out residuals. Historical specs and plans keep their references
  to the removed entry (the S5a precedent).
- Roadmap: the S6a row and the status note.
- `docs/product/sync-ux-contract.md`, `docs/architecture/architecture.md` and
  `docs/testing/testing-strategy.md` describe the chips as reason codes; they
  now say the chips are phrases for the domain reasons.
- `docs/product/vision.md`: the UI language decision (done in the first
  commit).

### FB13. `syncFailed` stays "Sync failed"

The proposal was "Sync failed — will retry automatically" if every path that
maps to `syncFailed` retries on its own. It does not hold:

- the automatic triggers (`OnlineTransitionDetector`, the foreground listener)
  call `syncNow()` directly and silently do nothing under `sessionExpired`
  (`unified_sync_status_popup.dart`, the comment on `_syncNow`): the user has
  to press Sync, which sends them to sign-in;
- a song row whose pending mutation carries `dependencyBlocked` also maps to
  `syncFailed` (`_reasonFromSongEntry`'s fallthrough). It is re-sent on every
  run and keeps failing until the referencing data changes.

So the chip makes no promise about retrying. The plan rows' `Try again`
button and `Sync now` carry the action.

### FB14. English UI copy; the two dialogs are translated

The decision of 2026-10-12 is recorded in `docs/product/vision.md`. The
Hungarian constants are translated to English in the copy table, stating the
same thing: what is deleted, whose it is, how many items, and what each button
does. Nothing is softened or strengthened. Two notes:

- "unsaved" in the original is the app's "unsynced": those changes are saved
  on the device and not yet on the server, and the app's English vocabulary
  for them is already "unsynced" (`unsyncedSignOut*`, the popup). The
  translation uses it.
- English needs a singular where Hungarian did not: one change is "1 unsynced
  change ... deletes it", the same pattern as `unsyncedSignOutPendingMessage`.

The song data (`asset_song_repository.dart` titles) and the accent map in
`song_catalog_store.dart` are data, not UI; they stay.

### FB15. A guard against Hungarian in `AppStrings`

A test reads `lib/src/shared/app_strings.dart` and fails on any of
`[áéíóöőúüűÁÉÍÓÖŐÚÜŰ]`. It covers `AppStrings` only, not song data. Existing
tests that matched the Hungarian text are rewritten.

## Copy table

### Sync popup reason chips (`_ReasonChip`; song rows and plan rows)

| Constant | Old | New |
|---|---|---|
| `unifiedSyncReasonPendingLocal` | `pending_local` | `Waiting to sync` |
| `unifiedSyncReasonSyncFailed` | `sync_failed` | `Sync failed` |
| `unifiedSyncReasonConflict` | `conflict` | `Conflicts with the server version` |
| `unifiedSyncReasonAuthorizationDenied` | `Not permitted — retrying will not help` | `Access may have ended — retrying will not help` |
| `unifiedSyncReasonDependencyBlocked` | `dependency_blocked` | `Blocked by a related item` |
| `unifiedSyncReasonRemoteMissing` | `remote_missing` | `Not found on the server, or access may have ended` |
| `unifiedSyncReasonUnknown` | `unknown` | `Unexpected sync error` |

### New snackbar strings

| Constant | Text | Shown |
|---|---|---|
| `signOutBlockedByImportMessage` | `Sign-out is unavailable while an import is running. Try again when it finishes.` | Sign out tapped while an import runs (Account tile, song list menu) |
| `signOutFailedMessage` | `Sign-out did not complete. Try again.` | The sequence failed, or the confirmation failed |
| `signOutSupersededMessage` | `The signed-in account changed, so this sign-out was stopped.` | The signed-in account changed while the sign-out ran |
| `deleteAccountFailedMessage` | `Could not confirm the account deletion. Check your connection and try again.` | The delete-account RPC failed |
| `deleteAccountSupersededMessage` | `The signed-in account changed, so the account deletion was stopped.` | Another account signed in while the delete confirmation was open (SO8); nothing was deleted |

### Translated dialogs (FB14)

| Constant | Old (Hungarian) | New | Shown |
|---|---|---|---|
| `reauthDifferentUserTitle` | `Másik fiók jelentkezett be.` | `A different account signed in.` | Different-user reauth dialog, title |
| `reauthDifferentUserPendingMessage` | `Másik fiók jelentkezett be. $email-nek $count mentetlen változtatása van. A folytatás törli ezeket.` | `A different account signed in. $email has $count unsynced changes. Continuing deletes them.` (one: `... has 1 unsynced change. Continuing deletes it.`) | same dialog, known count (`$email` is the prior user's) |
| `reauthDifferentUserUnknownPendingMessage` | `Másik fiók jelentkezett be. $email-nek mentetlen változtatásai vannak ezen az eszközön, de a pontos számuk nem állapítható meg. A folytatás törli ezeket.` | `A different account signed in. $email has unsynced changes on this device, but their exact number could not be determined. Continuing deletes them.` | same dialog, unknown count |
| `reauthConfirmWipeAction` | `Folytatás` | `Continue` | same dialog, confirm button |
| `reauthCancelAction` | `Mégse` | `Cancel` | same dialog, cancel button |
| `membershipRevocationPurgeTitle` | `A szervezeti tagságod megszűnt.` | `Your organization membership has ended.` | Membership-revocation purge dialog, title |
| `membershipRevocationPurgePendingMessage` | `A szervezeti tagságod megszűnt ezen az eszközön. A folytatás véglegesen törli az összes helyben tárolt dalt és tervet, beleértve $count mentetlen változtatást is.` | `Your organization membership has ended on this device. Continuing permanently deletes all locally stored songs and plans, including $count unsynced changes.` (one: `... including 1 unsynced change.`) | same dialog, known count |
| `membershipRevocationPurgeUnknownPendingMessage` | `A szervezeti tagságod megszűnt ezen az eszközön. A folytatás véglegesen törli az összes helyben tárolt dalt és tervet. A mentetlen változtatások pontos száma nem állapítható meg, de a folytatás ezeket is törli.` | `Your organization membership has ended on this device. Continuing permanently deletes all locally stored songs and plans. The exact number of unsynced changes could not be determined, but continuing deletes them too.` | same dialog, unknown count |
| `membershipRevocationPurgeConfirmAction` | `Törlés` | `Delete` | same dialog, confirm button |
| `membershipRevocationPurgeCancelAction` | `Mégse` | `Cancel` | same dialog, cancel button |

### Deleted (FB4)

`planMutationPendingMessage`, `planConflictMessage`,
`planAuthorizationRevokedMessage`, `planRemoteMissingMessage`,
`unifiedSyncFreshnessFresh`, `unifiedSyncFreshnessUnknown`,
`unifiedSyncConnectivityOnline`, `unifiedSyncConnectivityOffline`,
`unifiedSyncConnectivityUnknown`.

## Acceptance criteria (red tests first)

**Popup copy**

- CP1. Each of the seven `UnifiedSyncReasonCode` values renders the literal
  new chip text in the popup (literals, not constants, so a copy regression
  is visible).
- CP2. No chip text matches `^[a-z]+(_[a-z]+)+$`, and none is a bare
  `unknown` or `conflict`.
- CP3. A plan row built by `computeUnifiedSyncOverview` from a `planDelete`
  record with `failedRemoteDelete` shows the remote-missing phrase.
- CP4. At a 412 px wide viewport, a popup with the longest chips (conflict,
  access-ended and not-found rows, song and plan) raises no overflow. The
  test scales text by 0.55 to model real glyph widths (the test font is 1 em
  wide, about twice a real font). It is a width model, not a device
  measurement. The popup layout is unchanged: at 360 px the header buttons
  and the conflict rows' action buttons already fill the dialog and squeeze
  the title and chips; that pre-existing gap is recorded in
  `docs/deferred/2026-10-12-sync-popup-narrow-layout.md`.

**Sign-out feedback**

- SF1. An import running: outcome `blockedByImport`, the snackbar
  `signOutBlockedByImportMessage`, the sequence does not run (the three
  existing "cancels" cases are rewritten).
- SF2. The sequence throws: `failed` and `signOutFailedMessage`.
- SF3. `superseded`: `signOutSupersededMessage`.
- SF4. Cancel and a barrier dismiss show no snackbar; `signedOut` and
  `alreadyRunning` show none.
- SF5. The screen is replaced while the sequence runs, then it fails: the
  snackbar still appears (messenger captured before the first `await`).
- SF6. `SignOutCommand`: a throwing confirmation gives `failed`, is reported
  once, and nothing runs (the existing test is rewritten from `cancelled`).
- SF7. Song list: the menu is open, the import starts, Sign out is chosen:
  the message appears (it returned silently before).
- SF8. Account screen: Sign out while an import runs shows the message.

**Delete account**

- DA1. `deleteAccount()` throws: the snackbar `deleteAccountFailedMessage`,
  no unhandled error, `_isDeleting` is reset, and the tile can be tapped
  again.
- DA2. A non-connectivity error is reported once to `FlutterError.onError`
  (library `AccountScreen`); a `SocketException` is not reported, and the
  message still shows.
- DA3. `AppAuthController`: a failing `deleteAccount` repository call
  rethrows, leaves `signedIn` for the same user, emits no `signedOut`, and
  resets `_isSigningOut`.
- DA4. The user's own Cancel and a barrier dismiss of the delete confirmation
  show no snackbar, report nothing and do not call `deleteAccount`.
- DA5. Another account signing in while the confirmation is open: nothing is
  deleted and the snackbar `deleteAccountSupersededMessage` shows.

**UI language**

- L1. The two dialogs render the exact English strings of the table (known
  count, one, unknown count) and the English button labels.
- L2. A guard test: `app_strings.dart` contains none of
  `[áéíóöőúüűÁÉÍÓÖŐÚÜŰ]`.
- L3. The existing tests that matched the Hungarian text are rewritten; the
  full suite and `flutter analyze` are green.

## Visible effect

- The sync popup reads as sentences. A rejected delete says the item was not
  found on the server or access may have ended.
- A refused, superseded or failed sign-out, and a failed Delete account, show
  a message instead of nothing or an unhandled error.
- The two deletion-confirmation dialogs read in English, saying the same
  thing.

## Not changed

- The sign-out sequence, the purges, the D5 gate, the Delete-account RPC and
  its signed-out edge.
- Which rows are retried, the row actions (Keep mine, Discard mine, Try
  again), and the severity of any row.
- The header tooltip text and the popup's nested plan summaries.

## Accepted residuals

- The sync popup is not usable at a 360 px wide phone: pre-existing, layout
  work, outside copy-only S6a
  (`docs/deferred/2026-10-12-sync-popup-narrow-layout.md`).
- A session lost while the Delete-account RPC runs (a non-retryable token
  refresh failure, or a sign-out in another tab) is mapped to `signedOut`
  because `AppAuthController.deleteAccount` holds `_isSigningOut` for the
  whole call. The purges then run although the RPC may reject and the account
  survive. The user confirmed a dialog that says pending offline changes are
  removed, and the window is narrow; the failure message makes no claim about
  local data. Recorded in
  `docs/deferred/2026-10-12-delete-account-session-loss-purge.md`.
- A lost Delete-account response after the server committed: the user sees
  the "could not confirm" message; a retry then fails to authenticate and the
  session ends through the normal expiry path. The wording makes no false
  claim.
- A `superseded` message can also show when the current user was lost
  (signed out in another tab). It states only that the sign-out was stopped.
- A sign-out whose context unmounted before the dialog could open ends
  `cancelled`, silently (FB7).
