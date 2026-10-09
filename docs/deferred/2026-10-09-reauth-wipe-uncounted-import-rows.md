# Different-User Reauth Wipe Deletes Import Rows It Never Counted

**Found:** 2026-10-09, by the second adversarial review of
`fix/sign-out-pending-work-guard`
(`docs/specs/2026-10-07-sign-out-pending-work-guard.md`). Pre-existing on
`main`; not a sign-out path, so kept out of that PR by the user's decision.
**Related:** ADR-029 (D3, D4, D5, honest null count), ADR-035 D5.4/D5.5
(the membership purge already re-validates its count), SO7 of the sign-out
spec (the same class of problem on the sign-out path).

**Status:** open. Unconfirmed data loss, but it needs a ChordPro import that
is analysing or committing while a different user's session lands (a web
sign-in in another tab, or a magic link).

## Problem

The different-user resolution counts the prior user's pending work once and
asks with that count; the confirmed wipe then deletes everything the prior
user has at that moment, without counting again. A ChordPro import keeps
writing the prior user's `pendingCreate` rows behind the modal prompt (it
captured its context when it started), so more is deleted than the prompt
named. With a count of 0 there is no prompt at all, and rows written between
the count and the wipe are deleted silently.

## Event sequence

1. User A starts a ChordPro import; it reaches `ImportCommitting` and writes
   rows one by one with A's captured context
   (`apps/lyron_app/lib/src/presentation/song_library/chordpro_import_controller.dart`,
   `_commit`).
2. B's session lands. `resolveReauth` counts A's pending work as k
   (`apps/lyron_app/lib/src/application/auth/reauth_resolution.dart`, the
   count before `confirmDifferentUser`) and the prompt names k.
3. The import keeps writing behind the modal prompt.
4. The user confirms. `wipePriorAndProceed`
   (`apps/lyron_app/lib/src/application/auth_providers.dart`) deletes A's
   catalog and planning data with no recount: k + m rows are gone.

Probe (review, deleted afterwards): the prompt said 1; three imported songs
were written through `songLibraryService.createSong` with A's context; after
the confirmation A's pending count was 0 (four rows deleted).

## Fix sketch

Recount A's pending work immediately before the deletion and compare it with
the confirmed count, the pattern `LocalDataLifecycle.maybePurgeForMembershipRevocation`
already uses (`pendingWorkIncreased`, D5.5 rule 3). If it grew (or a zero
count became nonzero), do not wipe. Decide in the fix's spec between asking
again with the new count and cancelling to the prior user (no deletion; B
signs in again and is asked with the new count). Optionally also refuse the
wipe while an import is running (`isImportRunning`, SO7). Needs an ADR-029
amendment.

## Trigger

The next PR after `fix/sign-out-pending-work-guard`, before S0 PR 2
(roadmap, 2026-10-09).
