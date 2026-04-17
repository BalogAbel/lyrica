# Song Reader Landscape Shell Alignment Spec

> Status: Implemented

> This spec partially supersedes `docs/specs/2026-04-16-song-reader-tablet-immersive-shell.md` specifically for landscape/expanded reader header chrome, action placement, and set-context interaction behavior.

## Goal

Align the landscape reader shell with the compact immersive direction so tablet landscape reading stays content-first, consistent, and navigation-aware.

## Problem

The current landscape/expanded reader still shows older chrome patterns that now diverge from the compact/tablet direction:

- the app bar can still show the generic `Song reader` title instead of the current song title
- `Edit song` and `Delete song` remain as standalone top-level actions
- the `Set context` panel is informational only and not directly interactive
- the `Set context` panel can remain visible even when the reader was not opened from a list/session sequence

This makes the landscape shell feel like a separate product surface instead of a larger-screen variant of the same reader.

## Scope

- Replace the generic landscape app-bar title with the current song title while song content is available.
- Remove the duplicate expanded title bar so title ownership lives in the app bar.
- Move landscape edit/delete actions into the overflow menu.
- Make the landscape set-context surface directly tappable for sequence navigation.
- Hide the landscape set-context surface when no scoped list/session context exists.
- Preserve the existing shared reader runtime controls and expanded content/tools structure outside these shell changes, while still keeping subtitle metadata visible above content when present.

## Non-Goals

- No domain-layer changes to song parsing, projection, or transpose logic.
- No authorization changes.
- No redesign of compact overlay controls.
- No new reader-specific persistence.
- No redesign of planning list or song list screens.
- No change to the shared reader core state boundary.

## Reader Shell Decisions

### 1) Landscape Header Title

When the landscape/expanded reader has a loaded song, the app bar must show the current song title instead of the generic `Song reader` label.

The previous expanded in-content title bar is removed so the title is not duplicated. If subtitle metadata exists, it remains visible in the expanded content chrome below scoped navigation and above the reader surface.

Fallback title behavior may still use `Song reader` for loading, missing-content, or explicit error states.

### 2) Landscape Overflow Menu Actions

Landscape/expanded shell must use the same top-right overflow action model as the compact shell for song management actions:

- `Edit song`
- `Delete song`

No standalone top-level edit/delete buttons should remain above the expanded reader content.

### 3) Interactive Set Context Panel

The landscape `Set context` surface must become interactive when reader navigation is backed by a scoped list/session sequence.

Expected interaction model:

- previous context affordance is tappable when a previous scoped item exists
- next context affordance is tappable when a next scoped item exists
- interaction targets must be the panel segments, not text-only hit targets

### 4) Set Context Visibility

The landscape `Set context` surface is shown only when the reader has scoped list/session context that can resolve current-item orientation and sequence neighbors.

It is hidden when:

- reader was opened directly outside scoped list/session context
- scoped context cannot resolve to a usable sequence
- no current song projection is available

### 5) Shared Shell Consistency

Compact and landscape shells must keep the same product rules for:

- title ownership in the app bar
- overflow-based edit/delete placement
- scoped-only sequence navigation chrome

Differences between compact and landscape remain presentation-shell only:

- compact uses bottom context bar
- landscape uses left set-context panel

## Architectural Constraints

- Preserve one shared reader core (state, projection, controller behavior).
- Compact vs landscape differences stay at presentation-shell level.
- Keep scoped/unscoped runtime-state parity intact.
- Do not reintroduce compact overlay patterns into expanded shell.
- Keep overflow actions separate from reader runtime overlay controls.

## Acceptance Criteria

1. In landscape/expanded reader with loaded song, the app bar shows the current song title instead of `Song reader`.
2. `Edit song` and `Delete song` appear only in the overflow menu for landscape/expanded reader success state.
3. The expanded `Set context` panel is hidden in unscoped reader entry.
4. The expanded `Set context` panel is visible in scoped reader entry.
5. Expanded previous/next context segments are directly tappable hit targets.
6. Tapping expanded previous/next context performs the same scoped navigation as before.
7. Expanded shell removes the duplicate title bar while keeping subtitle metadata visible when present.
8. Shared reader runtime controls remain available in expanded mode and preserve current behavior.

## Validation Notes

- Validate on tablet landscape viewport.
- Validate both scoped and unscoped reader entry.
- Validate expanded success, loading, and scoped-context-unavailable states.
- Validate that current song title fallback still behaves safely in non-success states.
