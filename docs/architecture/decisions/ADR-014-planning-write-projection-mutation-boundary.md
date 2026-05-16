# ADR-014 Planning Write Projection-Mutation Boundary

## Status

Accepted

## Context

The local-first planning read slice already established a normalized Drift-backed planning projection for the active authenticated user and organization boundary.

The next planning slices add local plan create/edit, session create/rename/delete/reorder, and song-backed session-item add/delete/reorder. That introduces two competing pressures:

- the UI must show the user's latest local planning intent immediately, even when offline
- backend authorization, canonical slug acceptance, and optimistic-concurrency checks must remain backend-owned

If the planning write slice reused projection rows as the only local write carrier, the repository would blur read state and write intent, make failed writes harder to inspect or retry, and make future planning sync evolution unnecessarily coupled to the current projection shape.

## Decision

Keep planning reads and planning writes as separate local data sets:

- the normalized Drift planning projection remains the repository-owned read model
- a separate persisted planning mutation store records local plan create/edit, session create/rename/delete/reorder, and song-backed session-item add/delete/reorder intent
- the planning repository/application layer exposes merged local-first planning views by overlaying pending mutations on top of the last synchronized projection
- failed planning mutations move out of the normal read overlay and remain visible through explicit mutation-status UI
- backend write RPCs remain the only authority for authorization, canonical slug acceptance, optimistic concurrency, duplicate-song enforcement, song-visibility checks, and empty-session delete enforcement

## Mutation Compaction And Dependency Rules

The persisted mutation model uses deterministic local compaction and parent-child dependency handling:

- Create-then-edit of the same local plan or session collapses into one pending create with the latest local fields.
- Create-then-delete of the same local plan or session annihilates the local mutation instead of emitting backend work for an entity the backend never accepted.
- Multiple local edits to the same synchronized plan or session collapse into one pending update against the same synchronized base version until sync succeeds or conflict resolution intervenes.
- Session mutations belonging to a locally created plan remain tied to that local plan identity and must not be synchronized ahead of the parent plan create.
- If a local plan create is discarded or rejected permanently, its dependent local session mutations are discarded with it rather than left orphaned.
- A session delete supersedes earlier pending session rename mutations for that same session.
- The sync layer emits backend operations in parent-before-child order for creates and child-before-parent order for destructive operations when both aggregates are involved.

## Consequences

- Local planning writes remain visible immediately and survive restart without mutating the synchronized projection in place.
- Explicit sign-out can safely clear both authenticated planning projection data and authenticated planning mutation data.
- Failed planning mutations remain inspectable and retryable without silently corrupting normal planning reads.
- Future planning sync work can evolve mutation compaction, retry, or conflict handling without redefining the repository-owned read projection.
- The repository keeps one clear boundary: Flutter owns local intent capture and merged local views, while Supabase/Postgres owns canonical write acceptance.
