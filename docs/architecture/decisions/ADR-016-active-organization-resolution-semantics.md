# ADR-016: Active Organization Resolution Semantics

## Status

Accepted

## Context

The local-first song and planning flows scope cached data by `(userId, organizationId)` and rely on backend RLS for remote authorization. Before this decision, active-organization resolution used `String?` plus exception shape alone as its contract, without distinguishing verified empty membership from connectivity failure.

This left a P1 lifecycle risk: a user removed from all organizations could continue to open stale org-scoped local data through a cached fallback path even though backend membership had already been authoritatively revoked.

The app needed one shared resolution result that describes both identity and confidence, and an explicit policy for what happens to local data when each outcome occurs.

## Decision

Introduce one shared active-organization resolution result type shared by song and planning application flows:

- `selected(organizationId)`: a verified active organization is available.
- `verifiedEmpty`: backend lookup succeeded and returned no visible organization ids.
- `unknownConnectivityFailure`: the app cannot verify membership because the lookup failed with a connectivity-classified error.
- `unknownNonConnectivityFailure`: the lookup failed for a non-connectivity reason, including malformed responses or unexpected backend failures.

Gate cached fallback strictly on `unknownConnectivityFailure`. Never use cached fallback after `verifiedEmpty` or `unknownNonConnectivityFailure`.

### Local Data Policy: Delete, Not Quarantine

When active-organization resolution returns `verifiedEmpty`, the app clears and deletes all authenticated local data for that user:

- clear the active catalog context
- clear the active planning context
- delete authenticated local song catalog data for that user
- delete authenticated local planning projection data for that user
- delete authenticated pending song mutations for that user
- delete authenticated pending planning mutations for that user

Rationale: the current architecture keeps one active authenticated snapshot per user, not a durable multi-organization archive. Sign-out and session-expiry already clear authenticated data, so verified empty membership reuses that cleanup shape. Quarantine would require new hidden-read rules, new unblock semantics, and additional mutation-state handling with no product value in the current single-active-org model.

### Pending Mutation Policy: Drop Immediately

When `verifiedEmpty` is confirmed, drop all pending authenticated mutations immediately:

- delete pending song mutations for the affected user
- delete pending planning mutations for the affected user
- stop automatic retry and replay after cleanup
- do not surface revoked mutations as retryable conflicts

Rationale: replay is no longer authorized once membership is authoritatively empty. Preserving mutations would require a new revoked-membership review state and a later restoration policy that the current product model does not support.

### Per-Outcome Behavior

**Song catalog:**

- `selected(organizationId)`: keep current refresh behavior.
- `verifiedEmpty`: do not use cached fallback; clear catalog context; mark catalog unavailable; delete authenticated local song data for the user.
- `unknownConnectivityFailure`: preserve current cached fallback; allow latest cached organization reuse only when a cached catalog exists.
- `unknownNonConnectivityFailure`: do not use cached fallback; if no verified in-memory context exists yet, remain unavailable; if a previously established in-memory catalog context exists, do not treat the error as session expiry or verified empty membership.

**Planning:**

- `selected(organizationId)`: keep current active-context and sync behavior.
- `verifiedEmpty`: do not use cached fallback; clear the active planning context immediately; delete authenticated local planning data for the user; leave planning reads unavailable until a later verified `selected(...)` result exists.
- `unknownConnectivityFailure`: preserve current offline-first behavior; allow cached fallback only during cold-start recovery when no active planning boundary is established yet; once a planning boundary exists in memory, keep it through connectivity-only lookup failures.
- `unknownNonConnectivityFailure`: do not use cached fallback; preserve the existing in-memory planning boundary if one already exists; otherwise remain cleared/unavailable.

## Consequences

- Verified empty membership can never reuse a cached organization fallback.
- Authenticated local song and planning read data is removed when membership is authoritatively revoked.
- Authenticated pending mutations are dropped when membership is authoritatively revoked.
- Connectivity-classified failures still preserve offline-first cached fallback behavior.
- Non-connectivity failures do not use cached fallback.
- Existing sign-out and session-expiry cleanup behavior remains unchanged.
- No unauthenticated, expired-session, or verified-empty path can read stale org-scoped data through the local-first song or planning flows.
