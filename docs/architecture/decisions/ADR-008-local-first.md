# ADR-008: Local-First Reads And Sync Queue

## Status

Accepted

## Context

Users may need to work for up to one week without connectivity.

## Decision

Default to local-first reads, local writes with sync metadata, and a durable sync queue. Handle conflicts manually in the MVP.

The full online-preferred, offline-safe, local-first sync contract is defined in ADR-015. Key principles:

- UI reads always come from repository-owned local projections or merged local-first views.
- Online refresh improves freshness but never becomes required for core preparation work when usable local state exists.
- Local write intent is durable until backend acceptance, discard, conflict resolution, or explicit sign-out cleanup.
- Sync and refresh failures preserve the last usable local state.
- Backend authorization remains authoritative for every canonical write acceptance.

## Non-Goals

- No CRDT or automatic merge system — conflict resolution stays explicit and manual.
- No realtime event-driven UI read model — subscription events are invalidation triggers only.
- No Flutter-owned authorization decisions — backend policy enforcement via Supabase/Postgres is authoritative.
- No background sync while the app is suspended or terminated.
- No multi-organization retained cache — one active authenticated snapshot per user.

## Consequences

- Better resilience during poor connectivity.
- Clearer sync state with explicit conflict UX.
- Conflict UX must be explicit and eventually improved beyond MVP.
- The repository must keep read projection and write mutation state separate so failed writes remain inspectable without corrupting synchronized reads.
