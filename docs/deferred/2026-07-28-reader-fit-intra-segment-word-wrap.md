# Reader fit: intra-segment wrap ignores word boundaries

Related:
- `apps/lyron_app/lib/src/presentation/song_reader/song_reader_fit.dart`
- `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_line_view.dart`
- `apps/lyron_app/test/presentation/song_reader/song_line_view_estimate_consistency_test.dart`

Supersedes `2026-07-27-reader-fit-character-width-calibration.md`, which is closed:
the lyric and chord character advances are now measured from the real text styles
with a `TextPainter` (`song_reader_char_metrics.dart`) instead of sharing one
guessed constant.

What remains: when a single segment's text is wider than the line, the estimator
counts its wrapped lines as `ceil(lyricWidth / effectiveLineWidth)`. Real text
layout breaks at **word boundaries**, so a line usually breaks earlier than an
even character-count division implies, and the rendered segment is taller than
the estimate.

Measured per line at 2026-07-28, against a real `SongLineView` render:

| Line shape | Rendered | Estimated | Error |
|------------|----------|-----------|-------|
| plain lyric line that wraps | 292 px | 250 px | 14.4% under |
| single segment wrapping several times | 434 px | 368 px | 15.2% under |
| wide chords over short syllables | 210 px | 224 px | 6.7% over |
| chord-only instrumental bar | 122 px | 120 px | 1.6% over |
| chord-split word | 54 px | 56 px | 3.7% over |

Only the two shapes that wrap *inside* one segment are affected, and they err in
the direction that can let auto-fit overflow. Aggregated over a whole song the
residual is smaller (the whole-song fixtures sit at 6.5% and 1.4%), because most
lines are not dominated by a single over-wide segment — which is also why this was
not treated as a blocker.

Closing it means modelling greedy word-boundary wrapping for a segment's own text:
split the text on spaces and pack the words, the same way the run packing already
packs groups. That is a bounded change to one function, but it makes the estimator
sensitive to the text content rather than only its length, so it needs the per-line
consistency test extended with word-length distributions before and after.

The fit-layout **performance** regression test named in the repository review's
section 10 is still missing and would be worth having first: `resolveFitFontScale`
runs a 24-iteration binary search over every line, and word-level packing adds work
inside it.
