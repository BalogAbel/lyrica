# ADR-005: Drift

## Status

Accepted

## Context

The app must operate offline and maintain a durable local model plus synchronization metadata.

## Decision

Use Drift as the local persistence layer and sync queue foundation.

## Consequences

- Strong typed local persistence
- Good fit for local-first reads and queued writes
- Web storage implementation may need evolution while preserving contracts
