# ADR-040: Offline-First Startup Gate

**Status:** Accepted (2026-10-05). PR 1 implements SG1–SG5 and SG8; PR 2
implements SG6–SG7.
**Supersedes in part:** ADR-016 — its cached fallback is no longer the
membership gate's offline path.
**Amends:** ADR-037 — its invariant now covers everything the startup path
shows, not only the read contexts.
**Context spec:** `docs/specs/2026-10-05-offline-first-startup-gate.md`

## Context

After PR #79 the catalog and planning contexts were local-first, but the
membership gate in front of them was not. It started as a connectivity
failure and opened only after the `current_organization_ids` RPC answered.
With an expired access token every RPC first waits for gotrue's refresh
retry loop, measured at 10.0–12.4 s offline (up to the 120 s token backstop
on a connection that never answers). A cold start straight into
`sessionExpired` never opened the gate at all, and a single fresh
`verifiedEmpty` hid data that ADR-035 D5 deliberately keeps readable.

## Decision

1. **The gate decides from local state.** `decideMembershipGate` is a pure
   function of the current user's last known organization, the live
   resolution, the pending invite and the first-run timer. A known
   organization opens the gate with no network answer. The router redirect
   evaluates the same decision (`allowsAuthenticatedRoutes`).
2. **`verifiedEmpty` waits for the D5 purge.** With a known organization it
   changes nothing; the purge clears the identity, and a purge handler on
   `VerifiedEmptyMembershipCleanupCoordinator` records `verifiedEmpty` for
   the purged user. A pending invite still shows the redeem screen at once.
3. **Live results are scoped by user and by resolution.** A failure never
   replaces a `selected` result for the same user; a result for a user who
   is no longer current is dropped; an explicit sign-out forgets it. A live
   result is applied only if it belongs to the current user's most recently
   started resolution (a per-resolution token: a reset and a change of the
   current user invalidate earlier ones, and the D5 purge handler is
   authoritative for the current user). A result is also applied for the
   user captured before the network await, not the one current after it.
   A direct user switch (`signedIn` to `signedIn` with a different user)
   starts a fresh resolution.
4. **First run without a known organization** shows a loading state, and
   the connectivity message with Retry after 15 s. In `sessionExpired`,
   Retry resolves from the local cache only (no anonymous RPC), and the
   failure screens offer sign-in using the re-auth banner's route.
5. **Auth-stream errors are handled.** Connectivity errors are dropped;
   anything else is reported once as a handled error.
6. **Planning listeners notify on a microtask.** Opening the gate in the
   first frames exposed notifications fired during a widget build; the two
   planning `ref.listen` callbacks now defer their controller calls.
7. **(PR 2)** The last known capabilities are stored on the
   `LastKnownIdentity` row, and the sync surface shows when songs and plans
   last synced.

## Consequences

- A genuinely revoked member keeps seeing cached data until the D5 purge
  runs. Their writes are rejected by RLS. This is the cost ADR-035 already
  accepted; the declined-purge notice is deferred
  (`docs/deferred/2026-10-05-membership-revoked-notice.md`).
- Sync and other network calls still wait for gotrue's refresh loop
  offline; only display stopped waiting
  (`docs/deferred/2026-10-05-offline-token-refresh-churn.md`).
- Every offline startup path keeps at least one test with the real auth
  client (`docs/testing/testing-strategy.md`).
- Known residual cases are recorded in
  `docs/deferred/2026-10-05-gate-cross-user-leaks.md`. F6 and F7 are
  pre-existing cross-user leaks (not introduced by the gate) that the next
  fix PR closes; C4, F5, N1 and N2 are low-severity gate cases that show
  only the user's own state.
