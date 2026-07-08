# S0a — UX-3: Non-copyrighted default song body

**Date:** 2026-07-08
**Slice:** S0a (Phase 0)
**Finding:** UX-3 (`docs/architecture/repository-review-2026-06-22.md`)
**Branch:** `refactor/arch-spine-phase0-1`

## Problem

Every new song in the editor is pre-filled with the full lyrics of a real,
copyrighted worship song via `SongEditorController.defaultSource`
(`apps/lyron_app/lib/src/presentation/song_editor/song_editor_controller.dart:15`).
This ships copyrighted lyrics inside the app binary and forces users to clear
them before writing their own song. UX-3 rates this Medium: copyright exposure.

## Goal

Replace the copyrighted `defaultSource` with an original, non-copyrighted
ChordPro sample that doubles as a syntax hint for new users.

## Scope

**In scope**

- `song_editor_controller.dart` — the `defaultSource` const.

**Explicitly out of scope**

- Test fixtures across `song_editor_*_test.dart` / `song_editor_route_test.dart`
  that reuse a short copyrighted fragment as arbitrary sample data. The finding
  cites only `:15` ("full lyrics as `defaultSource`"); fixtures embed a single
  line, not the full verse, and scrubbing them is churn beyond UX-3. Left as-is.
- `song_editor_screen.dart:50` (`_sourceSample = SongEditorController.defaultSource`)
  inherits the new default automatically; no edit required.

## Design

Replace `defaultSource` with an original sample that keeps the **same directive
set** (`title`, `artist`, `key`, `tempo`, `tags`, `transpose`, `capo`, plus a
`comment`) so the preview/projection pipeline still receives the same field
shape it does today. The lyric lines are original placeholder text that does not
resemble any existing song and instructs the user how to start.

```chordpro
{title: My New Song}
{artist: }
{key: C}
{tempo: 120}
{tags: }
{transpose: 0}
{capo: 0}

{comment: Replace this sample with your own lyrics}
[C]Type a line of lyrics and put [G]chords in brackets
[Am]Delete these lines when you [F]start your song
```

## Behavior impact

- New editor sessions open with the original sample instead of copyrighted lyrics.
- No other behavior changes: fixture-based tests pass explicit `source:` values
  and are untouched. `screen.dart` reads the const symbol, so it updates with it.

## Testing (TDD)

Write the failing test first, in
`apps/lyron_app/test/presentation/song_editor/song_editor_controller_test.dart`:

1. Construct `SongEditorController()` with **no** `source` argument (exercises the
   default).
2. Assert `controller.state.source` does **not** contain any copyrighted marker:
   `Heart of Worship`, `Matt Redman`, `When the music fades`.
3. Assert the default parses as valid ChordPro with
   `controller.state.parsedSong.title == 'My New Song'`.

This test fails against the current copyrighted default and passes once the const
is replaced.

## Commits

1. `test(song-editor): characterize non-copyrighted default source` — failing test.
2. `fix(song-editor): replace copyrighted default with original ChordPro sample`
   — replace the const; mark UX-3 fixed in the repository-review doc; update docs.

## Done when

- New failing test written first, then green.
- `defaultSource` contains no copyrighted lyrics.
- UX-3 marked fixed in `docs/architecture/repository-review-2026-06-22.md`.
- `flutter test` for the song-editor suite green; no regression elsewhere.
