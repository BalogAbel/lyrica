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
| chord-only instrumental bar (fontScale 1.0) | 194 px | 194 px | 1.00 |
| plain wrapping lyric line (fontScale 1.0) | 610 px | 881.4 px | 1.44 |
| plain wrapping lyric line (fontScale 1.3) | 488 px | 622.74 px | 1.28 |

Pre-fix, the same three cases were RED: chord-only bar 194 rendered vs. 130
estimated (a genuine under-estimate — the exact failure mode this round
exists to close), plain lyric line 610 vs. 566.4 (also under), and the
fontScale-1.3 case 488 vs. 732.72 (over the ceiling, i.e. wrong in the other
direction once `sharedFontScale != 1.0` is in play). The whole-song fixtures
(both measured under the identity scaler at fontScale 1.0) were unaffected —
their numbers above are unchanged post-fix, since `SongReaderFitTextScale`'s
default (`TextScaler.noScaling`, base sizes 16/14/22/12) reduces to the
pre-fix arithmetic exactly when the scaler is linear.

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
