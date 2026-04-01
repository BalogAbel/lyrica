# ADR-012: Simplified Planning Hierarchy

## Status

Accepted

## Context

The repository previously carried a broader planning model that included an `event` layer between `plan` and `session`, but the first executable planning slice only needed a simpler structure that could be seeded, secured, and rendered end-to-end.

At the same time, the planning read path needed one clear authorization story: planning records belong to an organization, signed-in members of that organization may read the planning slice, and write behavior remains backend-owned RBAC instead of Flutter-owned filtering.

## Decision

Use `plan -> session -> session_items` as the active planning hierarchy.

For the current planning slice:

- `session` belongs directly to `plan`
- `session_item` belongs directly to `session`
- `song` remains a separate canonical aggregate referenced by `session_items`
- planning reads are organization-scoped for signed-in members of visible organizations
- planning writes remain capability-based backend RBAC decisions

The previous `event` layer is removed from the active repository-owned planning baseline. If a future product need reintroduces a calendar or occurrence concept, that will be treated as a new architectural/domain decision rather than an implicit return to the earlier model.

## Consequences

- The planning schema, seeds, repository, and route structure stay aligned to one active hierarchy.
- The read-side planning path stays simpler to reason about and verify than a mixed `plan -> event -> session` model.
- Authorization stays backend-enforced without requiring Flutter-side consistency logic between plan and session visibility.
- Future planning expansion remains possible, but it must happen through an explicit new decision rather than undocumented drift.
