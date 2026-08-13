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

Fixed (first pass) by modelling chord self-wrap in `song_reader_fit.dart`'s
`_segmentRowHeight`: a segment's chord occupied
`ceil(chordWidth / effectiveLineWidth)` chord rows (using the chord style's
own per-style factor), the same way an over-long lyric word already occupied
`ceil(wordWidth / effectiveLineWidth)` lines. This first pass reasoned that a
chord label has no spaces to break on in the general case (extended/slash
chords have no reliable word boundary), so an even division was the right
model here, unlike lyric text, where word-boundary-aware greedy packing was
needed — **this reasoning was wrong** (see the sixth-round section below: a
chord label CAN contain a space, and the even-division model was replaced
outright, not kept alongside the word-wrap one). The run/group height
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

## Chord label containing a space (2026-07-28, sixth review round)

A sixth review round found the chord self-wrap fix above still undercounts
whenever the chord label itself contains a space: `N.C.` plus a performance
annotation (`N.C. (fade out)`), a capo note (`C (capo 2)`), or any label a
caller passes through `displayChord` can carry one, and Flutter's `Text`
breaks at a space the same as it does anywhere else. The even-division
model — `ceil(chordWidth / effectiveLineWidth)` over the label's TOTAL
width — does not know that. Reproduction: `"C CCCCCCCCCC"` (a short leading
word, then a run of `C`s wider than the column on its own) at a 130px
column renders 3 rows ("C" takes its own row, then "CCCCCCCCCC" wraps onto
two more), while even division saw only `ceil(169.2 / 130) = 2` — one row
short, a genuine under-estimate of exactly the kind `resolveFitFontScale`
must never produce.

Fixed by replacing the even-division branch outright with
`_wordWrapLineCount` — the same greedy word-boundary model
`_segmentIntraLines` already uses for the lyric text below the chord, and
that the comment/inline-directive/leading-directive/section-header kinds
already use (see "Full-kind sweep" below) — measured with the chord style's
own char width and factor. This is not a trade-off kept alongside the old
model: it strictly subsumes it. A chord label with no space is a single
"word" to `_wordWrapLineCount`, and for a single word wider than the line
that helper already falls back to exactly the same
`ceil(wordWidth / effectiveLineWidth)` division the old code used — every
case the even-division branch got right, the word-wrap model reproduces
exactly, and the only cases it changes are the ones the even-division
branch got wrong. There is no shape of chord label the old model handled
better, so there is no reason for two code paths.

