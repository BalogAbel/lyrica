# ADR-031: Catalog Refresh Coalescing Is Scoped to Session Identity

- Status: Accepted
- Date: 2026-08-08
- Spec: `docs/specs/2026-08-08-web-catalog-refresh-race.md`
- Relates to: ADR-016 (connectivity-gated cached membership fallback),
  ADR-022 (single owner of active-organization resolution)
- Scope: `SongCatalogController.refreshCatalog` and the trigger seam in
  `songCatalogControllerProvider`

## Context

`SongCatalogController.refreshCatalog` coalesces concurrent refresh requests so
that overlapping triggers — the auth listener, the periodic recovery timer, a
pull-to-refresh — do not stack up remote round trips. The original rule was
presence-based: if a refresh future was registered, the caller got that future
back.

That rule silently assumes every refresh is interchangeable. It is not. A
refresh reads the session at its first gate and bails immediately when there is
none. On Flutter web that produced a reproducible total failure: the catalog
provider was built while `AppAuthController` was still `initializing`, fired a
refresh with no session, and the auth stream's `signedIn` event landed in the
same turn — so the one trigger that could have loaded the catalog was handed the
already-doomed null-session future. `GET /rest/v1/songs` was never issued, and
the only recovery path (the 5-minute timer) was itself disarmed by a
construction-time lifecycle sample. The library screen showed "No cached song
catalog is available yet." indefinitely.

Native platforms won this race by accident — auth restore completes before the
catalog screen mounts — which is why the defect surfaced as "web-only" despite
being platform-independent logic.

## Decision

**Coalescing is scoped to session identity, never to mere presence.**

`refreshCatalog()` records the session identity (`AppAuthSession.userId`,
nullable) that the in-flight refresh was dispatched under.

- A caller whose identity **matches** the in-flight one receives that future.
  This is the unchanged path, and the sign-out overlap guarantees depend on it:
  a stale in-flight refresh must keep preventing overlapping refresh work after
  an explicit sign-out.
- A caller whose identity **differs** is never dropped. Exactly one follow-up
  refresh is queued behind the in-flight one, and the caller's future settles
  only after that follow-up. The single-slot queue is deliberate: a burst of
  differing-identity triggers shares one follow-up rather than fanning out into
  a refresh storm.
- The follow-up re-reads the session when it actually runs, not when it was
  queued. A follow-up that lands after a sign-out therefore sees no session and
  takes the ordinary null-session bail — it cannot resurrect authenticated
  state or cached catalog access.

**A refresh is never dispatched under an unknown auth state.** The catalog
provider's trigger is `handleAuthStateChanged` alone — invoked once at
construction and again from the auth listener — matching the shape the planning
providers already use. Refreshing during `initializing` has no information to
act on and can only publish a misleading `expired` session status.

**The recovery timer does not depend on a pre-settle lifecycle sample.**
`WidgetsBindingAppForegroundState` treats any lifecycle value observed before
the first `didChangeAppLifecycleState` callback as foreground. A genuine
background transition still stops the scheduler; only the unreliable
construction-time reading is ignored.

## Consequences

- The controller carries two extra fields: the in-flight refresh's session
  identity and a single-slot follow-up completer. This is the smallest state
  that makes the coalescing contract expressible.
- Callers can no longer assume "a refresh is in flight" means "your refresh will
  not run". Under a changed identity, one more remote round trip happens. That
  is the point.
- The periodic refresh is now a real recovery net on web rather than a net that
  silently fails to arm.

## Non-Goals

- This does not change what the catalog fetches, the offline snapshot format, or
  any authorization boundary.
- It does not generalise the coalescing rule to the planning controllers. They
  do not have the trigger shape that produced this bug; changing them was out of
  scope and would have been speculative.
- It does not add browser-level test coverage. The regressions here are
  reproducible as native unit tests, and the web e2e gap remains recorded in
  `docs/deferred/2026-06-29-web-offline-e2e.md`.
