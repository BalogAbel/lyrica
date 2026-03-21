# ADR-008: Local-First Reads And Sync Queue

## Status

Accepted

## Context

Users may need to work for up to one week without connectivity.

## Decision

Default to local-first reads, local writes with sync metadata, and a durable sync queue. Handle conflicts manually in the MVP.

## Consequences

- Better resilience during poor connectivity
- Clearer sync state
- Conflict UX must be explicit and eventually improved beyond MVP
