# ADR-010: FreeShow As Future Adapter Boundary

## Status

Accepted

## Context

FreeShow is strategically relevant, but immediate implementation would distort the MVP foundation.

## Decision

Do not implement FreeShow integration in the foundation. Preserve an adapter boundary so future export/integration work does not leak into core domain models.

## Consequences

- Core domain stays presentation-tool neutral
- Future integration remains feasible
- No early value from direct presentation tooling in the MVP
