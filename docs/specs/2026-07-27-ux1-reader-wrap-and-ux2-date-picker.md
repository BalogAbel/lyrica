# S5 — UX-1: reader line-wrap and chord alignment; UX-2: plan date/time picker

**Date:** 2026-07-27
**Slice:** S5 (Phase 2)
**Findings:** UX-1, UX-2 (`docs/architecture/repository-review-2026-06-22.md`)
**Branch:** `refactor/ui-decomposition-phase2` (same branch as S4)
**Depends on:** S4 — the widgets this slice changes were extracted there

## UX-1

### Problem

On a narrow screen (reproduced at 375 px) the reader breaks a lyric line
mid-word and the chord ends up over the wrong syllable.

The cause is not text wrapping. `ChordproParser._parseLyricLine`
(`infrastructure/song_library/chordpro/chordpro_parser.dart:342-383`) splits a
lyric line into segments **at chord positions**, with raw `substring` calls and
no trimming. A chord placed inside a word therefore produces two adjacent
segments with no whitespace between them:

```
[C]por[D]cikám,   →   [ {chord: C, text: "por"}, {chord: D, text: "cikám,"} ]
```

`SongLineView` (`presentation/song_reader/widgets/song_line_view.dart:54-68`)
renders one `Wrap` child per segment. `Wrap` may break between any two children,
so it breaks inside the word, and the second segment's chord travels to the new
row with it. Nothing in the codebase has a notion of a word boundary or segment
grouping.

### Divergence between the fit estimate and the render

The review's §10 testing gap asks for a fit-layout regression test that asserts
estimate/render consistency. The padding half of that contract already holds:
`song_reader_compact_surface.dart:147-148` computes
`min(constraints.maxWidth, maxContentWidth) - contentPaddingH` and
`constraints.maxHeight - contentPaddingV` for the fit calculator, and lines
296-320 compose the identical subtraction structurally for the render, off the
same `LayoutBuilder` constraints. `tileWidth` is `(availableWidth - sectionGap) / 2`
on both sides. The expanded surface follows the same pattern
(`song_reader_expanded_surface.dart:121-122` vs `213-243`).

The height half does not hold. `_lineItemHeight`
(`presentation/song_reader/song_reader_fit.dart:166-189`) diverges from the
render in four ways:

| # | Estimate | Render |
|---|----------|--------|
| 1 | `ceil(joinedLength / charsPerLine)` — assumes greedy character wrapping | `Wrap` breaks between **segments**, never inside one, and never at a character position |
| 2 | subtracts `linePadding = 24.0` from `columnWidth` (`:166`) | nothing reserves 24 px; `Wrap` and each segment's `ConstrainedBox` use the full width (`song_line_view.dart:48-50, 114-115`) |
| 3 | charges `chordRowHeight` **once per line** (`:187-189`) | every segment carries its own chord column, so a line wrapped into N runs renders up to N chord rows (`song_line_view.dart:105-119`) |
| 4 | adds a single flat `lineGap` | `Wrap.runSpacing` (`_lineRunSpacing = 10.0`) is added between every run, on top of the grid's own inter-line gap |

Divergence 3 grows exactly in the narrow-screen, chord-inside-word case this
slice fixes, and the fix itself increases run counts — so leaving the estimator
alone would make the drift worse, not neutral.

The chord-only / whitespace-only collapse rule is already duplicated
consistently: `song_reader_fit.dart:175-177` and `song_line_view.dart:33-38`
both use `segments.any((s) => s.text.trim().isNotEmpty)`.

No existing test renders a real `SongLineView` and compares it against the
estimate. `song_reader_fit_test.dart` is estimator-vs-estimator throughout.
`song_reader_fit_to_screen_test.dart:218-264` pins the width/height **plumbing**
(real rendered dimensions fed back into `resolveFitFontScale`) but never checks
that the estimated height matches the rendered content height.

### Design

**Grouping module.** A new pure module
`presentation/song_reader/song_reader_word_groups.dart`:

```dart
class SongReaderWordGroup {
  const SongReaderWordGroup(this.segments);
  final List<SongReaderSegmentProjection> segments;
}

List<SongReaderWordGroup> groupSegmentsIntoWords(
  List<SongReaderSegmentProjection> segments,
);
```

A new group starts when the previous segment's text ends with whitespace, or the
current segment's text starts with whitespace. A segment with empty text (a bare
chord in the middle of a word) attaches to the group that follows it. Whitespace
stays inside the segment text — the module narrows where a break may happen and
changes nothing about what is drawn.

**Render.** `SongLineView`'s outer `Wrap` takes one child per group instead of
one per segment. A group renders as `ConstrainedBox(maxWidth: maxWidth)` wrapping
an inner `Wrap(spacing: 0)` of the segment columns. In the normal case the inner
`Wrap` lays the group out on a single run, so no break happens inside a word. If
a single group is wider than the available width — a very long word carrying
several chords — the inner `Wrap` breaks it, which is today's behaviour, now
reached only as a last resort. This needs no measurement and cannot overflow.

**Estimator.** `song_reader_fit.dart` imports the same
`groupSegmentsIntoWords` and simulates greedy group packing:

