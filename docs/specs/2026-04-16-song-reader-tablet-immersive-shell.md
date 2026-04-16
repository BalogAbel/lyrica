# Song Reader Tablet Immersive Shell Spec

> Status: Implemented

> This spec partially supersedes `docs/specs/2026-04-13-song-reader-ui-discovery.md` and the shipped behavior from `docs/plans/2026-04-14-song-reader-ui-implementation.md` specifically for compact/tablet shell chrome, scoped navigation placement, and catalog-status visibility inside the reader screen.

## Goal

Refine the song reader shell for tablet and compact contexts so the reader stays content-first and visually coherent during performance use.

## Problem

The current tablet rendering can mix compact and expanded chrome at the same time:

- top-level edit/delete buttons remain visible
- top previous/next controls remain visible
- bottom scoped context bar can stay visible in states where it should not
- catalog online/offline status appears in reader despite low user value in this surface

This creates a noisy and inconsistent reader, especially on tablet-sized viewports where users expect an immersive song-focused layout.

## Scope

- Redefine the compact/tablet reader shell to a minimal top bar plus overlay controls.
- Keep desktop expanded behavior intact unless explicitly covered by this spec.
- Move edit/delete affordances into a top-right overflow menu.
- Remove top previous/next controls from the reader content area.
- Restrict bottom scoped context bar visibility to scoped list/session navigation states only.
- Remove catalog online/offline status surface from the reader screen.

## Non-Goals

- No domain-layer changes to song parsing, projection, or transpose logic.
- No authorization changes.
- No redesign of song list, planning list, or plan detail screens.
- No redesign of desktop expanded side-panel information architecture in this slice.
- No theme-system overhaul.

## Reader Shell Decisions

### 1) Compact/Tablet Top Bar

The compact/tablet reader top bar must contain only:

- back affordance (left)
- current song title (center or start-aligned title area)
- overflow menu trigger (`...`, right)

The generic "Song reader" heading should not be shown when song content is visible.

### 2) Overflow Menu Actions

Edit and delete actions must move into the overflow menu in compact/tablet shell:

- `Edit song`
- `Delete song`

No standalone edit/delete buttons should remain in compact/tablet content chrome.

### 3) Navigation Placement

Previous/next behavior remains session-scoped where available, but UI placement changes:

- remove top previous/next button row from compact/tablet content area
- keep previous/next interaction through bottom scoped context bar only
- in unscoped reader, no previous/next controls are shown

### 4) Bottom Scoped Context Bar Visibility

The bottom context bar is shown only when reader has scoped list/session context that can provide current-item orientation and sequence navigation.

It is hidden when:

- reader is not opened from scoped session/list context
- scoped context cannot resolve to a usable sequence
- no current song projection is available

### 5) Catalog Connectivity Status

Do not render catalog online/offline/refresh state surfaces inside reader shell for this slice. Reader remains manually controllable and this status does not provide actionable value on this screen.

## Architectural Constraints

- Preserve one shared reader core (state, projection, controller behavior).
- Compact/tablet vs expanded differences stay at presentation-shell level.
- Maintain scoped and unscoped state parity for reader runtime controls.
- Do not reintroduce compact overlay or compact-only controls into expanded shell.

## Acceptance Criteria

1. On compact/tablet reader with a loaded song, header shows only back, song title, overflow menu.
2. Edit/delete appear only in overflow menu for compact/tablet reader.
3. Top previous/next button row is absent in compact/tablet reader.
4. Bottom context bar appears only for scoped sequence contexts; hidden otherwise.
5. Tapping bottom previous/next performs scoped navigation exactly as before.
6. Previous/next interaction target is the full previous/next segment area in the bottom bar, not only the text label.
7. Catalog connectivity status surface is not rendered in reader screen.
8. Existing reader controls (lyrics-only, transpose, font scale, auto-fit) remain reachable through compact/tablet overlay and preserve current behavior.

## Validation Notes

- Validate in mobile and tablet viewports, including web tablet.
- Validate both scoped and unscoped entry paths.
- Validate empty/unavailable song and error states to ensure shell does not leak stale bottom context chrome.
