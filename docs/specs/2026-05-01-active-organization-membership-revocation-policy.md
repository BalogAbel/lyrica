# Active Organization Membership Revocation Policy

> Status: Implemented

## Goal

Harden active-organization resolution so the app distinguishes verified empty membership from connectivity-related unknown state, blocks cached fallback after verified empty membership, and preserves offline-first behavior only for true connectivity failures.

## Problem

The current local-first song and planning flows scope cached data by `(userId, organizationId)` and rely on backend RLS for remote authorization, but they do not model membership-empty as a first-class resolution outcome.

Today:

- song-catalog organization resolution falls back to the latest cached organization on connectivity-classified failures
- planning active-context resolution can fall back to the latest cached organization when `allowCachedFallback` is enabled, but its current error handling is broader than connectivity-only
- explicit sign-out and session expiry already clear authenticated local song and planning data
- verified empty membership does not yet trigger the same explicit cleanup and fallback denial

This leaves a P1 lifecycle risk: a user removed from all organizations could continue to open stale org-scoped local data through a later cached fallback path even though backend membership has already been authoritatively revoked.

## Scope

- Add explicit active-organization resolution semantics shared by song and planning application flows.
- Distinguish these outcomes:
  - `selected(organizationId)`
  - `verifiedEmpty`
  - `unknownConnectivityFailure`
  - `unknownNonConnectivityFailure`
- Gate cached fallback strictly on `unknownConnectivityFailure`.
- Define local cleanup behavior for verified empty membership.
- Define pending mutation behavior for verified empty membership.
- Preserve the existing single-active-organization local-first model.

## Non-Goals

- No broad rewrite of auth or navigation architecture.
- No introduction of multi-organization local archives.
- No backend authorization move into Flutter.
- No new quarantine UI or hidden local archive system in this slice.
- No change to normal connectivity-failure offline behavior.

## Policy Decision

### Active organization resolution result

The app should stop using `String?` plus exception shape alone as the organization-resolution contract. Instead, one shared application-level result should describe both identity and confidence:

- `selected(organizationId)`: a verified active organization is available
- `verifiedEmpty`: backend lookup succeeded and returned no visible organization ids
- `unknownConnectivityFailure`: the app cannot verify membership because the lookup failed with a connectivity-classified error
- `unknownNonConnectivityFailure`: the lookup failed for a non-connectivity reason, including malformed responses or unexpected backend failures

`selectActiveOrganizationId()` remains responsible only for extracting the selected id from a verified response. The surrounding provider/application logic becomes responsible for classifying empty, connectivity, and malformed outcomes explicitly.

### Recommended local-data policy

Recommended policy: **delete, not quarantine**.

Rationale:

- the current architecture keeps one active authenticated song snapshot and one active authenticated planning projection per user, not a durable multi-organization archive
- sign-out and session-expiry already clear authenticated data, so verified empty membership can reuse that cleanup shape
- quarantine would require new hidden-read rules, new unblock semantics, and additional mutation-state handling with little value in the current single-active-org model

When active-organization resolution returns `verifiedEmpty`, the app should:

- clear the active catalog context
- clear the active planning context
- delete authenticated local song catalog data for that user
- delete authenticated local planning projection data for that user
- delete authenticated pending song mutations for that user
- delete authenticated pending planning mutations for that user

This is intentionally stronger than deleting only the latest cached organization because verified empty membership means the backend authoritatively reports no remaining visible organization memberships for the signed-in user.

### Song catalog behavior

- `selected(organizationId)`: keep current refresh behavior
- `verifiedEmpty`:
  - do not use cached fallback
  - clear catalog context
  - mark the catalog unavailable
  - perform authenticated local song cleanup for the user
- `unknownConnectivityFailure`:
  - preserve current cached fallback behavior
  - allow latest cached organization reuse only when a cached catalog exists
- `unknownNonConnectivityFailure`:
  - do not use cached fallback
  - if no verified in-memory context exists yet, remain unavailable
  - if a previously established in-memory catalog context exists, do not treat the error as session expiry or verified empty membership

### Planning behavior

- `selected(organizationId)`: keep current active-context and sync behavior
- `verifiedEmpty`:
  - do not use cached fallback
  - clear the active planning context immediately
  - trigger authenticated local planning cleanup for the user
  - leave planning reads unavailable until a later verified `selected(...)` result exists
- `unknownConnectivityFailure`:
  - preserve current offline-first behavior
  - allow cached fallback only during cold-start recovery when no active planning boundary is established yet
  - once a planning boundary exists in memory, keep that boundary through connectivity-only lookup failures
- `unknownNonConnectivityFailure`:
  - do not use cached fallback
  - preserve the existing in-memory planning boundary if one already exists
  - otherwise remain cleared/unavailable

### Pending mutation behavior after verified empty membership

Recommended policy: **drop pending authenticated mutations immediately**.

Rationale:

- replay is no longer authorized once membership is authoritatively empty
- preserving pending mutations would require a new revoked-membership review state and a later restoration policy
- the current product already treats sign-out/session-expiry cleanup as authenticated-data removal rather than durable local archival

Required behavior:

- delete pending song mutations for the affected user
- delete pending planning mutations for the affected user
- stop automatic retry/replay after cleanup
- do not surface revoked mutations as retryable conflicts

## Minimal implementation shape

Prefer minimal state-machine hardening:

1. Introduce one shared active-organization resolution result type and classifier.
2. Reuse that result in:
   - `SongCatalogController`
   - `ActivePlanningContextController`
   - the provider glue that currently calls `current_organization_ids`
3. Reuse existing store deletion capabilities where they already match the policy.
4. Add only the smallest new store helpers needed to remove authenticated song mutations per user if no equivalent helper exists yet.

Do not broaden the change into route rewrites, auth redesign, or new UI-state taxonomies unless failing tests prove they are required.

## Acceptance Criteria

- Verified empty membership never reuses a cached organization fallback.
- Verified empty membership removes authenticated local song and planning read data for the signed-in user.
- Verified empty membership removes authenticated pending song and planning mutations for the signed-in user.
- Connectivity-classified organization lookup failures still preserve offline-first cached fallback behavior.
- Non-connectivity organization lookup failures do not use cached fallback.
- Existing sign-out and session-expiry cleanup behavior remains unchanged.
- No unauthenticated, expired-session, or verified-empty path can read stale org-scoped data through the local-first song or planning flows.

## Verification Requirements

- Focused unit tests for organization-resolution classification.
- Controller tests for song verified-empty, connectivity-fallback, and non-connectivity no-fallback behavior.
- Controller tests for planning verified-empty, connectivity-fallback, and non-connectivity no-fallback behavior.
- Store tests for authenticated per-user cleanup semantics where new deletion helpers are introduced.
- Integration regression coverage proving offline-first behavior still works for connectivity failures while verified empty membership blocks local reuse.