- group width is `groupCharacterCount * characterWidthEstimate * fontScale`;
- groups are packed into runs of `effectiveLineWidth`; a group wider than a run
  occupies `ceil(groupWidth / effectiveLineWidth)` runs;
- `effectiveLineWidth` is `columnWidth` — the phantom `linePadding = 24.0`
  subtraction is removed, because the render does not reserve it;
- a run's height is `lyricRowHeight * fontScale`, plus
  `(chordRowHeight * fontScale + chordLyricGap)` when that run contains a
  segment with a `displayChord` and the view mode shows chords;
- the line's height is the sum of run heights, plus
  `(runCount - 1) * lineRunSpacing`, plus the existing `lineGap`.

**Shared metrics.** `presentation/song_reader/song_reader_metrics.dart` holds the
constants both sides need (`lineRunSpacing`, the chord-to-lyric gap). They are
duplicated today and kept in sync only by discipline; both files import them
after this slice.

**Accepted consequence.** A more accurate estimate produces a different auto-fit
scale. That is the point of the change, not a regression. Existing fit tests are
mostly monotonicity assertions and should hold; any test that pins a concrete
scale is updated deliberately, with the reason stated in the commit.

### Test contract

1. `song_reader_word_groups_test.dart` — the grouping rules as pure unit tests,
   including the mid-word chord case, leading/trailing whitespace, empty-text
   segments and an all-whitespace line.
2. **Mid-word regression, at 375 px.** Render a line whose word is split by a
   chord and assert both segment texts share the same `dy` — they are on the same
   visual row. This test must fail before the render fix.
3. **Estimate/render consistency.** Render a fixture song in
   `SongReaderCompactSurface` at 375 px, measure the real rendered content height
   from its `RenderBox`, and assert `estimateSongContentHeight`, given the same
   padding-adjusted dimensions, agrees within a bound. The test also asserts
   explicitly that both sides receive identical `availableWidth` /
   `availableHeight`. The bound is measured, not guessed: the plan records the
   observed relative error after the fix and pins a bound just above it, plus an
   absolute ceiling, so the test is neither flaky nor vacuous.
4. **Chord rows per run.** A line that wraps into two runs, both containing a
   chord, must be estimated with two chord rows.

## UX-2

### Problem

The plan `scheduled_for` value is edited as a raw ISO-8601 text field
(`2026-04-05T08:30:00.000Z`) in the edit-plan dialog, parsed by
`_parseOptionalDateTime` with a `_scheduledForError` string for invalid input.
The field stores a `timestamptz`, but the plan header renders it with
`MaterialLocalizations.formatMediumDate` — date only — so a time the user types
is stored and never shown back.

### Design

In `presentation/planning/widgets/plan_editor_dialog.dart` the ISO text field is
replaced by a read-only display of the current value (formatted local date and
time, or a "not scheduled" label) with two affordances:

- **Pick** → `showDatePicker`, then `showTimePicker`. The chosen local date and
  time are combined into a local `DateTime` and converted with `.toUtc()` before
  going into the draft. Cancelling either step leaves the value unchanged.
- **Clear** → sets the value to `null`, preserving today's nullable semantics.

`_parseOptionalDateTime` and `_scheduledForError` are deleted — invalid input is
no longer expressible.

`_formatScheduledFor` in `plan_detail_screen.dart` is extended to render date and
time (`formatMediumDate` + `formatTimeOfDay` from `MaterialLocalizations`), so a
scheduled time is visible where it is set.

The `showDatePicker` / `showTimePicker` parameter lists are verified against the
pinned local Flutter SDK source during implementation. The `context7` MCP was
queried first per rule 16 and returned no usable signature-level documentation
for these two functions; the SDK source is the authority.

### Test contract

- Picking a date and a time produces a draft whose `scheduledFor.isUtc` is true.
- The displayed string equals the formatting of `stored.toLocal()` — the local
  display and the persisted UTC instant cannot drift apart.
- Clearing produces a `null` `scheduledFor`.
- Cancelling the date picker, and cancelling the time picker, both leave the
  existing value untouched.
- Editing a plan that already has a `scheduled_for` seeds both pickers from the
  stored instant converted to local time.

## Non-goals

- No change to ChordPro parsing or transpose semantics.
  `docs/deferred/2026-04-22-song-reader-chordpro-modulation.md` stays deferred and
  its global-only transpose contract is untouched — this slice changes layout,
  not parsing.
- No fit-layout **performance** regression test. The review lists it as a
  separate gap; this slice closes the estimate/render-consistency half and leaves
  the performance half recorded as still open.
- No `TextPainter`-based measurement in the estimator. It would be more accurate
  but runs inside a 24-iteration binary search over every line, and the review
  already flags reader fit performance as unmeasured.

## Documentation duties

- `docs/architecture/repository-review-2026-06-22.md` — UX-1 and UX-2 struck
  through and marked done; the §10 testing gap updated to record that the
  estimate/render-consistency half is now covered and the performance half is not.
- `docs/plans/2026-07-27-ux1-reader-wrap-and-ux2-date-picker.md` — implementation
  plan.
