# Membership Purge Has No Import Check

**Found:** 2026-10-11, by the final review of `fix/reauth-wipe-recount`.
**Related:** ADR-035 (D5.4, D5.5), ADR-029 amendment 2026-10-11,
`docs/specs/2026-10-11-reauth-wipe-recount.md` (RW3).

**Status:** pre-existing; unchanged by that branch. Not implemented.

## Problem

The membership-revocation purge
(`LocalDataLifecycle.maybePurgeForMembershipRevocation`, ADR-035 D5.4/D5.5)
has no import-running check, and its recount reads the planning and song
databases with the same gap RW3 closes for the reauth wipe: a ChordPro import
for that user can write rows between the recount and the deletion, which the
purge then deletes uncounted.

## Fix sketch

The same per-user `ImportRunTracker.isRunningFor(userId)` check before the
purge's recount and again synchronously before its deletion. It needs an
ADR-035 amendment, which is why it was not done in the reauth slice.

Use `isRunningFor(userId)`, not the user-agnostic `ImportRunTracker.isRunning`
getter. That getter is kept only for the controller's own tests, and a
user-agnostic check is exactly the defect the reauth slice's final review
found: the new user's own import declined their sign-in. Remove the getter
when this entry is picked up, unless a production reader needs it by then.

## Trigger

The next change to the membership purge or to ADR-035.

Roadmap (2026-10-12): scheduled in S3 PR 2 (it amends ADR-035 anyway; use `isRunningFor(userId)`).

Roadmap (2026-10-13): moved to **S5b**. S3's scope changed and it no longer amends ADR-035; S5b's O3 already touches the D5 purge.

S5b spec (2026-10-21): decided as MG11 of `docs/specs/2026-10-21-planning-mutation-gaps.md` (ADR-035 amendment); resolved by S5b PR 3.
