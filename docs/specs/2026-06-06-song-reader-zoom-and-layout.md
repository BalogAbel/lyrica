# Song Reader Zoom And Layout Spec

> Status: Proposed

> This spec extends reader behavior defined in `docs/specs/2026-04-22-song-reader-capo-and-instrument-display.md` and the reader rendering work in `docs/specs/2026-05-15-chordpro-parser-rendering-improvements.md`.

## Goal

Make the song reader comfortable to read and scroll on every screen width — including tablets in landscape — and give musicians direct font-size control through pinch-to-zoom and a one-gesture fit-to-screen, with the chosen zoom remembered per song and per user. Tablets always receive the compact (overlay-controls, full-width-content) shell; the expanded side-panel shell is reserved for large desktop windows.

## Problem

The reader has three concrete UX defects, worst on mobile:

1. **The scroll thumb is not at the physical screen edge.** Two compounding causes in `song_reader_screen.dart`:
   - `Center` + `ConstrainedBox(maxWidth)` wrap the *entire* scroll view, so the scroll view shrinks to the content cap and is centered. On a wide screen the thumb sits in the middle of the window — when a song only fills half the width, the scrollbar appears in the centre.
   - The outer `Padding(EdgeInsets.all(24))` sits outside the scroll view and there is no explicit `Scrollbar`, so even on a phone the thumb is inset by the padding.
   Both make the scrollbar hard to find and grab while performing.

2. **Long lines can overflow horizontally.** Line breaking is done by a `Wrap` over atomic chord+lyric segments. A `Wrap` gives each child unbounded width, so a single long segment (a long word, or a lyric run with no chord splits) cannot break internally and overflows the line, producing horizontal clipping.

3. **No zoom.** Font size is only adjustable through `±0.1` buttons. There is no pinch-to-zoom and no quick way to size a song to the screen.

## Scope

- Restructure the reader layout so the `Scrollbar` + scroll view are the full-width outer element and all max-width / centering / padding apply to the scroll *content*. The thumb must land at the physical screen edge at every viewport width and content width.
- Guarantee that no horizontal scrolling can ever appear in the reflowable song body, at any font scale: every lyric segment wraps within the available line width.
- Add pinch-to-zoom that adjusts the existing shared font scale and reflows text. One-finger scrolling must keep working.
- Repurpose double-tap to fit the whole song to the screen (height-based), toggling back to the previous scale on a second double-tap.
- Persist the chosen zoom level locally, keyed by user and song; restore it when the song is reopened.
- Keep the scrollbar visible only while scrolling (native fade behavior), but at the edge.

## Shell Assignment

The reader has two shells: **compact** (overlay controls, full-width content, single or auto-dual column) and **expanded** (permanent side-panel tools). Shell is assigned by viewport width at render time:

- Viewports **< 1600 px** (phones, all tablets including landscape) → compact shell.
- Viewports **≥ 1600 px** (large desktop windows) → expanded shell.

In the compact shell on wide viewports (≥ 1180 px) the section grid automatically uses two columns when the song is too tall for a single screen at the current font scale, and collapses to one column when zoomed in past scale 1.15. This provides a natural tablet landscape reading experience without permanent UI chrome.

## Non-Goals

- No visual/transform (pixel) zoom; zoom is font-scale reflow only. No pan, no horizontal scroll introduced by zoom.
- No server-side persistence of zoom (no Supabase, no schema change). Local-only.
- No change to the parsed-song model, ChordPro semantics, transpose/capo behavior, or chord projection.
- No song editor changes and no new backend authorization rules.
- No change to monospace tab-block scrolling (see exception below).

## Layout And Scrollbar Rules

- The reader content scrolls vertically only.
- The `Scrollbar` and its `SingleChildScrollView` span the full available viewport width. Maximum content width, horizontal padding, and centering live **inside** the scroll view, wrapped around the section grid.
- The scroll thumb position is independent of content width: it is always at the physical right edge.
- The scrollbar uses default `thumbVisibility` (shows while scrolling, fades when idle).

## Reflow / No-Horizontal-Overflow Rule

- Each lyric segment is bounded by the available line width and wraps internally when it alone exceeds that width. The chord stays left-aligned above the (possibly wrapped) lyric.
- This must hold at the maximum allowed font scale. With vertical-only scrolling, the reflowable song body therefore never produces a horizontal scrollbar.
- **Exception:** monospace tab blocks keep their existing horizontal scroll. Tab notation is fixed-width and is not reflowable text; this is a deliberate, documented exception and is the only place horizontal scrolling remains.

## Zoom Model

- Zoom reuses the existing shared font scale; there is one scale value for the reader, applied uniformly to chord, lyric, comment, and tab text.
- The allowed scale range widens to **0.25 – 3.0**. The lower bound must allow fit-to-screen to shrink a long song on a phone; the upper bound allows meaningful magnification. The clamp is the single source of truth for both manual and gesture changes.
- **Pinch-to-zoom:** a two-pointer scale gesture multiplies the scale captured at gesture start by the live pinch factor, clamped to range. A one-finger drag must not be captured as zoom — it stays available for scrolling.
- **Double-tap = fit-to-screen (toggle):** the first double-tap sizes the song so the whole song fits the viewport height, then a second double-tap restores the scale that was active before fitting. Fit is computed from the existing height estimation, reused as a shared pure function so the reader and the fit calculation agree.
- The `±0.1` font-size buttons remain and operate on the same scale.

## Persistence Rules

- The active zoom level is stored locally, keyed by user id and song id.
- Storage is a local key-value store (no Supabase, no drift schema migration for a single scalar).
- On reader open, the stored zoom (if any) seeds the reader's shared font scale; otherwise the default scale applies.
- Zoom is written after a pinch gesture ends and after a double-tap fit/restore, debounced so rapid changes do not thrash storage.
- The user id source is the same one already used by the offline catalog layer.

## Acceptance Criteria

1. At any viewport width (phone, tablet, wide) and any content width, the vertical scroll thumb appears at the physical right edge, not inset and not centered.
2. The scrollbar is visible while scrolling and fades when idle.
3. Song text stays centered and width-capped while the scroll view itself is full width.
4. A lyric line containing a single very long unbreakable token wraps within the line and produces no horizontal overflow at the maximum font scale.
5. No horizontal scrollbar appears in the reflowable song body at any font scale; tab blocks remain the only horizontally scrollable element.
6. A two-pointer pinch changes the font scale and the text reflows live, clamped to 0.25–3.0.
7. A one-finger drag scrolls the song and is never interpreted as zoom.
8. The first double-tap sizes the whole song to fit the viewport height; a second double-tap restores the pre-fit scale.
9. The shared font scale clamps to the 0.25–3.0 range for manual buttons, pinch, and fit alike.
10. After changing zoom and reopening the same song as the same user, the previously chosen zoom is restored.
11. Zoom is not persisted to any backend; it is local-only and keyed by user and song.
12. No reader interaction changes parsed-song content, transpose, capo, or instrument display behavior.

## Documentation Impact

This slice must update:

- `docs/plans/2026-06-06-song-reader-zoom-and-layout.md` with the implementation plan for this slice.
- `docs/architecture/decisions/` with an ADR recording the local key-value persistence choice for reader zoom (drift alternative considered and rejected for friction).
- `docs/testing/testing-strategy.md` if new gesture or local-persistence test patterns are introduced.
