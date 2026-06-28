# Non-Destructive Session Expiry And Offline Relaunch

- Status: Proposed
- Date: 2026-06-28
- Scope: Mobile (`apps/lyron_app`) application + presentation + router layers — auth/session lifecycle, identity persistence, planning/catalog cleanup paths.
- Findings: `LF-T1` (keystone), `LF-T2` (partial), `ARCH-5` (targeted seam). Source: `docs/architecture/repository-review-2026-06-22.md`.

## Goal

Decouple **local data access** from **live auth-session validity** so the app delivers indefinite offline. A previously signed-in user keeps full read access to cached songs/plans and may keep editing (writes queue as mutations) when the auth session is no longer live — whether the session expired while running, or the app was relaunched offline with a dead token. Local data is destroyed only on **explicit sign-out** or **authoritative membership revocation**, never on connectivity-driven or unknown session loss.

## Current State (the bug)

Session loss is destructive across two distinct code paths.

### Path 1 — in-session expiry
The session stream emits `null` while signed in → `AppAuthStatus.sessionExpired` (`application/auth/app_auth_controller.dart:75-78`). This triggers:
- **Planning**: `handleSessionExpired` **deletes** local planning data (`application/planning/planning_sync_controller.dart:255-284`, `deletePlanningDataForUser`).
- **Catalog**: `handleSessionExpired` is already **non-destructive** — sets `CatalogSessionStatus.expired`, keeps cache (`application/song_library/song_catalog_controller.dart:322-329`). (Asymmetry.)
- **Router**: status `!= signedIn` falls through to `if (!isPublicRoute) return signIn.path` (`router/app_router.dart:85-86`) → user is bounced to the sign-in screen. Even the kept catalog cache is unreachable.

### Path 2 — cold-start offline relaunch (the worse case)
On launch `restoreSession()` returns a `null` session when the persisted token is dead and there is no network. Because this is **not** from the stream, `_stateForSession(null, fromStream: false)` maps it to `signedOut`, not `sessionExpired` (`app_auth_controller.dart:68-81`). `signedOut` drives the **explicit-sign-out** path → planning **and** catalog delete (`providers.dart:611-613,704-706`). Result: closing the app and reopening it offline days later wipes all local data — the exact "indefinite offline" scenario the feature must protect.

### Why both must change together
The two paths use different statuses (`sessionExpired` vs `signedOut`) and different cleanup wiring; each needs its own fix. Path 2 is the dominant real-world case (rehearsal/stage use with no network).

### Identity persistence gap (`ARCH-5`)
Active-organization/identity resolution is spread across `activeOrganizationResolutionProvider`, `membershipResolutionProvider`, the cached-org fallback, and per-controller `_lastAuthenticatedUserId` (`planning_sync_controller.dart:34`, `song_catalog_controller.dart:60`). `_lastAuthenticatedUserId` is **in-memory only** → lost on restart. The cached organization id is persisted per user (`readLatestCachedOrganizationId`, `offline/song_catalog/song_catalog_store.dart:389`, `offline/planning/planning_local_store.dart:510`), but on cold start there is no live session to tell the app **which** `userId` to load.

## Design

### Approach
Reuse `AppAuthStatus.sessionExpired` as a first-class **offline-authenticated / re-auth-required** state instead of introducing a parallel "local trust" layer. Both lifecycle paths converge on this state when a user was previously authenticated and the loss is not authoritative. This is the minimum-surface change and avoids a broad provider refactor; the targeted `ARCH-5` seam below is introduced only because LF-T1 genuinely needs a single source of truth for offline identity.

### Session/identity seam (targeted `ARCH-5`)
Introduce a small, testable identity unit that answers three questions used by the lifecycle and router:
1. **Who was the last authenticated user?** (`userId`, `email`)
2. **Is the live session valid right now?**
3. **What is the cold-start identity** when there is no live session?

Persist a durable `LastKnownIdentity { userId, email, organizationId, updatedAt }` record, written on every successful sign-in. **Persistence mechanism**: an own Drift-backed record (consistent with the existing offline stores), not a reliance on gotrue. The `LastKnownIdentity` record is the **primary** source of cold-start identity; a gotrue-persisted expired session exposing `user.id` is only an opportunistic optimization — its readability across an app restart is not guaranteed, so the design must not depend on it. This consolidates the scattered `_lastAuthenticatedUserId` / cached-org logic behind one seam without rewriting unrelated providers.

This record is cleared on explicit sign-out and on verified-empty membership revocation (the destructive paths), and rewritten on each successful sign-in.

### Auth controller mapping (`app_auth_controller.dart`)
- Cold start: `restoreSession()` returns `null` **and** a `LastKnownIdentity` exists → emit `sessionExpired` (offline-authenticated), carrying `lastKnownSession`. `null` **and** no identity → `signedOut` (unchanged).
- `AppAuthState` carries `lastKnownSession` (`userId`, `email`) in the `sessionExpired` state so downstream can render identity-scoped cached data.

