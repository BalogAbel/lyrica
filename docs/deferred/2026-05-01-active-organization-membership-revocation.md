# Active organization membership revocation and cached fallback policy

Status: Deferred

## Context

A targeted active-organization scoping audit found that local song and planning data are correctly scoped by `(userId, organizationId)`, and backend RLS remains authoritative for remote reads/writes.

However, there is a P1 lifecycle risk around membership revocation or verified empty membership responses.

Current behavior:
- Song and planning fallback can use cached local organization context when organization lookup fails.
- This is correct for connectivity failure / unknown membership state.
- But verified empty membership must be treated differently from connectivity failure.
- Planning fallback currently risks treating too broad a class of failures as fallback-eligible.
- Membership-empty or revoked paths do not currently have the same explicit cleanup semantics as sign-out/session-expiry.

## Risk

If a user is removed from all organizations, local cached song/planning data may remain available through cached fallback during later offline or lookup-failure states.

This is not a proven cross-user or cross-organization leak, because local data is scoped and backend RLS protects remote access. But it is a P1 local lifecycle/security-policy risk.

## Desired policy

Distinguish organization resolution outcomes explicitly:

- `selected(orgId)`:
  normal behavior

- `verifiedEmpty`:
  do not use cached fallback;
  clear active organization context;
  block access to previous org-scoped local data;
  define whether local song/planning data and pending mutations are deleted or quarantined

- `unknownConnectivityFailure`:
  preserve local cache;
  allow existing cached fallback behavior

- malformed / non-connectivity error:
  do not use cached fallback unless explicitly classified as connectivity

## Open questions

- Should verified-empty membership purge org-scoped local data immediately, or quarantine/block it?
- What should happen to pending local song/planning mutations after membership revocation?
- Should song and planning cleanup policies match session-expiry behavior?
- Should explicit active-organization selection be introduced before or alongside this fix?

## Suggested future plan

Use Superpowers planning before implementation.

The plan should cover:
- org resolution result semantics
- song catalog fallback gating
- planning context fallback gating
- verified-empty cleanup behavior
- pending mutation handling
- tests for verified-empty vs connectivity failure
- docs updates

## Required tests

- verified empty membership blocks cached fallback
- connectivity failure still allows cached fallback
- non-connectivity org lookup failure does not fallback
- song cache behavior after verified-empty membership
- planning projection behavior after verified-empty membership
- pending local mutation behavior after verified-empty membership
- no unauthenticated or revoked local read path can access stale org data

## Escalation

This should not be implemented by a mini worker without stronger review.

Escalate for:
- auth/session lifecycle
- active organization semantics
- local data deletion/quarantine policy
- pending mutation replay behavior
