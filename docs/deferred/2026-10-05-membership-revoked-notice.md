# No Signal While a Membership Revocation Is Pending

**Slice:** fix/offline-first-startup-gate (decided on 2026-10-05 as part of
product decision 1 in `docs/specs/2026-10-05-offline-first-startup-gate.md`)
**Related:**
- `docs/architecture/decisions/ADR-035-local-data-purge-contract.md` (D5: the
  two-confirmation purge gate, and the rejected read-only quarantine)
- `docs/specs/2026-10-05-offline-first-startup-gate.md` (SG2)

**Files:**
- `apps/lyron_app/lib/src/presentation/auth/membership_gate.dart`
- `apps/lyron_app/lib/src/application/storage/local_data_lifecycle.dart`
  (the `membershipRevokedAt` marker and the purge decision)

## Problem

Under SG2 of the offline-first startup gate spec, a member with a known
organization keeps the home route after a fresh `verifiedEmpty`, until the
ADR-035 D5 purge has actually run. That is intended. One case is left with
no signal at all:

- the member has pending local work;
- the second confirmation arrives;
- the member declines the purge in the confirmation dialog.

The marker stays set, the data stays visible, and every write the member
makes is rejected by RLS. The only trace is each rejected row showing
`authorizationDenied` in the sync popup. Nothing says that access to the
organization itself may be gone.

## Why it was deferred

ADR-035 rejected a **blocking** read-only quarantine with a banner, because a
false quarantine locks a member in good standing out of editing on exactly
the stage or rehearsal devices the purge contract protects. A purely
informational, non-blocking notice is a different trade-off. It still needs
its own product decision about copy, placement, when it clears, and whether
it may show after only one confirmation. That decision did not belong inside
a bug-fix slice.

## Options

### (a) Non-blocking notice while the marker is set and the purge was declined

- Show it on the song list and the plan list. It does not block reads or
  writes.
- Copy points to the cause ("your access to this organization may have
  ended") and to the action (sync the pending changes elsewhere, or let the
  purge run).
- It clears when a fresh `selected` resolution clears the marker, or when
  the purge runs.

### (b) Reword the `authorizationDenied` row copy only

- Name the likely cause on the rejected mutation rows instead of adding a
  new surface.
- Can be combined with S6 option (b) (the rejected-delete copy), which
  already reworks the same popup copy.

### (c) Nothing

- Acceptable while revocations stay rare and administrator-driven.

## Trigger

Pick this up when one of these happens:

- a field report of a member editing after revocation without understanding
  why the changes never sync;
- the next slice that reworks the sync popup copy (S6 option (b)).

## Requirements for the slice that picks this up

- Read-only and non-blocking. No path may lock reads or writes (ADR-035).
- It must not set or clear `membershipRevokedAt`. It only reads it.
- Red tests first. The notice shows only in the declined-purge state, and
  clears on a fresh `selected` resolution and on purge.
