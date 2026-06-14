# Song Reader Immersive Controls

Date: 2026-06-14
Status: Accepted

## Problem

The compact song reader exposes transpose / capo / font / view-mode controls
through a large `Card` overlay anchored at the top of the screen
(`SongReaderCompactOverlay` + `SongReaderHeader`). The overlay is bulky, auto-hides
after 3 seconds, and competes visually with the song content. System status and
navigation bars remain visible, shrinking the reading area on phones.

This change reworks the compact reader interaction into a single immersive toggle
with a slim bottom control bar, and consolidates the view-mode toggle into the
existing overflow menu.

## Goals

1. A single tap on the song content toggles an immersive "reader-active" state:
   - System status + navigation bars hide (Android immersive); they restore on
     tap-off and on leaving the screen.
   - A slim bottom icon control bar appears.
2. The control bar holds transpose −/value/+, capo −/value/+, and font −/+ as
   compact icon controls.
3. The lyrics-only / chords+lyrics toggle moves into the AppBar overflow (`...`)
   menu, alongside Guitar/Piano view.
4. The effective key stays persistently visible at the top of the screen.
5. Recoverable parse warnings move to an unobtrusive AppBar indicator.

## Non-Goals

- Reworking the expanded (tablet/wide) surface beyond the view-mode menu move.
- Changing pinch-to-zoom or double-tap fit behaviour (unchanged).
- Changing transpose/capo/font math or persistence.

## Interaction Model

The existing `SongReaderState.areCompactControlsVisible` flag becomes the single
"reader-active" toggle. There is no auto-hide timer.

| State                       | System bars | Bottom control bar | AppBar | Bottom context bar |
| --------------------------- | ----------- | ------------------ | ------ | ------------------ |
| reader-active = false       | visible     | hidden             | shown  | shown (scoped)     |
| reader-active = true (tap)  | hidden      | shown              | shown  | shown (scoped)     |

- Tap on the compact surface toggles the flag.
- When the flag is true → `SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky)`.
- When the flag is false → restore (`SystemUiMode.edgeToEdge`).
- `dispose()` restores system bars so other screens are unaffected.
- The 3-second auto-hide machinery is removed:
  `_compactOverlayHideTimer`, `_compactOverlayInactivity`,
  `_handleCompactOverlayVisibilityChanged`, `_bumpCompactOverlayInactivityIfVisible`.
  The per-action `_bump...` calls are dropped.

## Bottom Control Bar

New widget `SongReaderControlBar` (replaces `SongReaderCompactOverlay`).
Anchored at the bottom of the compact surface, above the bottom context bar,
shown only when reader-active.

Layout (single row, compact icon buttons on a themed surface container):

```
[T−] [transpose value] [T+]   ·   [capo−] [capo value] [capo+]   ·   [A−] [A+]
```

- Capo group is hidden when not in guitar mode
  (`projection.isCapoDirectiveVisible == false`).
- `capo−` is disabled at capo 0 (existing `onCapoDown == null` guard).
- Transpose value uses signed formatting (`+2`, `-1`); capo value is a plain int.
- Reuses existing callbacks: `onTransposeDown/Up`, `onCapoDown/Up`,
  `onDecreaseFontScale/IncreaseFontScale`.
- Existing widget keys are preserved where practical for tests
  (`song-reader-transpose-down/value/up`, `song-reader-capo-down/value/up`).

## View Mode in Overflow Menu

`_SongReaderOverflowAction` gains a `toggleViewMode` action. The menu item label
flips with the current mode:

- in chords+lyrics → "Lyrics only" (`songReaderLyricsOnlyAction`)
- in lyrics-only → "Chords + lyrics" (`songReaderChordsAndLyricsAction`)

The view-mode button is removed from the header/overlay.

## Effective Key Indicator

The effective key stays at the top, surfaced in the AppBar (subtitle line under
the song title). It is computed via the same transpose path used for displayed
chords, so it stays consistent with the chords on screen:

- piano mode: `sourceKey` transposed by `effectiveTranspose`
- guitar mode: `sourceKey` transposed by `effectiveTranspose`, then by
  `-effectiveCapo`

When `sourceKey` is null the indicator is omitted. The projection exposes a new
`effectiveKey` string (nullable) computed with the existing `SongChordTransposer`,
reusing the `_displayChord` logic path. The standalone source-key `_MetadataChip`
in the header is removed.

## Warnings Indicator

When `hasRecoverableWarnings` is true, the AppBar shows a `warning_amber` icon
action (left of the `...` menu). Tapping it opens a dialog showing the warning
count (existing copy from `_WarningSurface`). The `_WarningSurface` in the header
is removed.

## Files Affected

- `song_reader_screen.dart` — immersive toggle + dispose restore; remove auto-hide
  machinery; overflow `toggleViewMode` item; AppBar effective-key subtitle and
  warning action; wire `SongReaderControlBar`.
- `widgets/song_reader_control_bar.dart` — new bottom icon row.
- `widgets/song_reader_compact_surface.dart` — host the bottom control bar instead
  of the top overlay; remove `onToggleViewMode` plumbing for the overlay.
- `widgets/song_reader_compact_overlay.dart` — deleted.
- `widgets/song_reader_header.dart` — reduced (NOT deleted; the expanded tools
  panel still renders it for the side panel). Removed: view-mode section, source
  Key `_MetadataChip`, `_WarningSurface`. Kept: transpose/capo/font sections.
  Params `onToggleViewMode`, `hasRecoverableWarnings`, `warningCount` dropped.
- `song_reader_projection.dart` — add `effectiveKey`.
- `shared/app_strings.dart` — any new labels/semantics (warning dialog title, etc.).
- Expanded surface (`song_reader_expanded_surface.dart` /
  `song_reader_expanded_tools_panel.dart`) — drop `onToggleViewMode`,
  `hasRecoverableWarnings`, `warningCount` plumbing (view-mode now in the shared
  menu; key + warnings now in the shared AppBar). Layout otherwise unchanged.

## Testing

- Tapping the compact surface toggles `areCompactControlsVisible` and the control
  bar visibility (widget test).
- Toggling on calls immersive mode; toggling off and dispose restore system bars
  (verify via a `SystemChrome` channel mock / `TestDefaultBinaryMessenger`).
- Control bar transpose/capo/font buttons invoke the right callbacks; capo group
  hidden in piano mode; `capo−` disabled at 0.
- Overflow menu `toggleViewMode` flips the view mode and label.
- Effective key string matches the displayed-chord transpose path for piano and
  guitar (incl. capo), and is omitted when `sourceKey` is null.
- Warning action appears only with recoverable warnings and opens the dialog.
- No auto-hide: control bar stays visible until the next tap (timer removed).

## Risks

- Immersive sticky behaviour differs across Android versions / iOS; restore on
  dispose is essential to avoid leaking hidden bars into other screens.
- Removing `song_reader_header.dart` / `song_reader_compact_overlay.dart` may
  break existing widget tests that target the old overlay; those tests are updated
  to the new control bar.
