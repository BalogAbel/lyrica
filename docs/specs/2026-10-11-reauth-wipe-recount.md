# Spec: The Different-User Wipe Deletes Only the Work It Counted

- Date: 2026-10-11
- Branch: `fix/reauth-wipe-recount`
- Closes: `docs/deferred/2026-10-09-reauth-wipe-uncounted-import-rows.md`
- Amends: ADR-029 (D3, D5, honest null count)
- Related: ADR-035 D5.4/D5.5 (the membership purge already re-validates its
  count), `docs/specs/2026-10-07-sign-out-pending-work-guard.md` (SO7, the
  same class of problem on the sign-out path),
  `docs/deferred/2026-10-09-sign-out-guard-residuals.md` (R10, R16, R17),
  `docs/deferred/2026-10-11-session-transition-coordinator.md`
- Plan: `docs/plans/2026-10-11-reauth-wipe-recount.md`

## Problem

ADR-029's different-user resolution counts the prior user's pending work
once, and the wipe then deletes everything that user has at deletion time:

- with a count of k the prompt names k; the user confirms; the wipe deletes
  k + m, where m is what was written behind the prompt;
- with a count of 0 there is no prompt; rows written between the count and
  the wipe are deleted without anyone being asked.

The writer is the ChordPro import. It captures the catalog context when the
run starts and writes `pendingCreate` rows one by one (SO7), so it keeps
writing the prior user's work behind the modal prompt, and between the
count and the wipe on the no-prompt path.

### Reproduced (phase 1)

Real `AppAuthController`, `LocalDataLifecycle`, Drift in-memory stores, the
real reauth providers and the real `ChordProImportController` over the real
import service; only the platform file picker answers from the test. Two
gates pin the interleaving: one pauses user A's song writes, one pauses the
count after its real Drift reads returned
(`apps/lyron_app/test/integration/cross_user_local_first_leak_test.dart`,
group "the different-user wipe deletes only counted work"):

- **(a)** A has one pending plan edit. A's import reaches its commit; B's
  session lands; the prompt names 1; the import writes 3 rows; the user
  confirms. All 4 are deleted (the 3 imported rows were never named).
- **(b)** A has no pending work. A's import reaches its commit; B's session
  lands; the count reads 0; the import writes 3 rows before the wipe; the
  wipe runs without a prompt and deletes all 3.

Both fail on `main` (`Expected: <3>, Actual: <0>`).

### Root cause

The wipe acts on a value read before an await (D5.5 rule 4): a prompt of
unbounded length, or the gap between the count and the deletion. Nothing
re-validates the count before deleting, unlike
`LocalDataLifecycle.maybePurgeForMembershipRevocation` (D5.5 rule 3).

A recount alone narrows the gap but does not close it. The counter reads the
planning and the song databases in parallel; an import row written after the
song read and before the planning read returns is not in the recount, and the
deletion that follows would remove it. The only writer that runs in that
window without the user's hand on its own screen is the import (SO7).

## Decisions

### RW1 — the wipe receives the count its decision was made on

`resolveReauth`'s `wipePriorAndProceed` callback takes the count the
decision used: `0` on the no-prompt path, and on the confirm path exactly the
count the prompt showed, `null` included (honest null, ADR-029). The callback
type changes from `Future<bool> Function()` to
`Future<bool> Function(int? countedPendingWork)`; nothing else in
`resolveReauth` changes. Passing it through the coordinator, rather than
capturing it on the side in the provider, keeps "the wipe acts on the number
the user saw" a compile-checked contract, in the spirit of M4/M5.

### RW2 — recount immediately before the deletion

`wipePriorAndProceedFor` recounts the prior user's user-wide pending work
(`pendingLocalWorkCounterProvider`, the same counter) after its first
currentness check and before the deletion, and proceeds only if:

| counted (decision) | recount | wipe |
|---|---|---|
| `0` (no prompt) | `0` | proceeds |
| `0` (no prompt) | `> 0` or unreadable | declined (RW4) |
| `k > 0` (confirmed) | `<= k` | proceeds |
| `k > 0` (confirmed) | `> k` or unreadable | declined (RW4) |
| `null` (confirmed unknown) | not recounted | proceeds |

This is D5.5 rule 3's comparison, applied here:

- an unreadable recount is uncertainty, and uncertainty never authorises a
  wipe (D5);
- a confirmed unknown is not compared numerically: the user already accepted
  an unknown amount, the maximally cautious case
  (`maybePurgeForMembershipRevocation` does the same).

Accepted, as in D5.5: the comparison is by count, not by row identity. If sync
removed counted rows while an import that has since ended added the same
number, the wipe deletes no more items than were confirmed, but not the same
items.

### RW3 — no wipe while an import is running

The wipe is declined while a ChordPro import run is in a running phase
(`isImportRunning`: picking, analysing, committing; SO7's definition, and
for the same reason `ImportAwaitingDuplicateResolution` does not count).
Checked twice:

1. before the recount, so no import is writing while the recount reads;
2. immediately before the deletion, synchronously, with no await between the
   check and obtaining the deletion futures (ADR-029 D3's rule for
   currentness checks).

