# ADR-022: Active-Organization Resolver

- Status: Accepted
- Date: 2026-07-08
- Extends: [ADR-016-active-organization-resolution-semantics.md](ADR-016-active-organization-resolution-semantics.md)
- Related: [ADR-020-non-destructive-session-and-offline-authenticated-state.md](ADR-020-non-destructive-session-and-offline-authenticated-state.md), [ADR-021-provider-domain-split.md](ADR-021-provider-domain-split.md)
- Spec: `docs/specs/2026-07-08-arch5-active-organization-resolver.md`
- Plan: `docs/plans/2026-07-08-arch5-active-organization-resolver.md`
- Findings: `ARCH-5`

## Context

Active-organization resolution was spread across three provider seams and a
free function, with no single owner (ARCH-5). ADR-020 already touched the
identity-persistence seam of ARCH-5; this decision completes it.

## Decision

Introduce `ActiveOrganizationResolver`, one application-layer class that owns the
three resolution flavors — raw, connectivity-gated cached fallback (per ADR-016),
and organization-id projection — composed from the existing pure functions
(`resolveActiveOrganizationResolution`, `resolveMembershipWithCachedFallback`,
relocated to `active_organization_resolution.dart`). The provider seams
`activeOrganizationResolutionProvider` (raw), `membershipResolutionProvider`, and
`activeOrganizationReaderProvider` are preserved with identical types and override
points; the latter two delegate to the resolver.

Controllers keep their own per-outcome fallback policy (ADR-016 §Per-Outcome
Behavior): the `activePlanningContextController` cold-start `allowCachedFallback`
path and the song catalog controller handling are NOT folded in, because they
depend on controller-held in-memory boundary state. The resolver owns the
resolution + connectivity-fallback *mechanism*; controllers own per-outcome
*policy*.

## Reauth-Seam Intersection (noted, not closed)

The resolver is where `signedIn`-time organization resolution is composed — the
same seam the deferred different-user re-auth wiring must hook
(`docs/deferred/2026-06-28-reauth-different-user-live-wiring.md`). That wiring
remains deferred. Any future PR that wires it should hook the resolver /
`auth_providers.dart` composition point (the deferred doc, previously pointing at
the pre-split `providers.dart`, is updated to reflect this).

## Consequences

- One testable owner of active-organization resolution; providers are thin.
- ADR-016 semantics and all override seams are unchanged; no behavior change.
- Controller per-outcome policies remain where their state lives.
