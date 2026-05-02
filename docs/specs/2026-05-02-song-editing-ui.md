# Song Editing UI Spec

> Status: Draft

## Goal

Define the visual and workflow direction for a ChordPro-first song editing surface so the canonical source, derived metadata, and previewed reader behavior feel like one coherent workspace.

This slice is prototype-first. The immediate deliverable is a repository-owned mock in `docs/prototypes/` that matches the visual vocabulary of the existing song reader, song list, and planning workspace prototypes before any implementation plan is written.

## Problem

The repository already has clear durable rules for song data:

- ChordPro source is canonical
- derived song metadata can be indexed in the database for fast lookup
- the reader already has runtime transpose and capo behavior
- song CRUD already defines backend-enforced authorization, sync metadata, and local-first write rules

What is missing is a coherent editing surface that makes those rules understandable during day-to-day use. Today the user would have to infer too much from separate surfaces:

- title and metadata are not clearly shown as derived from the ChordPro source
- song-owned transpose/capo settings are not clearly distinguished from reader runtime behavior
- the relationship between stored settings and live preview is not explicit
- the design language is not yet aligned with the existing prototype set under `docs/prototypes/`

## Scope

- Define the song editing workspace layout and hierarchy.
- Support canonical ChordPro source editing.
- Show derived title and metadata summary fields that refresh from the source.
- Support song-owned transpose and capo settings as part of the stored song model.
- Show a live preview or feedback panel that reflects the resulting reader state.
- Add a repository-owned mock under `docs/prototypes/` that follows the existing prototype conventions.
- Preserve the backend-enforced authorization boundary for any future implementation.

## Non-Goals

- No backend schema or policy changes in this slice.
- No new authorization model.
- No real-time collaborative editing.
- No rich visual chord editor.
- No redesign of the song reader beyond the preview needed to evaluate editing changes.
- No implementation plan until the mock and spec are reviewed.

## Product Direction

The editor should feel like a workspace, not a stack of unrelated form controls.

The user should be able to answer these questions immediately:

1. What song am I editing?
2. What does the ChordPro source currently resolve to?
3. Which values are stored settings versus reader runtime behavior?
4. What will the reader look like after I save?

The editor should use the same prototype language as the rest of the repo:

- top bar with reviewer controls
- surface-based layout
- a state switcher for important UI scenarios
- calm, operational presentation instead of decorative chrome

## Editing Model

### Canonical Song Data

The editing surface must treat the ChordPro source as the primary editable source of truth.

Required source-aware surfaces:

- ChordPro source editor
- derived song title
- derived song metadata summary
- derived key, tempo, and tag display where available
- other existing structured values that can be regenerated from the source

The derived summary fields are read-only in this slice. If the user changes title, artist, tags, or similar values, that edit happens by changing the corresponding ChordPro source directives or metadata blocks.

### Song-Owned Transpose And Capo

This slice treats transpose and capo as song-owned settings that belong to the stored song record, while the reader can still apply its own runtime adjustments later.

The UI must make that separation explicit:

- stored song-level transpose and capo are editable in the song editor
- reader runtime transpose and capo remain a separate concern
- live preview shows the effective result of the stored song settings
- the editor must not present runtime controls as if they were persisted song settings

### Source Relationship

The editor must make the source relationship obvious:

- title and metadata are derived song values produced from the ChordPro source
- ChordPro source is canonical text source
- transpose and capo settings are song-level settings that affect the reader preview

If a later implementation decides that any additional field must be persisted or derived, that decision must be documented in the repository rather than left implicit in the mock.

## Layout Direction

### Recommended Shape

The preferred layout is a two-surface workspace:

- left: derived song summary and metadata overview
- right: canonical ChordPro source editor with an internal Source / Preview toggle

This layout gives the editor a stable mental model: derived data on one side, source in the main editing block, preview available without leaving that block.

### Responsive Behavior

The mock should demonstrate responsive behavior that follows the existing prototype style:

- wide: both main surfaces visible, with the source block offering Source / Preview toggle
- tablet: switchable surface tabs for `Overview`, `Source`, and `Preview`

Tablet mode should default to `Source` and allow the user to switch between the derived summary, source editor, and preview without losing context.

## State Model

The mock and eventual UI should be able to express these states:

- default
- loading
- empty song
- read-only
- unauthorized
- pending mutation
- conflict
- validation error
- parse warning
- offline cached

### State Meanings

- `read-only`: the song can be viewed but not edited
- `unauthorized`: backend-enforced write access is denied
- `pending mutation`: local-first change is waiting for sync
- `conflict`: local changes diverged from the canonical server state
- `validation error`: the form or source is invalid
- `parse warning`: source is valid, but preview data includes a warning

## Architecture Constraints

- Presentation must stay within repository-owned prototypes and docs until implementation planning begins.
- Any eventual implementation must keep backend-enforced authorization as the source of truth.
- The editor must not introduce a second song-write state machine in the UI.
- The editor must not redefine canonical song data semantics already described in `docs/domain/domain-model.md` and `docs/specs/2026-04-05-song-crud.md`.
- If implementation work discovers a durable product or architecture decision, that decision must be mirrored in repository docs in the same change.

## Prototype Requirements

Create and maintain a prototype companion in `docs/prototypes/` using the existing prototype conventions:

- `song-editing-mockup.html`
- `song-editing-mockup.css`
- `song-editing-mockup.js`

The prototype should include reviewer controls matching the rest of the repo:

- screen: overview, source, preview
- layout: tablet, wide
- theme: standard, high contrast, black
- state: default, loading, empty song, read-only, unauthorized, pending mutation, conflict, validation error, parse warning, offline cached

The prototype should show:

- derived summary display for title and metadata
- source editing
- song-level transpose and capo editing
- preview that reflects the effective result of the stored settings
- save, cancel, and error feedback

## Acceptance Criteria

1. The spec clearly separates stored song-level transpose/capo from reader runtime transpose/capo.
2. The workspace treats ChordPro as canonical and derived title/metadata as read-only output in this slice.
3. The workspace shows a clear relationship between source, derived summary, and preview output.
4. The prototype follows the existing `docs/prototypes/` visual vocabulary.
5. The prototype supports layout, theme, screen, and state review controls.
6. The spec does not introduce new backend authorization rules.
7. The spec does not contradict the existing song domain model or song CRUD slice.
8. Any future implementation can translate the spec into a concrete plan without inventing missing product decisions.

## Validation Notes

- Review the mock in browser against the existing prototype set.
- Validate the editing hierarchy on wide and tablet layouts.
- Validate tablet surface switching across `Overview`, `Source`, and `Preview`.
- Validate the state switcher against normal, read-only, unauthorized, pending, conflict, and error scenarios.
- Validate that the preview communicates the effect of stored settings without collapsing into the reader runtime control model.

## Documentation Impact

This slice must update:

- `docs/prototypes/song-editing-mockup.html`
- `docs/prototypes/song-editing-mockup.css`
- `docs/prototypes/song-editing-mockup.js`
- `docs/plans/` once the implementation plan is written
- `docs/domain/domain-model.md` only if the eventual implementation introduces a durable schema or semantics change for song editing settings
