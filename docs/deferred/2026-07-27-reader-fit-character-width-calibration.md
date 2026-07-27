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

Measured on the chord-heavy consistency fixture at 375 px: rendered 2574 px
against an estimate of 3388 px, a 31.6% overestimate. The same constant
overshoots bold chord glyphs enough that, on moderately chorded content, the
older estimator's *ignoring* of chord width partly cancelled the overshoot and
looked more accurate than the corrected one. That coincidence is why the
chord-width defect survived the first consistency test.

The failure direction is the safe one: an overestimate makes auto-fit choose a
smaller font than strictly necessary, where an underestimate would let content
overflow the viewport. That is why this was not treated as a blocker.

Left out of the ui-decomposition-phase2 slice deliberately. Closing it means
calibrating a separate chord character-width constant (or measuring both styles
with a `TextPainter`) and re-deriving the bounds in
`song_reader_estimate_render_consistency_test.dart`, which currently pin 0.38
relative / 950 px absolute on the chord-heavy fixture. A `TextPainter` approach
has to be weighed against reader fit performance: `resolveFitFontScale` runs a
24-iteration binary search over every line, and the review's fit-layout
**performance** regression test is itself still missing.

The chord-heavy fixture uses 80-segment instrumental bars — deliberately beyond
anything a real song contains, chosen so the bound reacts to the estimator's
behaviour rather than to fixture noise. Real-world error is smaller than the
pinned bound.