### Controller cleanup changes
- `planning_sync_controller.handleSessionExpired`: **stop deleting**. Mirror the catalog: reset transient sync state, keep projection + pending mutations, mark access as offline-authenticated.
- `handleExplicitSignOut` (`signedOut`) and `handleVerifiedEmptyMembership`: remain **destructive** (unchanged). Authoritative revocation (`verifiedEmptyMembership`) only fires on a verified-empty membership over a live connection — not affected by offline/unknown loss.

### Write queue while offline-authenticated
Mutation creation is allowed (same as offline). With no live session the sync loop does not attempt to flush — queued mutations stay `pending` and flush **only after re-auth** (there is no background flush while offline-authenticated). The sync loop must treat "no live session" as a non-fatal, non-destructive condition (no cleanup, no failed/conflict downgrade).

### Re-auth resolution
- **Same `userId`** re-authenticates → existing `signedIn` path runs refresh + sync → the queued mutations flush.
- **Different `userId`** signs in while a prior user's local data **and** pending mutations exist → show a confirmation before any deletion: "Másik fiók jelentkezett be. {email}-nek {n} mentetlen változtatása van. A folytatás törli ezeket." Confirm → wipe prior user's data, proceed as the new user. Cancel → abort the new sign-in, stay offline-authenticated as the prior user.

### Router + UI
- `sessionExpired` no longer redirects to sign-in; for navigation it is treated like `signedIn` (the `MembershipGate` resolves via the cached organization id).
- A persistent re-auth banner is shown in the offline-authenticated state, with an action that opens the sign-in flow and, on same-user success, returns to the prior location.
- Reuses the existing offline-membership cached fallback (`docs/specs/2026-06-03-offline-membership-gate-cached-fallback.md`).

## Behaviour Matrix

| Trigger | Now | New |
| --- | --- | --- |
| In-session expiry (stream `null`, was signed in) | planning wiped + bounced to sign-in | data kept, offline-authenticated, read + write-queue, re-auth banner |
| Cold start, dead token, **known** user (identity present) | `signedOut` → wiped | offline-authenticated (as above) |
| Cold start, **no** known identity | sign-in | sign-in (unchanged) |
| Explicit sign-out | wiped | wiped (unchanged) |
| Verified-empty membership (online revocation) | wiped | wiped (unchanged) |
| Re-auth, **same** user | n/a | queue flush + sync |
| Re-auth, **different** user with pending data | n/a | confirm before wipe; cancel stays offline-authenticated |

## Non-Goals

- **No** server-side refresh-token TTL lengthening or rotation (`LF-T2` backend half) — this spec only decouples local access from live-session validity.
- **No** mutation-size budget, squash, or storage-eviction policy (`LF-T3`/`LF-T4`) — separate strategic slice.
- **No** broad `ARCH-5` rewrite — only the identity seam LF-T1 requires.
- **No** change to backend-enforced authorization (AGENTS.md rule 5). Authoritative revocation stays backend-driven and destructive.
- **No** attempt to enforce membership offline. While offline, cached data may outlive a server-side membership revocation; this is intended — authorization is backend-enforced and cannot be evaluated offline. Convergence happens on reconnect, when `verifiedEmptyMembership` fires and destructively cleans up. The offline window is accepted.
- **No** planning mutation reconciliation changes — covered by `docs/specs/2026-06-28-planning-mutation-sync-correctness.md`.

## Documentation Requirements

- New ADR in `docs/architecture/decisions/` recording the destructive ↔ non-destructive session policy and the offline-authenticated state (supersedes/extends `ADR-008-local-first.md` offline horizon).
- Update `docs/architecture/architecture.md` Offline Strategy with the offline-authenticated state and identity persistence.
- Update `docs/product/vision.md` if the offline guarantee wording changes.

## Testing

- Unit (`app_auth_controller`): cold start `null` + persisted identity → `sessionExpired` with `lastKnownSession`; `null` + no identity → `signedOut`; stream `null` while signed in → `sessionExpired`.
- Unit (`LastKnownIdentity` store): write-on-sign-in, read-on-cold-start, cleared on explicit sign-out / verified-empty.
- Unit (`planning_sync_controller`): `handleSessionExpired` preserves projection + pending mutations; `handleExplicitSignOut` and `handleVerifiedEmptyMembership` still delete.
- Unit (re-auth resolution): same-user → flush/sync; different-user with pending → confirmation gates deletion; cancel preserves prior data.
- Widget (router): `sessionExpired` stays in app (no sign-in redirect); re-auth banner renders; write actions queue.
- Integration: offline relaunch with dead token → cached songs/plans visible; offline edit → queued → re-auth same user → synced; offline edit → different user sign-in → confirmation before wipe.

## Acceptance Criteria

- Implementation follows `docs/plans/2026-06-28-non-destructive-session-and-offline-relaunch.md`.
- All behaviour-matrix rows are covered by tests and pass.
- Destructive paths (explicit sign-out, verified-empty revocation) remain destructive; no regression to backend authorization.
- ADR + architecture docs updated in the same change as the behavior.
