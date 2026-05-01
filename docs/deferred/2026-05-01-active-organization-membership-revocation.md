# Active organization membership revocation and cached fallback policy

Status: Resolved

Related repository docs:

- Spec: `docs/specs/2026-05-01-active-organization-membership-revocation-policy.md`
- Plan: `docs/plans/2026-05-01-active-organization-membership-revocation-policy.md`

## Context

A targeted active-organization scoping audit found that local song and planning data are correctly scoped by `(userId, organizationId)`, and backend RLS remains authoritative for remote reads/writes.

However, there was a P1 lifecycle risk around membership revocation or verified empty membership responses.

Current behavior:
- Song and planning fallback can use cached local organization context when organization lookup fails.
- This is correct for connectivity failure / unknown membership state.
- But verified empty membership must be treated differently from connectivity failure.
- Planning fallback currently risks treating too broad a class of failures as fallback-eligible.
- Membership-empty or revoked paths do not currently have the same explicit cleanup semantics as sign-out/session-expiry.

## Risk

This slice has now been implemented in the repository through the active-organization resolution policy and verified-empty cleanup paths. Local cached song/planning data no longer reopens through verified-empty membership, and authenticated local cleanup now runs on that path.

This was not a proven cross-user or cross-organization leak, because local data is scoped and backend RLS protects remote access. It was a P1 local lifecycle/security-policy risk that has now been closed in code.

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

- The repository plan now recommends delete-not-quarantine semantics for verified empty membership.
- The repository plan now recommends dropping authenticated pending song/planning mutations immediately after verified empty membership.
- If implementation reveals a requirement to preserve revoked local drafts, treat that as a new slice and escalate rather than broadening this hardening change.

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