An import that is not running when the recount starts cannot write before the
deletion starts: a new run needs the user to pick files first (R10's
argument). Check 2 also declines a run that started meanwhile; it cannot have
written yet, so that decline is conservative.

The import controller is a presentation-layer `StateNotifier`, and the reauth
resolution lives in the application layer, which does not import
presentation. A small application-layer seam carries the run state:

- `ImportRunTracker` (`application/song_library/import_run_tracker.dart`):
  `isRunning` plus a `report({required bool running})` method;
- `importRunTrackerProvider` (in `song_catalog_providers.dart`): app-scoped,
  not autoDispose;
- the controller reports `isImportRunning(value)` from its state setter,
  next to SO7's keep-alive link, so the tracker and the link always follow
  the same transitions.

SO7's sign-out refusal keeps reading the controller state; it is not moved to
the tracker in this PR.

### RW4 — a declined wipe cancels to the prior user

A declined wipe deletes nothing and runs the existing cancel path
(`cancelToPriorUserFor`, i.e. `AppAuthController.cancelReauthToPriorSession`):

- the new session is signed out at the repository level;
- the app returns to `sessionExpired` as the prior user;
- the identity row stays the prior user's.

The callback returns `false`, so `resolveReauth` reports `ReauthSuperseded`.
This understates what ran (a cancel) and never overstates it, which is the
callback contract's existing direction, and the same shape as ADR-029
Finding 1's fallback. The decline is logged in debug builds only: it is
expected behaviour, not an error.

The next sign-in of the new user runs the resolution again with a fresh
count; by then the import has ended, so the prompt names what is really at
stake.

If the generation is no longer current when the decline is decided, the
callback returns `false` without cancelling, because a newer edge owns the
outcome (D3, Hazard 3). `cancelToPriorUserFor` re-checks currentness itself.

**"Ask again" was rejected.** While an import runs, the count can grow with
every row, so a second prompt can be outdated by the time it is answered. To
avoid that, the resolution would have to wait for the import to end inside
the serial resolution chain. That wait is unbounded (the picking phase waits
for the operating-system picker) and blocks every later auth edge, including
the sign-out identity clear (R3). Asking again therefore cannot be shown to
terminate, while cancelling always does. The user can sign in again; a dead
end would only be a view without a way out, and here the re-auth banner of
`sessionExpired` is the way out.

## What the user sees

- **Prompt confirmed, then declined:** the dialog closes, and the app is the
  prior user's offline view with the re-auth banner (the same as Cancel).
- **No prompt, then declined:** the new sign-in does not take effect, and the
  app stays the prior user's offline view.

No message explains why (residual RW-R1 below; R8 is the same gap on the
sign-out side).

## Acceptance criteria

- **AC1 (a, RW2):** prompt names k; an import writes m more and ends; the
  user confirms. Nothing is deleted. The app is `sessionExpired` as A, and
  A's identity row and all k + m items remain.
- **AC2 (b, RW2):** the count reads 0; the import writes m rows before the
  wipe. No prompt and no deletion; `sessionExpired` as A; the m rows remain.
- **AC3 (RW3):** an import is still running when the user confirms (the
  recount is still `<= k`). Nothing is deleted; `sessionExpired` as A; the
  import's rows land in A's catalog.
- **AC4 (RW3):** the count is 0 while an import is running. Nothing is
  deleted; `sessionExpired` as A; the import's rows land in A's catalog.
- **AC5 (RW2, regression):** a confirmed wipe still runs when the recount is
  lower than or equal to the confirmed count; a zero-count wipe still runs
  silently when the recount is 0 (ADR-029 outcomes 2 and 3 unchanged).
- **AC6 (RW2):** an unreadable recount declines a wipe whose decision count
  was known; a confirmed unknown count is not recounted and the wipe runs.
- **AC7 (RW1):** `resolveReauth` passes 0 to the wipe on the no-prompt path,
  and exactly the prompt's count (including `null`) on confirm.
- **AC8 (RW3):** the tracker reports running for exactly the running phases,
  through every transition, including the throwing-listener path.

## Intentional test changes

- `test/application/auth/reauth_resolution_test.dart`: the ten
  `wipePriorAndProceed` callbacks gain an ignored parameter (`(_) async`).
  This is a signature change; their assertions and the behaviour they pin do
  not change.

No other existing test may change. A failing existing test outside this list
stops the work (see the plan).

## Non-goals

- No new purge, no new `PurgeReason`, no ADR-035 change. The wipe keeps
  `PurgeReason.differentUserSignIn` and its existing primitives.
- No restructuring of the sign-out or the reauth flows. One serialized
  transition chain is the subject of
  `docs/deferred/2026-10-11-session-transition-coordinator.md`.
- R10, R16 and R17 are unchanged: import rows written for a signed-out or
  wiped user stay orphans, and duplicate resolution still reads the live
  context.

## Residuals

- **RW-R1, no feedback for a declined wipe.** The prompt was confirmed but
  the app shows the prior user again, with no explanation. Fix sketch: a
  snackbar from the reauth host when a confirmed resolution ends in a
  decline. Trigger: the next UX pass on the reauth prompt, together with R8.
- **RW-R2, single-row writers.** The song editor's save and the planning
  reorder tails (R11) can finish one row inside the recount window. They are
  not background batches, and the recount still sees anything written before
  it.
