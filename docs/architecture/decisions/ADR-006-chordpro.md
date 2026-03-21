# ADR-006: ChordPro As Canonical Song Format

## Status

Accepted

## Context

Songs need durable, editable, portable text storage with metadata support.

## Decision

Use ChordPro as the canonical editable song format. Store metadata in structured columns and map it during import/export.

## Consequences

- Canonical songs remain plain-text and portable
- Inline editing is sufficient for MVP
- PDF remains a fallback attachment only
