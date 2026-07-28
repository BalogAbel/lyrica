# Reader fit: how much the upper bound overshoots

Related:
- `apps/lyron_app/lib/src/presentation/song_reader/song_reader_fit.dart`
- `apps/lyron_app/test/presentation/song_reader/song_line_view_estimate_consistency_test.dart`
- `apps/lyron_app/test/presentation/song_reader/song_reader_estimate_render_consistency_test.dart`

The fit estimator is now a deliberate **upper bound**: `resolveFitFontScale` picks
the largest scale whose estimated height fits, so an estimate below the rendered
height would let fit-to-screen overflow — the one thing the feature exists to
prevent. The tests assert `estimated >= rendered` one-sidedly rather than a
symmetric tolerance.

The cost is that auto-fit chooses a smaller font than strictly necessary. Measured
at 2026-07-28 against real `SongLineView` renders:

| Line shape | Rendered | Estimated | Ratio |
|------------|----------|-----------|-------|
| chord-only instrumental bar | 122 px | 122 px | 1.00 |
| chord-split word | 54 px | 58 px | 1.07 |
| wide chords over syllables | 210 px | 226 px | 1.08 |
| single segment wrapping several times | 434 px | 514 px | 1.18 |
| plain wrapping lyric line | 292 px | 372 px | 1.27 |
| plain wrapping line at text scaler 1.5 (linear) | 492 px | 660 px | 1.34 |
| whole-song plain fixture | 1082 px | 1198 px | 1.11 |
| whole-song chord-heavy fixture | 2574 px | 2630 px | 1.02 |

Lines that wrap inside a single segment are the loose end: up to ~1.34. Lines
dominated by chords are near-exact. Aggregated over a whole song the overshoot is
1.02-1.11, because most lines are not a single over-wide segment — so the practical
font-size cost is smaller than the worst per-line ratio suggests.

## Non-linear `TextScaler` (2026-07-28, fifth review round)

A fifth round found the estimator could fall **under** the render (not just
overshoot it) whenever the ambient `MediaQuery.textScalerOf(context)` is
non-linear (e.g. Android 14+ non-linear font scaling): the old code
flattened the scaler to a single ratio measured at a 1px probe
(`textScaler.scale(1.0)`) and multiplied every row-height constant and
character width by that one number. For `TextScaler.linear(x)` the probe
ratio equals the real ratio at every size, so this happened to work; for a
non-linear scaler it does not, and depending on the curve's shape the result
can be a genuine under-estimate, not just a looser bound. The fix
(`song_reader_fit.dart`'s `SongReaderFitTextScale`) threads the real
`TextScaler` down and evaluates it at each style's own actual base size and
candidate `sharedFontScale`, per style (lyric, chord, section header,
directive line), instead of a single flattened number.

`ambientTextScaleRatio` was removed from `SongReaderCharWidths` entirely —
nothing needs a flat ratio once every quantity is converted via
`SongReaderFitTextScale.factorFor` at its own real size. `lyricCharWidth`/
`chordCharWidth` also changed what they measure: previously the ambient
scaler was baked into the measurement itself (measured with the ambient
`TextScaler` applied), and callers multiplied by `sharedFontScale` alone
afterward; now they are measured RAW (no scaler at all) and every caller
converts them to the candidate scale via the same per-style factor. Baking
the scaler into the measurement and then applying a second, flattened
factor on top would double-count it.

Measured against a synthetic non-linear scaler with a "hump" shape (1.1x
at/below 2px, peaking at 1.9x at 14px, back down to 1.2x at/above 22px —
see `_NonLinearTextScaler` in `song_line_view_estimate_consistency_test.dart`
for why a hump, not a monotonic curve, is needed to reproduce a genuine
under-estimate: a monotonically-decreasing curve makes the 1px probe the
curve's global maximum, so flattening it can only ever over-estimate, never
under):

| Line shape | Rendered | Estimated | Ratio |
|------------|----------|-----------|-------|
| chord-only instrumental bar (fontScale 1.0, width 150) | 346 px | 346 px | 1.00 |
| plain wrapping lyric line (fontScale 1.0) | 610 px | 881.4 px | 1.44 |
| plain wrapping lyric line (fontScale 1.3) | 488 px | 622.74 px | 1.28 |

Pre-fix, the same three cases were RED: chord-only bar (width 150) 346
rendered vs. 194 estimated (a genuine under-estimate — the exact failure
mode this round exists to close), plain lyric line 610 vs. 566.4 (also
under), and the fontScale-1.3 case 488 vs. 732.72 (over the ceiling, i.e.
wrong in the other direction once `sharedFontScale != 1.0` is in play). The
whole-song fixtures (both measured under the identity scaler at fontScale
1.0) were unaffected — their numbers above are unchanged post-fix, since
`SongReaderFitTextScale`'s default (`TextScaler.noScaling`, base sizes
16/14/22/12) reduces to the pre-fix arithmetic exactly when the scaler is
linear.

## Chord label self-wrap (2026-07-28, same round, closed before merge)

