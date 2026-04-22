# Song Reader Capo And Instrument Display Spec

> Status: Proposed

> This spec extends reader behavior defined in `docs/specs/2026-03-22-tablet-first-chordpro-song-reader.md`, `docs/specs/2026-04-13-song-reader-ui-discovery.md`, and `docs/specs/2026-04-16-song-reader-tablet-immersive-shell.md`.

## Goal

Add ChordPro-native capo and transpose awareness to the song reader so guitarists and pianists can see instrument-appropriate chords without mutating the stored ChordPro source.

## Problem

The current reader only supports a reader-local transpose offset and only parses the song `key` from ChordPro metadata. This leaves three gaps:

- ChordPro-authored `capo` metadata is ignored.
- ChordPro-authored `transpose` metadata is ignored.
- The reader cannot switch between guitar-oriented and piano-oriented chord presentation.

This produces incorrect or incomplete guidance for real performance use. A guitarist needs to know the effective capo position and shape chords, while a pianist needs the sounding chords without capo subtraction.

## Scope

- Read global ChordPro `key`, `capo`, and `transpose` directives into the reader slice.
- Add a reader runtime instrument-display mode with `guitar` and `piano`.
- Render guitar and piano chord views from the same parsed song content.
- Show effective transpose and effective capo values in reader controls.
- Show an in-song capo directive line for guitar mode only.
- Update the static prototype in `docs/prototypes/` first so the UI direction is reviewed before Flutter implementation.
- Record song-internal transpose modulation as deferred follow-up work in `docs/deferred/`.

## Non-Goals

- No write-back of capo, key, or transpose into ChordPro source in this slice.
- No song editor changes.
- No support in this slice for song-internal `{transpose: ...}` modulation after the song start.
- No new backend authorization rules.
- No change to canonical stored chord text inside parsed song segments.

## ChordPro Interpretation Rules

Reader behavior must follow ChordPro semantics for the directives used in this slice:

- `key` is the player-facing key from the ChordPro source.
- `capo` does not change the player-facing key, but it changes the sounding key heard by other musicians and listeners.
- `transpose` changes the effective sounding chords from the point where it appears.

For this slice, only a global transpose value is supported. That means:

- a `transpose` directive at song start is read and applied
- later in-song transpose changes are not applied yet
- this limitation must remain visible in `docs/deferred/`

The reader may use ChordPro-derived metadata such as effective key fields when useful, but the parser and projection must not invent semantics that contradict the ChordPro rules above.

## Reader State Model

The reader needs two kinds of values:

### ChordPro Base Values

These come from parsed ChordPro source:

- `baseKey`
- `baseTranspose`
- `baseCapo`

If a ChordPro directive is absent, the corresponding base value defaults to the current reader behavior:

- missing `key` stays absent
- missing `transpose` behaves as `0`
- missing `capo` behaves as `0`

### Runtime Reader Values

These remain local to the reader and are not written back to the song:

- `instrumentDisplayMode`
- `runtimeTransposeDelta`
- `runtimeCapoDelta`

The runtime values must initialize from ChordPro-aware defaults:

- effective transpose starts from `baseTranspose`
- effective capo starts from `baseCapo`
- instrument display defaults to `guitar`

Internally, runtime capo and transpose may be stored as deltas from the ChordPro base values. However, the UI must always present the effective values the musician is using right now, not the delta.

## Chord Projection Rules

The parsed song remains canonical. Projection computes displayed chords from canonical segment chords plus reader state.

Definitions:

- `effectiveTranspose = baseTranspose + runtimeTransposeDelta`
- `effectiveCapo = baseCapo + runtimeCapoDelta`
- `soundingChord = originalChord + effectiveTranspose`

Displayed chord formulas:

- guitar display chord = `soundingChord - effectiveCapo`
- piano display chord = `soundingChord`

This preserves one shared parsed-song model while allowing instrument-specific display.

## UI Decisions

### Instrument Switch

Instrument selection lives in the reader overflow menu in the top-right corner.

The menu must expose:

- `Guitar view`
- `Piano view`

This keeps the reading surface calm while still making the display mode discoverable.

### Guitar View

Guitar mode shows:

- guitar display chords
- a capo directive-style line at the top of the song body when effective capo is greater than zero
- transpose control
- capo control

The capo directive line should feel like a native ChordPro directive rendered into the reading flow, not like a detached status badge.

The capo control belongs with transpose in the reader controls:

- in compact mode inside the overlay
- in expanded mode inside the tools panel

The displayed control values must be effective values. Example:

- ChordPro `capo: 2`
- user increases capo once
- control shows `Capo 3`

### Piano View

Piano mode shows:

- piano display chords
- transpose control

Piano mode hides:

- capo directive line
- capo control
- capo value from the visible reader control surfaces

### Transpose Control

Transpose remains available in both guitar and piano modes.

The displayed transpose value must be the effective transpose value. Example:

- ChordPro `transpose: -2`
- user increases transpose once
- control shows `Transpose -1`

## Prototype-First Requirement

Before Flutter implementation, update the static reader mockup in `docs/prototypes/` to validate:

- overflow-driven guitar/piano switch placement
- guitar-only capo directive line
- guitar-only capo control visibility
- effective value rendering for transpose and capo
- compact overlay and expanded tools-panel behavior under both instrument modes

The prototype is the first design-review artifact for this slice and should be updated in the same change series as the spec and plan.

## Acceptance Criteria

1. The ChordPro parser reads global `key`, global `capo`, and global `transpose` values.
2. Reader state initializes effective capo and transpose from ChordPro-provided base values.
3. Reader overflow menu allows switching between guitar and piano display modes.
4. Guitar mode displays chords as sounding chords minus effective capo.
5. Piano mode displays sounding chords without capo subtraction.
6. Guitar mode renders a capo directive-style line near the start of the song content when effective capo is greater than zero.
7. Piano mode does not render a capo directive line.
8. Guitar mode exposes a capo control in the existing reader control area.
9. Piano mode hides the capo control.
10. Transpose control remains available in both instrument modes.
11. Visible control labels show effective capo and effective transpose values, not reader-local deltas.
12. No reader interaction in this slice writes capo, key, or transpose back into the stored ChordPro source.

## Documentation Impact

This slice must update:

- `docs/prototypes/song-reader-reader-mockup.html`
- `docs/prototypes/song-reader-reader-mockup.css`
- `docs/prototypes/song-reader-reader-mockup.js`
- `docs/plans/` with an implementation plan for this slice
- `docs/deferred/` with the deferred follow-up for song-internal transpose modulation

