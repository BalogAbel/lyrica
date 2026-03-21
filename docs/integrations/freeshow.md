# FreeShow Integration Boundary

## Status

FreeShow integration is important but intentionally not implemented in the MVP foundation.

## Current Boundary

Lyrica must preserve future compatibility by:

- Keeping ChordPro as the canonical editable source
- Modeling attachments separately from canonical song content
- Avoiding presentation-tool-specific fields in core song aggregates
- Preserving ordered session item structures that can later be exported
- Keeping FreeShow decisions in repository docs and ADRs rather than in tool-local prompts

## Planned Integration Surface

Potential future adapters may:

- Export session structures into FreeShow-friendly payloads
- Map songs, lyrics, metadata, and ordering into presentation documents
- Attach PDF or rendered outputs as fallbacks when needed

## Explicit Non-Goals Today

- No direct FreeShow API integration
- No presentation runtime control
- No FreeShow-specific schema in the MVP database

## Design Constraint

Future integration must sit behind a bounded adapter layer so the core domain remains vendor-neutral.
