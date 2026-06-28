# ADR-020: Non-Destructive Session Expiry and the Offline-Authenticated State

- Status: Accepted
- Date: 2026-06-28
- Extends: [ADR-008-local-first.md](ADR-008-local-first.md), [ADR-015-online-preferred-local-first-sync.md](ADR-015-online-preferred-local-first-sync.md)
- Related: [ADR-016-active-organization-resolution-semantics.md](ADR-016-active-organization-resolution-semantics.md), [ADR-007-rbac-and-rls.md](ADR-007-rbac-and-rls.md)
- Spec: `docs/specs/2026-06-28-non-destructive-session-and-offline-relaunch.md`
- Plan: `docs/plans/2026-06-28-non-destructive-session-and-offline-relaunch.md`
- Findings: `LF-T1` (keystone), `LF-T2` (partial, client half only), `ARCH-5` (targeted identity seam)

## Context

ADR-008 commits the product to local-first operation with an offline horizon of at least one
week. Before this decision the client violated that horizon along two session-loss paths:

1. **In-session expiry** — the auth session stream emitting `null` while signed in mapped to
   `AppAuthStatus.sessionExpired`, which **deleted** local planning data and bounced the user to
   the sign-in screen. (The catalog cache was already non-destructive on expiry, so the two stores
   disagreed.)
2. **Cold-start offline relaunch** — on launch a `null` restored session (dead token, no network)
   mapped to `signedOut`, which drove the **explicit-sign-out** destructive cleanup of both planning
   and catalog data. Relaunching the app offline days later wiped everything — the exact scenario
   the offline horizon must protect, and the dominant real-world case (rehearsal/stage use with no
   network).

The root problem: **local data access was coupled to live auth-session validity.** Any session
loss, including a recoverable/offline one, was treated as authoritative and destructive.

## Decision

**Decouple local data access from live-session validity.** Treat `AppAuthStatus.sessionExpired` as
a first-class **offline-authenticated / re-auth-required** state: a previously authenticated user
keeps full read access to cached songs and plans and may keep editing (writes queue as pending
mutations) while the session is not live. Local data is destroyed **only** on explicit sign-out or
authoritative membership revocation — never on connectivity-driven or unknown session loss.

### Destructive ↔ non-destructive policy matrix

| Trigger | Behaviour |
| --- | --- |
| In-session expiry (stream `null` while signed in) | **Non-destructive.** Keep projection + cache + pending mutations; mark offline-authenticated; show re-auth banner. |
| Cold start, dead token, **known** identity present | **Non-destructive.** Same offline-authenticated state. |
| Cold start, **no** known identity | Sign-in (unchanged). |
| Explicit sign-out | **Destructive** (unchanged). |
| Verified-empty membership (online authoritative revocation) | **Destructive** (unchanged). |
| Re-auth, **same** user | Queue flush + sync. |
| Re-auth, **different** user with pending data | Confirm before wipe; cancel stays offline-authenticated as prior user. |

### Identity seam (targeted `ARCH-5`)

Cold start has no live session to say **which** user to load. Persist a durable
`LastKnownIdentity { userId, email, organizationId, updatedAt }` as its own Drift-backed record
(consistent with the existing offline stores), written on every successful sign-in and the
**primary** source of cold-start identity. A gotrue-persisted expired session exposing `user.id` is
only an opportunistic optimization; its readability across an app restart is not guaranteed, so the
design does not depend on it. This record is cleared on the destructive paths (explicit sign-out,
verified-empty revocation) and consolidates the previously scattered in-memory
`_lastAuthenticatedUserId` / cached-org logic behind one seam without a broad provider rewrite.

### Auth, router, and re-auth wiring

- `AppAuthController` cold-start: `restoreSession()` returning `null` **and** a `LastKnownIdentity`
  exists → `sessionExpired` carrying `lastKnownSession`; `null` and no identity → `signedOut`.
- `AppAuthState` carries `lastKnownSession` (`userId`, `email`) and includes it in `==`/`hashCode`.
- Planning `handleSessionExpired` stops deleting and mirrors the catalog: reset transient sync
  state, keep projection + pending mutations, mark access offline-authenticated.
- Router treats `sessionExpired` like `signedIn` for navigation gating (membership resolves via the
  cached organization id), while keeping the sign-in / magic-link routes reachable for re-auth.
- A persistent re-auth banner is shown in the offline-authenticated state; its action opens sign-in
  preserving the prior location via the `from` query param.
- Re-auth resolution: same user → flush + sync; different user with prior pending mutations →
  confirm before wiping the prior user's data; cancel keeps the prior user offline-authenticated.

## Consequences

- The offline horizon now holds across both in-session expiry and offline cold-start relaunch: the
  app stays usable and editable until the user explicitly signs out or the backend authoritatively
  revokes membership.
- While offline, cached data may outlive a server-side membership revocation. This is **intended**:
  authorization is backend-enforced ([ADR-007](ADR-007-rbac-and-rls.md)) and cannot be evaluated
  offline. Convergence happens on reconnect when `verifiedEmptyMembership` fires and destructively
  cleans up. The offline window is accepted.
- Backend-enforced authorization is unchanged (AGENTS.md rule 5). Authoritative revocation stays
  backend-driven and destructive; no authorization decision moves into Flutter.
- This is the client half of `LF-T1`. The backend half of `LF-T2` (refresh-token TTL/rotation) and
  the storage-eviction concerns (`LF-T3`/`LF-T4`) are explicit non-goals deferred to later slices.
- The different-user re-auth coordinator and its confirmation dialog are implemented and tested as a
  ready seam; the live provider→dialog integration is intentionally deferred and tracked in
  `docs/deferred/2026-06-28-reauth-different-user-live-wiring.md`.
