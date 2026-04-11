# ADR-014 Planning Write Projection-Mutation Boundary

## Status

Accepted

## Context

The local-first planning read slice already established a normalized Drift-backed planning projection for the active authenticated user and organization boundary.

The next planning slice adds local plan create/edit and session create/rename/delete. That introduces two competing pressures:

- the UI must show the user's latest local planning intent immediately, even when offline
- backend authorization, canonical slug acceptance, and optimistic-concurrency checks must remain backend-owned

If the planning write slice reused projection rows as the only local write carrier, the repository would blur read state and write intent, make failed writes harder to inspect or retry, and make future planning sync evolution unnecessarily coupled to the current projection shape.

## Decision

Keep planning reads and planning writes as separate local data sets:

- the normalized Drift planning projection remains the repository-owned read model
- a separate persisted planning mutation store records local plan create/edit and session create/rename/delete intent
- the planning repository/application layer exposes merged local-first planning views by overlaying pending mutations on top of the last synchronized projection
- failed planning mutations move out of the normal read overlay and remain visible through explicit mutation-status UI
- backend write RPCs remain the only authority for authorization, canonical slug acceptance, optimistic concurrency, and empty-session delete enforcement

## Consequences

- Local planning writes remain visible immediately and survive restart without mutating the synchronized projection in place.
- Explicit sign-out can safely clear both authenticated planning projection data and authenticated planning mutation data.
- Failed planning mutations remain inspectable and retryable without silently corrupting normal planning reads.
- Future planning sync work can evolve mutation compaction, retry, or conflict handling without redefining the repository-owned read projection.
- The repository keeps one clear boundary: Flutter owns local intent capture and merged local views, while Supabase/Postgres owns canonical write acceptance.
