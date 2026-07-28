# Reader fit: one character-width constant for two text styles

Related:
- `apps/lyron_app/lib/src/presentation/song_reader/song_reader_fit.dart`
- `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_line_view.dart`
- `apps/lyron_app/test/presentation/song_reader/song_reader_estimate_render_consistency_test.dart`
- `docs/specs/2026-07-27-ux1-reader-wrap-and-ux2-date-picker.md`

The fit estimator derives every width from a single `characterWidthEstimate`
(10 px per character, scaled by the font scale). The renderer draws lyrics in
`bodyLarge` and chords in `labelLarge` with `FontWeight.w700` — two different
styles with different glyph widths — so one constant cannot be right for both.

Measured at 375 px, after the second review round corrected the run and
intra-segment wrap accounting:

| Fixture | Rendered | Estimated | Error |
|---------|----------|-----------|-------|
| Plain | 1082 px | 1010 px | 6.7% **under** |
| Chord-heavy | 2574 px | 3378 px | 31.2% **over** |

The two errors point in opposite directions, which is the signature of a single
constant serving two styles: it overshoots bold chord glyphs and undershoots
lyric glyphs. The overshoot is the safe direction (auto-fit picks a smaller font
than needed); the 6.7% undershoot on plain content is the direction that can let
content overflow, which is why the residual is recorded rather than dismissed.

The same constant coincidence made the older, *more broken* estimator look more
accurate on the plain fixture (2.0%): its `ceil()` division over a group's total
width happened to approximate the intra-segment text wrap it did not model.
Removing that accident without replacing it regressed the plain fixture to 17.7%
under before the wrap model was added. Two separate defects hid inside one
number — worth remembering before anyone "simplifies" this code by a measured
error alone.

Left out of the ui-decomposition-phase2 slice deliberately. Closing it means
calibrating a separate chord character-width constant (or measuring both styles
with a `TextPainter`) and re-deriving the bounds in
`song_reader_estimate_render_consistency_test.dart`, which currently pin 0.15
relative / 160 px absolute on the plain fixture and 0.37 / 930 px on the
chord-heavy one. A `TextPainter` approach
has to be weighed against reader fit performance: `resolveFitFontScale` runs a
24-iteration binary search over every line, and the review's fit-layout
**performance** regression test is itself still missing.

The chord-heavy fixture uses 80-segment instrumental bars — deliberately beyond
anything a real song contains, chosen so the bound reacts to the estimator's
behaviour rather than to fixture noise. Real-world error is smaller than the
pinned bound.