A repo-wide check confirmed this was the only remaining even-division site
over text that can contain a space: comment lines, both directive kinds,
and the section header already used `_wordWrapLineCount` (see "Full-kind
sweep" below); tab blocks scroll rather than wrap and were never a
candidate; the one other `.ceil()` division left in `song_reader_fit.dart`
is `_wordWrapLineCount`'s own oversized-single-word sub-case, which is
correct by construction since a "word" (already split on spaces) contains
no space by definition.

Measured, no custom `TextScaler`, at a 130px column (above the 120px clamp
floor, same reasoning as the self-wrap fix above):

| Line shape | Rendered | Estimated | Ratio |
|------------|----------|-----------|-------|
| `"C CCCCCCCCCC"` (reviewer's repro) | 72 px | 72 px | 1.00 |
| `"N.C. (fade out)"` (realistic annotation) | 72 px | 72 px | 1.00 |

Pre-fix, both were RED: 72 rendered vs. 52 estimated in both cases — the
chord-row contribution was undercounted by exactly one `chordRowHeight`
(20px) because even division saw 2 rows over the label's total width where
the real render, breaking at the space, needed 3. Both fixtures land on an
exact match post-fix; this is not guaranteed in general (real Flutter line
breaking can, at some widths, pack part of an over-wide word onto the
preceding line rather than starting it fresh — a real quirk of the line
breaker, not a defect in the greedy model, which only needs to stay at or
above the render). No other fixture in either consistency test file moved:
none of their chord labels contain a space, and a single-word label reduces
to the exact same arithmetic as before.

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

## Breakable whitespace beyond a plain ASCII space (2026-07-28, seventh review round)

A seventh review round found `_wordWrapLineCount` (song_reader_fit.dart) split on
`' '` — the ASCII space only — while Flutter's real line breaker also breaks at TAB
and at several Unicode space-separator characters, and treats some characters as
MANDATORY breaks (the line ends right there regardless of remaining width) rather
than mere break opportunities. `text.split(' ')` does not recognize any of these, so
a "word" containing one was measured as a single unbreakable token — the same
under-estimate shape the sixth round closed for a literal space, reproduced through
a different separator. Reproduction (the reviewer's repro): `C\tCCCCCCCCCC` at a
130px column rendered 72px, estimated 52px.

Every candidate separator was measured empirically with a real `TextPainter`
(`song_line_view_estimate_consistency_test.dart`'s probe) before being used in a
fixture, per "check `TextPainter` behaviour empirically, don't assume from the
Unicode category" — this mattered, because assumption would have been wrong twice
over:

- **Breaks, confirmed via `TextPainter.getLineBoundary`**: TAB, and the Unicode
  space separators U+00A0 (NO-BREAK SPACE), U+1680, U+2000-U+200A, U+200B (ZERO
  WIDTH SPACE), U+202F (NARROW NO-BREAK SPACE), U+205F, U+3000 (IDEOGRAPHIC SPACE).
  Every one of these places the same trailing-whitespace line boundary a plain
  ASCII space does — including U+00A0 and U+202F, whose names suggest they should
  NOT be break points; Flutter's line breaker does not special-case either.
- **Does NOT break at all**: a bare `\r` with no following `\n` — glued to its
  neighbours, no break opportunity whatsoever (confirmed the same way).
- **MANDATORY break** (line ends immediately after the preceding content, the
  separator consumed as the terminator, next content starts a fresh line
  regardless of remaining width): `\r\n` (as a single unit — a bare `\r` is not
  itself a break, so `\r\n` must match before a lone `\n` or it would double-count),
  a lone `\n`, and — confirmed to behave identically to `\n` — U+2028 LINE
  SEPARATOR and U+2029 PARAGRAPH SEPARATOR. A double mandatory break (`AAAA\n\nBBBB`)
  produces 3 real lines, not 2: the empty chunk between two mandatory breaks still
  occupies its own blank visual line.

A second, separate empirical finding, NOT modelled (because it only ever loosens
the estimate, never breaks the one-sided contract): among the confirmed-breaking
characters, U+00A0 and U+202F specifically — the two "no-break"-branded ones —
additionally let Flutter's real layout "steal" trailing characters of a following
over-wide run across the break to fill the remaining line width (confirmed via
`getLineBoundary`: a three-word run split as `"CCCCCCC␠CCCC"` / `"CCC␠CCCCCCC"`,
not on a word boundary). Real Flutter's line count for these two characters,
in every width/shape tried, converged on the SAME theoretical minimum
(`ceil(totalWidth / lineWidth)`) the OLD buggy fallback already computed — so
fixtures built around U+00A0 or U+202F specifically did not reproduce a red
under-estimate at all (the same "plausible-looking fixture doesn't reproduce"
lesson as the sixth round), even though both characters genuinely break. TAB and
every other tested Unicode space do not exhibit this stealing and reproduce the
defect reliably. U+3000 IDEOGRAPHIC SPACE (a real character, not synthetic) was
used in the fixture below instead of U+00A0 for exactly this reason.

Fixed by splitting `_wordWrapLineCount` into two passes: `text.split` on a
`_mandatoryLineBreak` pattern (`\r\n|\n|U+2028|U+2029`) first, summing each
resulting chunk's own line count (a new `_greedyWrapLineCount` helper, same
algorithm as before) — a mandatory break can never be undone by available width, so
each side is wrapped independently and never packed onto the same line as the
other. Within each chunk, words are now split on a `_breakableWhitespace` character
class (space, tab, and the confirmed Unicode space separators, U+2000-U+200B as one
contiguous range) instead of a literal `' '`. One helper, used by every kind that
already used `_wordWrapLineCount` (lyric segment, chord label, comment, both
directive kinds, section header) — no chord-specific fork.

Measured, no custom `TextScaler`, fontScale 1.0:

| Case | Rendered | Pre-fix estimated | Post-fix estimated | Post-fix ratio |
|------|----------|--------------------|---------------------|-----------------|
| Chord label with internal TAB (`C\tCCCCCCCCCC`), width 130 | 72 px | 52 px **RED** | 72 px | 1.00 |
| Lyric segment with internal U+3000 (`C　CCCCCCCCCC`), width 150 | 72 px | 60 px **RED** | 84 px | 1.17 |
| Lyric segment with embedded `\n` (`Verse\nChorus`, no ASCII space at all), width 300 | 52 px | 36 px **RED** | 60 px | 1.15 |

All three were RED pre-fix and are at or above the render post-fix. The TAB case
lands exact (its shape happens to line up with the greedy model's row boundaries,
same caveat as the sixth round's exact matches — not guaranteed in general). The
U+3000 case is looser (1.17x) because the greedy model does not attempt Flutter's
character-stealing optimization noted above; that costs a slightly smaller
auto-fit font size, the same acceptable trade-off as every other fixture in this
document.

Every pre-existing fixture in all three consistency test files
(`song_line_view_estimate_consistency_test.dart`,
`song_reader_block_estimate_consistency_test.dart`,
`song_reader_estimate_render_consistency_test.dart`) was re-measured against the
fixed code and none moved: `_breakableWhitespace`'s character class includes the
literal ASCII space as one alternative, and none of the pre-existing fixtures'
text contains TAB, a Unicode space, or an embedded mandatory break, so
`text.split(_breakableWhitespace)` produces byte-for-byte the same split as the old
`text.split(' ')` for every one of them — confirmed both by re-running the full
suite (no ceiling needed to change) and by spot-checking representative fixtures
from each file directly (the two whole-song fixtures: 1082/1198 and 2574/2630,
unchanged; every block-kind fixture in `song_reader_block_estimate_consistency_test
.dart`, unchanged; a sample of `song_line_view_estimate_consistency_test.dart`'s
plain-space fixtures, unchanged).

### VERTICAL TAB / FORM FEED follow-up (2026-07-28, same round, coordinator review)

The sweep above deliberately scoped `_mandatoryLineBreak` to `\n`, `\r\n`, and the
Unicode line/paragraph separators, and flagged (rather than silently fixed) that
U+000B (VERTICAL TAB) and U+000C (FORM FEED) were ALSO measured to force a break
identical to `\n` — `TextPainter.getLineBoundary` places both characters' line
boundary immediately after the preceding content, and a doubled occurrence of
either produces a genuine blank line the same way `AAAA\n\nBBBB` does. Neither is
expected in ChordPro-parsed song text, which was the reason given for leaving them
out initially.

Coordinator's call: close the gap anyway. This helper's contract is an upper bound
over arbitrary strings, not over trusted input, and every round of this review
sequence has turned somebody's "real data won't contain it" into the next round's
finding — two characters in a regex is cheap insurance against repeating that
pattern a third time. Both are now in `_mandatoryLineBreak` alongside `\n`, `\r\n`,
U+2028, and U+2029.

Reproduction, isolated the same way as the `\n` case above (no ASCII space
anywhere in the text, so the old code saw one comfortably-fitting "word"):
`Verse\u000BChorus` (U+000B written out for readability; the actual character is a literal VERTICAL TAB) at a 300px column.

| Case | Rendered | Pre-fix estimated | Post-fix estimated | Post-fix ratio |
|------|----------|--------------------|---------------------|-----------------|
| Lyric segment with embedded U+000B (`Verse\u000BChorus`), width 300 | 52 px | 36 px **RED** | 60 px | 1.15 |

RED pre-fix, identical numbers to the `\n` case post-fix (as expected — U+000B is
now handled by the exact same code path). Only U+000B is exercised by a test;
U+000C was measured with the same `TextPainter` probe and behaves identically in
every respect that matters to this helper (same line-boundary placement, same
double-occurrence blank-line behavior), so a second, functionally-identical test
would prove nothing additional. Re-ran all three consistency files and the full
suite after this change: still green, no ceiling moved.

Still unverified by a dedicated render-vs-estimate test in this file (measured via
`TextPainter` only, or not measured at all): U+1680 (OGHAM SPACE MARK), U+2000
through U+200A individually (only the aggregate range and U+200B were exercised via
fixtures — U+3000 and TAB stand in for the class), U+205F (MEDIUM MATHEMATICAL
SPACE), and U+00A0/U+202F's "stealing" behavior at widths other than the ones
tried. None of these are expected to differ from the group they were measured
alongside, but "expected not to differ" is exactly the kind of claim this review
sequence keeps finding exceptions to, so it is recorded here rather than implied.


## Standalone `\r` and U+0085 NEXT LINE: host vs. web disagree (2026-07-28, eighth review round)

The seventh round measured a bare `\r` (no following `\n`) as NOT a break at all on
the HOST text stack — `TextPainter.getLineBoundary` (run via `flutter test`,
default platform) showed it glued to its neighbours, no break opportunity
whatsoever, and it was deliberately left out of both `_mandatoryLineBreak` and
`_breakableWhitespace` on that basis.

An eighth round pointed out that measurement was host-only, and this app ships to
Flutter WEB too (there is a Cloudflare Pages deployment of this branch). Verified
empirically rather than assumed — `flutter test --platform chrome
test/presentation/song_reader/song_line_view_estimate_consistency_test.dart` runs
cleanly against a real Chrome (Chrome 150, via `CHROME_EXECUTABLE`), and a temporary
scratch probe (rendered once, in both directions, then deleted — never committed;
per "do not add a chrome-only test file to the repo") measured a standalone `\r`
and a standalone U+0085 in real Chrome, run twice: once with the pre-fix estimator
(HEAD's committed code, via a single-file `git stash`) and once with the fix
applied.

Chrome forces a break at both characters, identically to `\n` — the host text
stack does not. This is a genuine cross-platform disagreement in what counts as a
mandatory break, not a measurement error on either side.

**Fixed by adding both to `_mandatoryLineBreak` unconditionally** (no `kIsWeb`
check, no platform fork): this helper's contract is an upper bound
(`estimated >= rendered`) over whatever platform actually renders the text, and the
mandatory set is therefore the UNION of every character any target platform treats
as a forced break. A union is always safe under an upper-bound contract — treating
a character as mandatory when some platform doesn't actually break there can only
ever ADD estimated lines, never remove them, so it can never turn a safe estimate
into an under-estimate on any platform. A per-platform set would not have this
property (the same estimator code runs everywhere and must stay safe everywhere at
once), so the union is not just simpler than a platform fork, it is the only choice
that is provably correct without one.

`\r\n` was already listed before the lone `\n` in the pattern for the same
single-match-per-pair reason (see the seventh round's note above); adding a lone
`\r` alternative requires it to also come before that new alternative, or a CRLF
pair matches `\r` alone first, leaves the `\n` to match separately immediately
after, and splits into three chunks instead of two — an over-estimate (safe under
the contract) but still the wrong line count for a single CRLF pair. Final order:
`\r\n|\r|\n|U+2028|U+2029|U+0085|U+000B|U+000C`. Pinned by a dedicated ordering test
in `song_reader_fit_test.dart`'s "eighth review round" group, plus two pure unit
tests asserting the standalone-`\r` and standalone-U+0085 forced-break line counts
directly — all three are host-runnable (`flutter test`, no chrome flag), so
`scripts/verify.sh` actually enforces them, unlike a chrome-only fixture would.

Measured (host, `flowBlockHeight` directly, width 300, single lyric segment, no
chord — `lyricRowHeight * lines + lineGap + lineWidgetBottomPadding = 24*lines+12`):

| Case | Pre-fix estimated | Post-fix estimated |
|------|--------------------|----------------------|
| `A\rB` (standalone `\r`) | 36 px (1 line) | 60 px (2 lines) |
| `A[U+0085]B` (standalone NEL) | 36 px (1 line) | 60 px (2 lines) |
| `A\r\nB` (CRLF, ordering pin) | 60 px (2 lines, unchanged) | 60 px (2 lines, unchanged — proves the ordering fix didn't regress the already-correct CRLF case) |

Measured (real Chrome render, same shape as the seventh round's `\n`/U+000B
fixtures, width 300):

| Case | Rendered | Pre-fix estimated | Post-fix estimated | Post-fix ratio |
|------|----------|--------------------|----------------------|-----------------|
| standalone `\r` (`Verse\rChorus`) | 52 px | 36 px **RED (under)** | 60 px | 1.15 |
| standalone U+0085 (`VerseChorus`) | 52 px | 36 px **RED (under)** | 60 px | 1.15 |

Both were a genuine under-estimate pre-fix on Chrome specifically — the exact
failure mode `resolveFitFontScale` exists to prevent, on a platform this app ships
to — and both are fixed with the same numbers as the seventh round's `\n`/VT
cases post-fix (1.15x ratio), since all of them now go through the identical
mandatory-break code path.

Re-ran all three consistency test files
(`song_line_view_estimate_consistency_test.dart`,
`song_reader_block_estimate_consistency_test.dart`,
`song_reader_estimate_render_consistency_test.dart`) plus `song_reader_fit_test.dart`
and `song_reader_fit_to_screen_test.dart` on host after this change: 77 tests, all
green, no ceiling moved — none of the pre-existing fixtures' text contains a
standalone `\r` or U+0085, so `_mandatoryLineBreak`'s new alternatives never fire
for them.

### Separator classification, by verification method (running tally)

To keep straight what's actually been checked and how, rather than implied:

- **Host-verified via `TextPainter` (`flutter test`, default platform)**: `\n`,
  `\r\n` (as a unit), U+2028, U+2029, U+000B, U+000C (all mandatory, seventh round);
  ASCII space, TAB, U+00A0, U+1680, U+2000-U+200A, U+200B, U+202F, U+205F, U+3000
  (all breakable-opportunity, seventh round); a standalone `\r` was measured as
  glued (NOT breaking) on host, same round.
- **Web-only per this (eighth) review round, measured in real Chrome, NOT
  confirmed to break on host**: standalone `\r`, U+0085 NEXT LINE — both
  mandatory on Chrome, glued/unmeasured-as-breaking on host. This is the one
  documented case in this file where host and web genuinely disagree.
- **The mandatory and breakable-whitespace sets are each a deliberate UNION across
  every target platform**, not a value tuned to any one platform's text stack. A
  character is added to a set the moment ANY target platform is measured (or
  reasonably known) to treat it that way, because a union can only ever tighten
  the "forced break" side of the estimate (more lines counted, never fewer) —
  which is always safe under this file's `estimated >= rendered` upper-bound
  contract. This is also why no `kIsWeb` branch exists anywhere in
  `_mandatoryLineBreak` or `_breakableWhitespace`: a per-platform fork would not
  have the union's safety property, since the same estimator code must stay a
  valid upper bound on every platform it runs on, not just the one it happened to
  be tuned against.

### Web test lane: not added, cost noted for a human decision

`scripts/verify.sh` runs `flutter test` on the host only; a `--platform chrome`
lane is not part of CI for this repo today. This round's Chrome run (see above)
worked without any project changes — Chrome is already recognized by `flutter
doctor` on this machine, and no `--web-renderer` or extra flags were needed beyond
`CHROME_EXECUTABLE`. Cost of making that permanent: CI would need Chrome available
(either a hosted-runner-provided browser or downloading one), a slower job (Chrome
headless startup adds real wall-clock time per run, and this repo's fit-estimator
suite alone is dozens of widget-pump tests), and, if any web-only fixture besides
`\r`/U+0085 shows up later, ongoing maintenance of a platform-specific fixture set
alongside the host-only one. Given this round found exactly two characters where
host and web disagree across four rounds of increasingly aggressive separator
hunting, and the fix for both was a one-line regex addition covered entirely by
host-runnable unit tests, a dedicated CI web lane does not currently look
justified by the defect rate — but that is a call for a human to make with the CI
budget in view, not something to fold into this PR.

## Word-boundary splitting (2026-08-10)

> **2026-08-11:** `splitSegmentsAtWordBoundaries`'s chord-assignment rule
> changed after this section was written (a duplicate-chord bug found by
> visual verification — see `docs/specs/2026-08-09-song-presentation.md`,
> "Amended 2026-08-11"). The render/estimate numbers below are unaffected
> (the chord label was never the wider side of the affected pieces), but the
> chord semantics they were measured under did change.

### What changed

The reader's wrapping unit became the **word** rather than the ChordPro segment
run. `splitSegmentsAtWordBoundaries` (`song_reader_word_groups.dart`) cuts each
segment's text at its own internal breakable whitespace before
`groupSegmentsIntoWords` runs, and **both** the renderer
(`widgets/song_line_view.dart`) and the estimator (`song_reader_fit.dart`) call
the pair in that order — pinned by a source-inspection guard in
`song_reader_word_groups_test.dart` so the two layers cannot drift apart.

This closes the mid-word break defect (`docs/specs/2026-08-09-song-presentation.md`,
"Defect pulled into scope"): at 375px the reader rendered `Igé` / `dben bízok én`,
because grouping worked at segment granularity and a segment's *internal*
whitespace was never a break opportunity.

### The real root cause of the round's RED fixture: the effective-width clamp

Task 3's framing — that the split simply buys "more per-group packing slack" — was
incomplete, and the new fixtures found why. A three-segment single word
(`al` + `ph` + `a beta`, chord on each) measured at a **90px** column came back
`rendered=136 estimated=92`: an under-estimate, the one failure mode this whole
estimator exists to prevent.

The cause was **not** the char-width model. That model was verified directly
against `TextPainter` for exactly these strings and is *exact* here (`'al'` 33.0
real vs 33.0 estimated; `'beta'` 66.0 vs 66.0; `'Am'` 28.2 vs 28.2), which
disproves the standing "short strings under-measure because per-glyph overhead is
amortized over fewer characters" hypothesis for this case.

The cause was `columnWidth.clamp(120.0, 1200.0)`, applied at all three
`effectiveLineWidth` sites in `song_reader_fit.dart`. The two bounds are **not**
symmetric under a one-sided contract:

- modelling a **narrower** line than the renderer really gets can only add
  estimated wraps → estimate moves **up** → safe;
- modelling a **wider** line than the renderer really gets removes estimated wraps
  → estimate moves **down** → straight through the contract floor.

The 120px *lower* bound is the unsafe direction, and it silently modelled a 120px
line for every narrower column. At 90px the `alpha` group measures 99px: under a
120px model it fits on one row, while the real 90px column splits it across two.
The renderer applies no such floor — `SongLineView` lays out at whatever
`constraints.maxWidth` it is handed.

**Fixed** by lowering the floor to `minEffectiveLineWidth = 1.0`, a pure numeric
guard (at width 0 the oversized-word branch of `_greedyWrapLineCount` evaluates
`(wordWidth / 0).ceil()` on an infinity and throws; a negative width makes the
greedy packing loop meaningless) that can never *raise* a real column width. The
1200px upper bound is kept as `maxEffectiveLineWidth`: it only ever over-estimates.

This bug **pre-dates this PR** — it is not fallout from word splitting. Measured on
`main`'s reader library, the same 90px fixture gives `rendered=126 estimated=114`
(ratio 0.905), already RED. Word splitting only produced the first fixture narrow
enough to expose it. Note that an earlier round had already *worked around* the
clamp rather than fixing it: the "N.C. (fade out)" fixture's comment explicitly
pins its width at 130 to stay "above the 120px clamp floor". That comment is now
corrected.

### Measured (2026-08-10, host, `MaterialApp` default `ThemeData`, fontScale 1.0)

The three new fixtures in `song_line_view_estimate_consistency_test.dart`:

| Line shape | Rendered | Estimated | Ratio |
|------------|----------|-----------|-------|
| reproduction — `'…Igé'` + `'dben bízok én'`, chords `E`/`G#m`, width 375 | 136 px | 148 px | 1.09 |
| one word across three segments — `'al'`/`C` + `'ph'`/`G` + `'a beta'`/`Am`, width 90 | 136 px | 148 px | 1.09 |
| single unbreakable 38-char word, no chord, width 130 | 132 px | 132 px | 1.00 |

Same fixtures against `main`'s reader library, for the before/after:

| Line shape | `main` rendered | `main` estimated | `main` ratio | This PR rendered | This PR estimated | This PR ratio |
|------------|-----------------|------------------|--------------|------------------|-------------------|---------------|
| reproduction, width 375 | 126 px | 138 px | 1.10 | 136 px | 148 px | 1.09 |
| three-segment word, width 90 | 126 px | 114 px | **0.90 — RED (under)** | 136 px | 148 px | 1.09 |
| unbreakable 38-char word, width 130 | 132 px | 132 px | 1.00 | 132 px | 132 px | 1.00 |

**Overshoot held.** The ratios did not worsen: 1.10 → 1.09 on the reproduction,
unchanged at 1.00 on the unbreakable word, and the third case moved from an unsafe
0.90 to a safe 1.09. No pre-existing fixture's ceiling was loosened; the
reproduction fixture's ceiling was *tightened* from a provisional 1.4x to 1.1x once
the real numbers were known. This document's subject — the estimator's deliberate
conservatism — is **not** resolved by this PR.

### Side effect that is real, and not a regression to hide: wrapped lines got taller

A lyric line is now one box **per word** in the outer `Wrap`, where a single-segment
line used to be one `Text` that wrapped internally. So the renderer's 10px
`lineRunSpacing` now applies between a line's *own* wrapped rows, at plain text
leading before. Measured on a long single-segment chorded line:

| Column width | `main` rendered | This PR rendered | Delta |
|--------------|-----------------|------------------|-------|
| 380 px (3 wrapped rows) | 114 px | 144 px | +30 px (+10 px per wrap) |
| 760 px (1 wrapped row) | 74 px | 84 px | +10 px |

This is not new behaviour so much as **newly consistent** behaviour: on `main` a
line that happened to contain whitespace at a segment boundary already became
several groups in the outer `Wrap` and already wrapped with the 10px run spacing.
Only lines that collapsed into a single group — exactly the ones carrying the
mid-word-break defect — wrapped tightly. The estimator models the increase
correctly (`estimated >= rendered` holds throughout), and
`song_reader_section_grid_test.dart`'s "uses two columns when wrapped lyrics
overflow single-column height" fixture was re-tuned from `availableHeight: 420` to
`540` for this reason, with the measurement recorded in its comment.

On a phone, where most lines wrap, this adds roughly 10px per wrapped row to total
song height. **Whether that leading is the right typography is a PR3/PR4 question,
not this PR's** — this PR's job is where lines may break. Flagged here so the
type-scale work does not rediscover it as a mystery.

## Type scale (2026-08-13, PR3)

Re-measured under this PR's type scale
(`docs/specs/2026-08-09-song-presentation.md` section 1): 22/19px lyrics at
`w500`, 15/13px chords in a 3px-padded tinted chip, uppercase letter-spaced
15/13px section labels, `lineRunSpacing` 10 → 2, and a 600px viewport
breakpoint switching between the two sets. **This item is still open** — the
estimator stays a deliberate upper bound; nothing below resolves it.

This PR also found and fixed two real (`estimated < rendered`) defects,
unrelated to the type scale's numbers but surfaced while re-measuring against
it:

- **Per-row pixel rounding.** Real text layout rounds each wrapped row's
  height to a whole logical pixel, per row, not once over a multi-line block.
  Under a non-linear text scaler the estimator's raw
  `rows * rowHeight * factor` product can be fractional, and the real render's
  per-row rounding pushes the true height above that fraction whenever it
  rounds up. Fixed by ceiling each row's modelled height before multiplying by
  row count (`_scaledRowHeight` in `song_reader_fit.dart`) — safe because
  `ceil(x) >= round(x)` unconditionally.
- **Character quantisation of an unbreakable word.** `_greedyWrapLineCount`'s
  oversized-word branch used to divide continuously
  (`ceil(wordWidth / effectiveLineWidth)`), modelling a line that can end
  mid-glyph. Real line breaking cannot split a glyph, so a line holds
  `floor(effectiveLineWidth / charWidth)` whole characters and the true row
  count is `ceil(charCount / charsPerLine)`, which is always `>=` the
  continuous form. Fixed to quantise at character boundaries.

Both fixes only ever move an estimate up or leave it unchanged; neither
touched a rendered value. With both landed, no lower-bound failure remains
anywhere in the three consistency suites as of this PR.

Every ceiling below is re-measured against the wired, breakpoint-resolved
metrics on both sides (a fixture that resolves the estimate from
`SongReaderMetrics.legacy` while the render uses the resolved tokens is not a
consistency check — see the per-fixture comments in the test files for the
"wired 2026-08-12" note where that gap existed transiently during this PR).

| suite | fixture | old rendered | old estimated | old ratio | new rendered | new estimated | new ratio |
|---|---|---|---|---|---|---|---|
| block | comment: short comment, wide column | 30.0 | 34.0 | 1.13 | 26.0 | 54.0 | 2.08 |
| block | comment: long comment, narrow column | 410.0 | 586.0 | 1.43 | 406.0 | 750.0 | 1.85 |
| block | inline directive: long value, narrow column | 238.0 | 540.0 | 2.27 | 234.0 | 648.0 | 2.77 |
| block | leading directive: long capo/tuning, narrow column | 304.0 | 560.0 | 1.84 | 298.0 | 626.0 | 2.10 |
| estimate/render | whole-song plain fixture, content height | 1082.0 | 1198.0 | 1.11 | 1066.0 | 1080.0 | 1.01 |
| estimate/render | whole-song chord-heavy fixture, content height | 2574.0 | 2630.0 | 1.02 | 1732.0 | 1746.0 | 1.01 |
| estimate/render | whole-song plain fixture, tablet-portrait (834x1194, regular set) — new fixture, no prior measurement | — | — | — | 778.0 | 792.0 | 1.02 |
| line-view | single-segment line, several wraps | 434.0 | 514.0 | 1.18 | 592.0 | 832.0 | 1.41 |
| line-view | chord label with internal space | 72.0 | 72.0 | 1.00 | 44.0 | 62.0 | 1.41 |
| line-view | chord label with internal TAB | 72.0 | 72.0 | 1.00 | 44.0 | 62.0 | 1.41 |
| line-view | plain lyric line, 1.5x linear text scaler | 610.0 | 1026.0 | 1.68 | 606.0 | 1300.0 | 2.15 |
| line-view | non-linear scaler + 1.3 sharedFontScale | 610.0 | 925.6 | 1.52 | 606.0 | 1064.0 | 1.76 |

The whole-song ratios *tightened* (1.11 → 1.01, 1.02 → 1.01): the estimate
side now scales its row-height guesses by the same resolved metrics the
render actually used, closing a gap that used to come from comparing a
resolved-metrics render against a `SongReaderMetrics.legacy`/identity-scale
estimate — not from the type scale itself. Several per-line ratios *loosened*
substantially (up to 2.77x on the long inline directive): the reader's new
row heights are smaller in absolute terms (18/16 chord rows, 6px line gaps
against 20/10 before), so a fixed per-fixture overshoot in pixels is now a
larger fraction of a smaller rendered height. The type scale does not move
every fixture in the same direction — treat these per-fixture, not as one
global trend.

Two changes tightened the model in the safe direction rather than loosening
it: the chord chip's padding is now charged per drawn chord (previously
absent, an under-estimate risk this PR closed rather than opened — see
`_segmentPixelWidth`'s `chordChipHorizontalPadding` term), and the section
label is modelled as the uppercased string it is actually drawn as (previously
the mixed-case source, also an under-estimate risk this PR closed). Where a
margin above looks unexpectedly tight, it is because the estimate got MORE
accurate, not because the floor moved.
