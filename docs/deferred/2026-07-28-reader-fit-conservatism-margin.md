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
| plain wrapping line at text scaler 1.5 | 492 px | 660 px | 1.34 |
| whole-song plain fixture | 1082 px | 1198 px | 1.11 |
| whole-song chord-heavy fixture | 2574 px | 2630 px | 1.02 |

Lines that wrap inside a single segment are the loose end: up to ~1.34. Lines
dominated by chords are near-exact. Aggregated over a whole song the overshoot is
1.02-1.11, because most lines are not a single over-wide segment — so the practical
font-size cost is smaller than the worst per-line ratio suggests.

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