A follow-up review of the non-linear-scaler fix found the chord-only bar
fixture above was passing for the wrong reason at some widths: it had been
widened from 150px to 260px specifically to dodge a SEPARATE bug rather than
prove the fix. `_SongLineSegmentView`'s chord `Text` (widgets/song_line_view.dart)
has no `ConstrainedBox` of its own — only the lyric `Text` below it does —
but `RenderWrap` constrains EVERY child's main-axis size to its own
`constraints.maxWidth` regardless (Flutter SDK, `RenderWrap._computeRuns`).
So a chord label wider than the line wraps internally onto a second (or
further) line, growing the segment taller, and the estimator (which assumed
every chord label renders on exactly one line, always charging exactly one
`chordRowHeight`) fell under the render whenever that happened. Reachable in
practice: a ten-plus character extended/slash chord at a 14px base size,
under a non-linear scaler near its peak boost and a raised `sharedFontScale`,
comfortably exceeds a 375px phone's content width.

Fixed by modelling chord self-wrap in `song_reader_fit.dart`'s
`_segmentRowHeight`: a segment's chord occupies
`ceil(chordWidth / effectiveLineWidth)` chord rows (using the chord style's
own per-style factor), the same way an over-long lyric word already occupied
`ceil(wordWidth / effectiveLineWidth)` lines — a chord label has no spaces to
break on in the general case (extended/slash chords have no reliable word
boundary), so an even division is the right model here, unlike lyric text,
where word-boundary-aware greedy packing was needed. The run/group height
computation was also changed from separately maxing "chord rows across the
run" and "lyric lines across the run" and summing those maxes, to computing
each segment's own combined height (`chordRows * chordRowHeight` + gap +
`lyricLines * lyricRowHeight`) and taking the run's height as the max of its
segments' combined heights — max(a)+max(b) can exceed max(a+b) when the
tallest-chord segment and the tallest-lyric segment in a run differ, so the
old sum-of-maxes was already an (harmless, over-estimating) approximation;
the new per-segment max matches what `Wrap` actually measures.

Measured, no custom `TextScaler` (default/unscaled), at a 130px column (just
above `_lineItemHeight`'s own 120px `columnWidth.clamp` floor, so the
estimator and the real render agree on the width being tested):

| Line shape | Rendered | Estimated | Ratio |
|------------|----------|-----------|-------|
| long chord label alone must wrap (`Cmaj7#11/G`, 10 chars) | 52 px | 52 px | 1.00 |
| wrapping chord label over a lyric syllable | 74 px | 78 px | 1.05 |

Pre-fix, both were RED: 52 rendered vs. 32 estimated, and 74 rendered vs. 58
estimated — the estimator's chord-row contribution was a flat 20px
(`chordRowHeight`) regardless of how many rows the label actually needed.
None of the other per-line fixtures in the table above moved: the group/run
height computation change is provably conservative-or-equal everywhere a
chord label does NOT need to wrap (every segment's own width is already
`<= effectiveLineWidth` whenever its group is not flagged over-wide, so
`_segmentRowHeight` can never compute more than 1 chord row there), and the
two whole-song fixtures' chords (longest 8 characters) stay well under
their ~327px tile width, so neither triggers the chord-wrap path either —
their numbers are unchanged.

## Full-kind sweep (2026-07-28, same round): every kind the estimator assigns a height to

Three rounds in a row found the same shape of defect (some rendered element
wraps/grows in a way the estimator does not model) one fixture at a time —
the ambient-scaler flattening, then the chord label's own wrap, then the
inline directive's 6.3x under-estimate found in passing while checking for
more of the same. Rather than wait for a fourth fixture to stumble onto the
next one, every kind `_lineItemHeight`'s switch and `flowBlockHeight`'s
`FlowBlockKind` switch (song_reader_fit.dart) assign a height to was
enumerated and given a real render-vs-estimate case (short instance + long
instance at a narrow width) in
`song_reader_block_estimate_consistency_test.dart` (the lyric line itself
is covered exhaustively by `song_line_view_estimate_consistency_test.dart`,
above).

Pre-fix sweep (2026-07-28), default/unscaled `TextScaler`, fontScale 1.0:

| Kind | Case | Rendered | Estimated | Status |
|------|------|----------|-----------|--------|
| Comment | short, width 300 | 30 px | 34 px | OK |
| Comment | long, width 150 | 410 px | 346 px | **RED** (under) |
| Tab block | short, width 300 | 46 px | 50 px | OK |
| Tab block | 4 long lines, width 100 | 106 px | 122 px | OK |
| Inline directive | short, width 300 | 30 px | 36 px | OK |
| Inline directive | long value, width 150 | 238 px | 36 px | **RED** (6.6x under) |
| Leading directive | short, width 300 | 44 px | 56 px | OK |
| Leading directive | long, width 150 | 304 px | 56 px | **RED** (5.4x under) |
| Section header | short label, width 300 | 40 px | 60 px | OK |
| Section header | long custom label, width 150 | 404 px | 60 px | **RED** (6.7x under) |

