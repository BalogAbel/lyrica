# ADR-011: Repository-Owned Specs And Plans

## Status

Accepted

## Context

The bootstrap phase stored design and planning artifacts under a tool-named directory. That creates avoidable ambiguity about whether those documents are workflow hints or durable repository knowledge.

## Decision

Store repository-owned specs under `docs/specs/` and implementation plans under `docs/plans/`. Tooling may reference these documents, but the repository path remains vendor-neutral.

Each repository-owned spec and plan should also keep a short status note directly under the title so later slices can mark when an earlier artifact was implemented, partially superseded, fully superseded, or abandoned.

## Consequences

- Durable workflow knowledge is easier to discover without tool context
- Superpowers or other assistants can still participate without owning the canonical artifacts
- Existing tool-specific bootstrap artifacts become removable repository noise
