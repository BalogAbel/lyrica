# Capability Persistence Residuals and Test-Strength Gaps

**Found:** 2026-10-12, in the final whole-branch review of S0 PR 2.
**Related:** `docs/specs/2026-10-05-offline-first-startup-gate.md`, ADR-040.

**Files:**
- `apps/lyron_app/lib/src/application/auth/capability_resolver.dart`
  (`writeCapabilityCodes`, ~172-177)
- `apps/lyron_app/lib/src/application/auth/auth_providers.dart`
  (`persistIdentity` ~285; D5 purge ~133-137)

**Status:** neither residual leaks data across users or organizations. Not
implemented.

## F3: first sign-in can lose the stored capability set

On the first sign-in the no-stored-set resolve can finish before
`persistIdentity` writes the (A, X) identity row. `writeCapabilityCodes` then
matches 0 rows and its return value is ignored, so nothing is stored and there
is no retry until the next invalidate (token refresh, about 1 hour).

Effect: an offline cold start inside that window has no stored set. Import is
hidden and `IfCapability` fails open. No leak.

Fix sketch: re-persist the resolved set when the identity row is written (a
`noteLastKnownIdentity` hook, version-gated), or retry the persist on the next
load.

## F4: D5 purge does not invalidate the resolver

The D5 purge avoids `notifyListeners` (`auth_providers.dart` ~133-137), so the
in-memory `_resolved[X]` keeps the pre-purge set for the same user until the
next auth notify or `RedeemStateSuccess`. Same user only, UX-only; the store is
not written back because the row is gone.

Fix sketch: drop the in-memory entry for the purged context without notifying,
or notify once the purge has settled.

## Test-strength residuals

Small gaps from the review ledger that remain open:

- Formatter boundary cases for the last-synced text (just under/over each unit
  threshold) are not pinned.
- The hollow-dot colour in the header control is asserted by presence, not by
  colour value.
- The cross-user (XU) mirror timing test does not pin the ordering of the
  mirror versus the context change.
- The `debugPrint` override in tests is not restored in a `finally`, so a
  failing test can leak the override into later tests.

## Trigger

The next change to capability resolution or the auth persistence path (F3, F4),
or a test-hardening pass over the sync surface.