Four of five non-lyric kinds were broken. Tab blocks were the exception:
`TabBlockView` (widgets/tab_block_view.dart) draws its raw lines inside a
`SingleChildScrollView(scrollDirection: Axis.horizontal)`, so a tab line
SCROLLS rather than wraps no matter how long it is or how narrow the column
is — proven by the "several LONG tab lines at a narrow width" case above,
which stayed green with NO fix. One estimated row per raw line was already
exact; the constant was left alone, per "a proven-tight case is a useful
result, not a wasted one."

Fixes, one per kind, each in `song_reader_fit.dart`:
- **Comment** (`SongReaderCommentProjection`): `CommentLineView` sits
  directly in the grid's Column (full available width) and wraps at word
  boundaries like a lyric segment does — the old formula was a plain
  character-count division, the same undercounting bug the lyric line had
  before its own word-wrap fix. Now uses `_wordWrapLineCount` (the lyric
  line's word-boundary model, extracted into a shared helper), reusing
  `lyricCharWidth` as a deliberately conservative width proxy (comment's
  real style, `bodyMedium` 14px, is smaller than lyric's `bodyLarge` 16px,
  so this can only over-count wraps, never under).
- **Inline directive** (`SongReaderDirectiveProjection` /
  `DirectiveLineView`) and **leading directive**
  (`FlowBlockKind.leadingDirective` / `_DirectiveLine`): both sit directly
  in a Column and wrap at word boundaries too — word-boundary text, not a
  chord label, so both use `_wordWrapLineCount` as well, reusing
  `chordCharWidth` (`labelLarge`+`w700`, bolder and same-or-larger than
  either directive style) as a conservative proxy. The flat
  `directiveLineHeight` constant was previously charged once regardless of
  the directive's own text length; it is now multiplied by the real
  word-wrapped line count.
- **Section header** (`FlowBlockKind.sectionHeader` /
  `_buildHeaderWidget`): also word-boundary text, but unlike the directive
  kinds, no existing measured char width is a safe (conservative) proxy —
  `titleLarge` (22px) is LARGER than every other measured style, so
  reusing a smaller one would UNDER-count, not over-count. A genuine
  `headerCharWidth` measurement (titleLarge, no weight override) was added
  to `SongReaderCharWidths`. Section labels are not a hypothetical edge
  case: a ChordPro `start_of_verse`-style directive can carry an arbitrary
  custom label.

Modelling the header and leading-directive fixes required a real (if
additive) API extension: `FlowBlock` previously carried no text at all for
these two kinds, so `flowBlockHeight` had nothing to measure. `FlowBlock`
gained an optional `blockText` field, populated by `buildFlowBlocks` from
the section's label / the leading-directive string; `flowBlockHeight`,
`resolveFlowLayoutForSections`, `estimateRenderedLayout`, and
`resolveFitFontScale` gained optional `headerCharWidth` /
`leadingDirectiveText` parameters, all defaulting to today's flat-constant
behavior so the ~40 pre-existing call sites in `song_reader_fit_test.dart`
(which construct `FlowBlock`s directly, without text) needed no changes and
all still pass unchanged.

Post-fix sweep:

| Kind | Case | Rendered | Estimated | Ratio |
|------|------|----------|-----------|-------|
| Comment | short, width 300 | 30 px | 34 px | 1.13 |
| Comment | long, width 150 | 410 px | 586 px | 1.43 |
| Tab block | short, width 300 | 46 px | 50 px | 1.09 |
| Tab block | 4 long lines, width 100 | 106 px | 122 px | 1.15 |
| Inline directive | short, width 300 | 30 px | 36 px | 1.20 |
| Inline directive | long value, width 150 | 238 px | 540 px | 2.27 |
| Leading directive | short, width 300 | 44 px | 56 px | 1.27 |
| Leading directive | long, width 150 | 304 px | 560 px | 1.84 |
| Section header | short label, width 300 | 40 px | 60 px | 1.50 |
| Section header | long custom label, width 150 | 404 px | 660 px | 1.63 |

Every kind holds the one-sided contract. The two directive kinds' ratios
(2.27x, 1.84x) are the loosest in this document — the cost of reusing
`chordCharWidth` as a conservative proxy rather than measuring each
directive style's own char width — but loose is the acceptable failure
mode here; under is not. The whole-song fixtures (both measured under the
identity scaler, short section labels only) are unchanged by this round:
1082/1198 and 2574/2630, same as above.

Reducing the overshoot means making the modelled word packing agree more closely
with real text layout (trailing-space handling, the exact width the `Text` is given
inside its `ConstrainedBox`, and how a run's height is derived from its tallest
child). Any such work must keep the one-sided contract: a change that improves the
average ratio but lets a single fixture fall under the rendered height is a
regression, not an improvement, and the tests are written to catch exactly that.

Worth doing after the fit-layout **performance** regression test that the
repository review's section 10 still lists as missing: `resolveFitFontScale` runs a
24-iteration binary search over every line, and finer layout modelling adds work
inside that loop.
