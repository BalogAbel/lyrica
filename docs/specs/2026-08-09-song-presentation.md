# Song presentation: reader typography, theming and chrome

- Date: 2026-08-09
- Branch: `feat/song-presentation-phase7`
- Status: accepted (design agreed with the product owner before writing)

## Why

The song reader is the app's live surface: a musician reads it on stage, from a
tablet held in portrait, at arm's length. The current reader is legible but
wasteful. Measured against the reference app the product owner wants to replace
(SongBook, linkesoft), the same song rendered in Lyrica uses a **smaller font
and more vertical space at the same time**.

Measured at 834x1194 (tablet portrait), with the reference song:

| | reference | Lyrica today |
|---|---|---|
| chord+lyric pair height / lyric font size | ~2.5x | **3.63x** |
| side margin | ~10% | **~23%** |
| section label | lyric-sized, one line | `titleLarge` 22px on its own block |
| per-section vertical overhead | ~1 blank line | header 28 + 12 gap + 20 section gap = **60px** |

The 3.63x figure is not an estimate: it is exactly what
`song_reader_metrics.dart` and `song_reader_fit.dart` encode today
(`chordRowHeight 20` + `chordToLyricGap 2` + `lyricRowHeight 24` + `lineGap 10`
+ `lineWidgetBottomPadding 2` = 58px at a 16px lyric size).

The 23% side margin is not the 960px content cap. It comes from
`song_reader_compact_surface.dart`'s `Center` + `ConstrainedBox`: the section
grid is a `Column` with `crossAxisAlignment: start`, so under the loose
constraints `Center` passes down it **shrink-wraps to its own longest line** and
is then centred. Line wrapping still happens at the full available width, so
today this costs optical space rather than characters per line — but it also
means every section starts from a floating, content-dependent left edge.

A second, separate problem: there is no dark theme at all
(`MaterialApp.router` sets only `theme:`), which the repository review records as
UX-7 and justifies specifically by dim-stage use.

## Goals

1. Fit substantially more song on a tablet-portrait screen **while increasing**
   the lyric font size.
2. Ship a dark theme designed for a dim stage, not an inverted light palette.
3. Introduce a design-token layer so that the two themes are one system with two
   value sets, not two hardcoded palettes.
4. Restructure the reader chrome so that persistent state stays visible and
   transient controls do not consume layout space.
5. Keep the fit estimator a valid upper bound throughout.

## Non-goals

- **UX-6 (CanvasKit renderer / text selection / screen-reader support).**
  Confirmed present — the reader's DOM exposes no text — but this is a platform
  renderer decision needing measurement of bundle size, selection and a11y
  across CanvasKit vs. HTML/skwasm. It deserves its own phase and its own ADR.
- ChordPro in-song modulation (`docs/deferred/2026-04-22-song-reader-chordpro-modulation.md`).
  Untouched; the deferred doc stays as is.
- UX-4 song-list density.
- Left-handed mirroring of the control rail (see Open questions).
- Session items other than songs (see Assumptions).

## Assumptions

- **Sessions contain only songs.** `session_item_type` permits
  `song | attachment | note`, but `SessionItemSummary` requires a `SongSummary`
  and the RPC hardcodes `item_type = 'song'`. Confirmed with the product owner:
  the scoped reader's previous/next navigation may assume every item is a song.
  The schema headroom exists only because adding it later would have been
  painful. No note/attachment handling is implemented here.

## Design decisions

Every number below was chosen against a rendered mockup at 834x1194 and a real
measurement, not by eye. The mockups live outside the repo (session scratchpad)
and are not a deliverable; the numbers they produced are.

### 1. Typography and spacing

| token | tablet / desktop | phone (< 600 logical px) |
|---|---|---|
| lyric size | 22 | 19 |
| lyric weight | `w500` | `w500` |
| lyric row height | 24 | 21 |
| chord size | 15 | 13 |
| chord weight | `w700` | `w700` |
| chord row height | 18 | 16 |
| chord-to-lyric gap | 0 | 0 |
| line gap | 6 | 6 |
| section gap | 14 | 14 |
| section label size | 15 | 13 |
| section label row height | 20 | 18 |
| gap below section label | 4 | 4 |
| content padding | `12 horizontal, 14 vertical` | same |

Result at 834x1194: the whole reference song occupies **870px** of the
**1130px** available, with no line wrapping — against 1238px (overflowing) for
the same content under today's metrics.

Why 22 and not larger: the ceiling is set by **line length, not height**.
Measured, at 12px side padding, the largest lyric size at which no line of the
reference song wraps is **26px**; at 29px, three lines wrap and the song no
longer fits at all, because one wrapped line costs ~50px while the larger type
buys less than that. 22px is the base; auto-fit may raise it toward that
ceiling.

**`lineRunSpacing`: 10 → 2.** This value is not in the table above because it
did not exist as a type-scale decision until the word-boundary-wrapping PR
(#70) changed what it means. Before #70, a single-segment lyric line was one
`Text` that wrapped internally at plain text leading, and `lineRunSpacing`
only ever separated distinct `Wrap` children. Since #70 a line is one box per
word in the outer `Wrap`, so the same spacing now also lands between a single
line's OWN wrapped rows. Measured on a 380px column, one wrapped lyric line
went from **114px to 144px** at the old value of 10 — around 20-30px per line
on a phone, where wrapping is the normal state (see "Phone behaviour").

It is 2 rather than 0 because the new lyric leading is tight: `height` is
derived as `lyricRowHeight / lyricSize` (24/22 ≈ 1.09, against 1.25 before),
so wrapped rows would otherwise nearly touch. At 2 a continuation row sits
26px below its own line against 24 + 6 = 30px to the next line, so a wrap
still reads as closer to its own line than to the following one.

### 2. Chords: tinted chip

Chords render as a filled, low-contrast chip (`chordBg`) with a bold, coloured
label (`chordFg`), 3px horizontal padding, 3px corner radius, in **both**
themes. The chip is what lets a 15px chord stay readable from a distance while
its row height drops from 20 to 18, giving the space to the lyric.

A solid, fully saturated chip was rejected for the dark theme: on a black
surface it would be the brightest element on screen, pulling the eye away from
the text someone is singing. Consistency across themes was preferred over a
per-theme treatment.

### 3. Section labels

Uppercase, letter-spaced (`0.07em`), coloured, weight `w700`, at the label size
above. No chip, no background fill, no rule.

Four treatments were compared and the height difference across all four was
40px over an entire song — this is a look decision, not a density one. The
uppercase-plus-tracking form was chosen as the quietest of the four.

### 4. Horizontal layout

- Side padding drops to **12px**.
- The content is **left-aligned at a fixed edge**. The `Center` +
  `ConstrainedBox` shrink-wrap in `song_reader_compact_surface.dart` is removed,
  so every section starts from the same left edge regardless of the longest line.
- The 960px `maxContentWidth` cap is retained for wide desktop windows only; it
  does not bind at tablet widths.

Measured trade-off (largest non-wrapping lyric size by side padding, reference
song): 12px, 16px and 24px all yield 26px; 32-40px yields 25px; 48px yields
24px; 64px yields 23px. Below 24px there is no further gain **on this song**,
but shorter margins can only help songs with longer lines, never hurt them, so
12px was chosen.

### 5. Dark theme

The dark theme keeps a **pure black page** and moves the *text* down from white,
rather than lifting the background:

| role | light | dark |
|---|---|---|
| page background | `#F7F4EA` | `#000000` |
| bar surface | `#EFF3EA` | `#121411` |
| floating rail surface | `#E6E9DF` | `#1A1C18` |
| lyric text | `#1B1C18` | `#CDCAC0` |
| section label | `#0B6E4F` | `#6FA98D` |
| chord foreground | `#0B6E4F` | `#7ACFA8` |
| chord chip background | `rgba(11,110,79,0.13)` | `rgba(122,207,168,0.15)` |

Rationale, measured across four candidate dark palettes:

- Glare in a dark room is driven by **emitted light**, which comes from the
  text; a black background emits none. Lifting the background from `#000000` to
  `#121411` reduced emitted light by **0%** — both palettes measured 79%
  relative text luminance — while giving up true black.
- Dropping the text from `#E8E6DD` to `#CDCAC0` cut relative text luminance from
  79% to **59%** and still leaves **12.8:1** contrast, comfortably above the 7:1
  AAA threshold.
- A contrast *ratio* is the wrong metric for separating near-black surfaces: all
  four candidates landed within 1.08-1.15:1. Perceptual lightness reverses the
  conclusion — on a pure black page the app bar sits at ΔL\* 6.0 and the rail at
  ΔL\* 9.9, i.e. a black page leaves **more** headroom for elevation, not less.
- `#0B6E4F` (the light-theme green) is unusable on black at roughly 2:1. The
  accent is therefore two values, not one inverted value — which is the concrete
  reason a token layer is required rather than a second hardcoded palette.

**Switching between the themes.** Following the platform setting alone does not
serve the use case that justifies the dark theme at all: a stage tablet is in
light mode all day, and nobody leaves the app for the OS settings between two
songs. The reader's overflow menu carries a single entry that flips to the other
theme, and the choice is stored app-wide. Absence of a stored value means
"follow the system", so a user who never touches it keeps platform behaviour;
once they choose, the choice wins. There is deliberately no "back to system"
entry — a third state to explain, for a preference set once. An account-screen
setting is a reasonable later addition and is not built here.

A brightness step for the reader is **not** in this slice; `#B3B0A6`-level
dimming (9.7:1, 43% luminance) was rejected as a default because it is too faint
in daylight rehearsal.

### 6. Chrome

Three surfaces, with different persistence:

**Bottom bar — always visible, occupies layout space.** 64px on tablet, 58px
plus the home-indicator safe-area inset on phone. Contents:

- plan-scoped: previous item (chevron + title) | current title, key, capo,
  set position (`3 / 7`) | next item (title + chevron)
- catalogue: current title, key, capo, centred
- phone, plan-scoped: chevrons only, no neighbour titles

Capo appears only when `isCapoDirectiveVisible` is true, as today.

**Top bar — hidden by default, revealed by tapping the content, floats over
it.** Contents: back (leading edge, standard back symbol), song title, the
recoverable-warnings indicator, and the overflow menu. The title is deliberately
duplicated with the bottom bar; an empty title area was rejected by the product
owner.

**Control rail — hidden by default, revealed by the same tap, floats over the
content at the right edge.** Vertical groups: transpose -/value/+, capo
-/value/+, font A-/A+.

A second tap dismisses both. There is **no idle auto-hide**: on stage,
predictability beats tidiness — a control must not vanish while someone is
reaching for it.

Both floating surfaces **overlay** the content and are excluded from the fit
calculation's available height. This is a behaviour change: today's control bar
sits inside the `Column`, so revealing it resizes the content area.

Space recovered on tablet: today's chrome is 52 (app bar) + 143 (control bar +
context bar + gaps) = 195px, leaving 999px for the song. The new chrome is a
flat 64px, leaving **1130px** — **+131px**, roughly three extra lyric line
pairs.

#### Platform conformance

This structure was checked against Apple's current Human Interface Guidelines
rather than assumed:

- *Toolbars* places the navigation toolbar at the top of the window, with the
  element that returns to the previous view at the leading edge, and requires
  the standard back symbol rather than a "Back" text label. A back control in a
  bottom bar was therefore rejected. Note this is an HIG convention, not an App
  Review rejection criterion; the practical risk is the conflict with the
  system's left-edge back gesture and with user expectation.
- *Going full screen* (updated June 2025) explicitly endorses temporarily hiding
  toolbars and navigation controls when content is the focus, provided they can
  be restored by a familiar action such as tapping, and provided controls
  **essential to navigation** stay visible. Previous/next are essential during a
  service and stay in the fixed bottom bar; back is not needed mid-song and may
  hide. iOS's left-edge back gesture keeps back reachable even while the top bar
  is hidden.

### 7. Breakpoints and the expanded shell

The token sets in section 1 switch at a new **600 logical px** breakpoint
(phone below, tablet/desktop at or above). This is a third width threshold
alongside the two that already exist — `denseLayoutMinWidth` (1180, two-column
content) and the expanded shell's 1600 — and it lives with them as a named
constant, not inline in a widget.

The **expanded shell** (>= 1600 logical px, `SongReaderExpandedSurface` with its
side context and tools panels) is **not restructured** in this slice. It adopts
the tokens from sections 1, 2, 3 and 5, so its typography and both themes match
the compact shell, but it keeps its current chrome: the desktop layout has the
width to show panels permanently, and the stage problem this slice exists to
solve is a tablet-portrait problem. The chrome model in section 6 applies to the
compact shell only. If the two shells later need to converge, that is its own
slice.

### 8. Design-token layer

A `ReaderTheme` `ThemeExtension` carries every value in sections 1, 2, 3 and 5,
registered on both `ThemeData` instances built in `app/app_theme.dart`. Reader
widgets read tokens from the extension; no reader widget hardcodes a colour, a
font size or a spacing constant.

The spacing tokens the fit estimator depends on remain the single shared
constants they are today (`song_reader_metrics.dart`, and the height constants
in `song_reader_fit.dart`) — the token layer must not fork them into a second
copy. Whether the estimator reads them from the extension or the extension is
built from them is an implementation decision for the plan; what is fixed is
that exactly one definition exists per value.

This is an architectural change and gets an ADR. The dark theme closes UX-7 and
gets its own entry in the repository review's strike-through list; the chrome
model gets a second ADR.

## Invariants this work must not break

### The fit estimator upper bound

`resolveFitFontScale` picks the largest scale whose *estimated* height fits, so
an estimate below the rendered height lets fit-to-screen overflow — the exact
failure the feature exists to prevent. `estimated >= rendered` is asserted
one-sidedly by `song_line_view_estimate_consistency_test.dart`,
`song_reader_block_estimate_consistency_test.dart` and
`song_reader_estimate_render_consistency_test.dart`.

Every typography change in section 1 moves a constant the estimator mirrors.
Three of them are traps that will silently under-estimate if missed:

1. **Chord chips add width.** The chip's horizontal padding (3px each side) is
   part of the chord label's rendered width. `chordCharWidth`-based widths must
   include it, or a chord that wraps in the render will not wrap in the estimate.
2. **Section labels are uppercased and letter-spaced.** `headerCharWidth` is
   measured today from `titleLarge` with no tracking. It must be re-measured
   from the new label style **with `letterSpacing` applied and against the
   uppercased string**, since both change glyph advance.
3. **Lyrics move to `w500`.** `lyricCharWidth` must be measured at the new
   weight; a heavier face is wider than the `w400` measured today.
4. **A row-height token and its text style must agree.** The estimator charges
   `lyricRowHeight` / `chordRowHeight` / `sectionLabelRowHeight` per rendered
   row; a `Text`'s real row height is `fontSize * style.height`. The token
   factories therefore DERIVE each style's `height` from its row-height metric
   rather than typing both as literals, and `reader_theme_test.dart` asserts
   the equality. Two independent literals here is the same class of drift as
   two independent copies of a style.

These tests are re-run after every visual change, not at the end of the slice.

### Reader error taxonomy

ADR-023 / ADR-024 states must all survive the chrome restructure, each with its
user-visible state and test: unavailable song, access denied, retryable backend
failure, preserved-title tombstone, unresolved remote-delete conflict,
unavailable planning context. The new bottom bar must render sensibly in the
scoped states where there is no song to describe.

### Backend-owned authorization

Untouched. Nothing in this slice reaches authorization.

## Defect pulled into scope

**Lyric lines break mid-word at narrow widths.** At 375px the reader renders
`Igé` / `dben bízok én` and `Szelleme` / `d újítson meg!`.

Root cause (corrected 2026-08-10, after reading the code rather than inferring
from the screenshot): `groupSegmentsIntoWords`
(`song_reader_word_groups.dart:23-33`) decides group boundaries at **segment**
granularity — a new group starts only where the previous segment's text ends
with whitespace or the next segment's begins with it. A segment's *internal*
whitespace is never a boundary. So `Kegyelmed elég, több, mint elég, Igé` plus
`dben bízok én` becomes one indivisible group holding an entire line of text.
That group is wider than the line, so the renderer falls back to packing it
segment by segment, and the only available break is the segment boundary — which
sits in the middle of `Igédben`.

The file's own doc comment claims a break is only possible where the source text
had whitespace. Today the opposite holds: the real word boundaries are not break
opportunities, and the mid-word segment boundary is.

The estimator (`song_reader_fit.dart:763`) mirrors this faithfully, so the
estimate is correct and the render is wrong. Both move together in the fix.

**Amended 2026-08-10, while implementing:** "the estimate is correct" held for
the grouping rule only. Building the new consistency fixtures surfaced a
*separate*, pre-existing estimator defect on the same code path — the
`columnWidth.clamp(120.0, 1200.0)` applied to `effectiveLineWidth` clamped the
modelled line width **up** to 120px for any narrower column, modelling a wider
line than the renderer gets and so under-estimating its height. Under a
one-sided `estimated >= rendered` contract the two bounds are not symmetric: a
narrower model is always safe, a wider one is never. Reproduced on `main` at a
90px column (rendered 126px, estimated 114px). Fixed by lowering the floor to a
pure numeric guard, `minEffectiveLineWidth`; the 1200px cap stays, as it can
only over-estimate. Full measurements in
`docs/deferred/2026-07-28-reader-fit-conservatism-margin.md`, "Word-boundary
splitting (2026-08-10)".

**Amended 2026-08-11, from visual verification:** the first implementation of
`splitSegmentsAtWordBoundaries` also carried the segment's chord onto its *last*
piece whenever that piece had no trailing whitespace and another segment
followed, on the reasoning that "a word split across two segments by a chord can
preserve both chords through the group". That reasoning was wrong, and it
contradicted this spec's own fix description and the plan
(`docs/plans/2026-08-10-reader-word-boundary-wrap.md`, "The fix"), both of which
say the chord rides on the **first** piece only. A chord is drawn once, at the
position where it starts sounding; every later piece of the same segment is
still under that chord, so a second label there announces a chord change the
source never wrote. In a chord-dense line the duplicate lands directly next to
the following segment's real chord and the two labels render as one run of text.
Caught on the real song "A mi Istenünk (Leborulok előtted)"
(`[E] Kegyelmed elé[G#m]g, több, mint elé[C#m]g, Igé[A]dben bízok é[E]n`), whose
first line has four mid-word chord splits: at ~400px the reader drew `G#m` over
`elé` immediately before `C#m` over `g,`, reading as `G#mC#m`. Fixed by dropping
the last-piece rule, so exactly one label per source chord survives the split.
The estimator consumes the same splitter and moved with it; the recorded
render/estimate measurements are unchanged (the chord column was never the wider
of the two).

That document also records a real side effect of the fix: because a line is now
one box per word in the outer `Wrap`, the renderer's 10px `lineRunSpacing` now
applies between a line's own wrapped rows (+10px per wrap), where a
single-segment line previously wrapped internally at plain text leading. Lines
that already split into several groups behaved this way on `main`, so this makes
the behaviour consistent rather than introducing it. Whether that leading is the
right typography belongs to the type-scale slice, not here.

**Fix:** make the wrapping unit the word rather than the segment run. Split each
segment's text at its internal whitespace before grouping, leaving the
whitespace on the left-hand piece so the rendered string is unchanged, and
carrying `displayChord` only on the first piece (the chord is positioned at the
segment's start). The existing grouping rule then produces exactly one word per
group with no change to the rule itself, and the over-wide-group branch fires
only for a genuinely unbreakable single word — which is its correct meaning.

## Phone behaviour

At 375x812 with the phone token set, the reference song is 1215px against 720px
of available height, and 11 of 13 lines wrap. **On a phone, scrolling and
wrapping are the normal state, not a failure**, and fit-to-screen would choose an
unusably small size. The phone target is legibility per line, not the whole song
per screen. No phone-specific fit behaviour is added here; this is recorded so
the plan does not treat phone wrap counts as a regression.

## Testing

- The three estimator consistency suites stay green, and their measured tables
  in `docs/deferred/2026-07-28-reader-fit-conservatism-margin.md` are re-measured
  and updated in the same commit as the constants change. That deferred item is
  **not** resolved by this work — the estimator stays a deliberate upper bound —
  so the document is updated, not removed.
- New estimator cases: a chord label with chip padding at a width where it wraps;
  an uppercased, letter-spaced section label at a narrow width; a `w500` lyric
  line at a width where the weight change alone shifts the wrap point.
- Widget tests: bottom bar contents in plan vs. catalogue mode; neighbour titles
  present on tablet and absent on phone; capo shown only when the directive is
  visible; reveal toggle showing and hiding the top bar and rail together;
  content geometry unchanged by the reveal (the fit input must not move).
- A regression test that the reader content is left-aligned at a fixed edge
  rather than centred on its longest line.
- Visual verification: screenshots of the running app at 834x1194 and 375x812,
  in both themes, before and after.

## Slice / PR split

Four PRs. Revised 2026-08-10, after PR1 landed and the wrap defect's real cause
turned out to be a separate correctness bug rather than a styling consequence.

1. **Token layer + dark theme.** *(landed: #69)* `ReaderTheme` holding every
   reader colour and text style, both themes registered, an in-app light/dark
   switch, ADR-033, UX-7 closed. Light rendering pixel-identical and no
   estimator constant moved.
2. **Word-boundary wrapping.** *(landed: #70)* The defect above: split
   segments at internal whitespace so a group is one word, in both the
   renderer and the estimator, with its own consistency fixtures. Measured
   against **today's** metrics, so its fixtures prove one thing at a time.
3. **Type scale.** *(landed: #71)* Two commits: first the estimator's
   row-height and gap constants become values passed in (defaulted to today's,
   so no fixture moves — the inert step), then the new values from sections
   1-4 with the chip, the uppercased label and the margins. Re-measures the
   reader-fit deferred doc's tables.
4. **Chrome restructure.** Fixed bottom bar, tap-revealed top bar and control
   rail, phone adaptation, safe-area handling. ADR for the chrome model.

There is deliberately **no separate documentation PR**: AGENTS.md rule 4 makes
docs part of the change that justifies them, so each PR carries its own ADR and
its own review-doc strike-throughs.

Why 2 and 3 are separate: the wrap fix proves the renderer and the estimator
agree under *unchanged* metrics; the type scale proves they still agree under
changed ones. Merged into one diff, a moved fixture number would not identify
which change moved it — the failure mode that cost Phase 2 eight review rounds.

Why 3 is one PR and not two: landing the plumbing inert is a real risk
reduction, but it is visible as a commit boundary, which is where a reviewer
checks it. A second PR would add a CI round and a session for no extra evidence.

## Open questions, to settle on a real device rather than in a mockup

- **Pure black and OLED scrolling.** Some OLED panels smear on high-contrast
  edges during scroll. This is panel-dependent and cannot be judged from a
  mockup. If it is visible on the target hardware, the fallback is lifting the
  page to a near-black, which by the measurements above costs true black and
  buys no glare reduction.
- **12px side padding versus edge gestures and rounded corners** on a tablet.
  If the text crowds the edge-swipe zone, the fix is asymmetric padding, not a
  return to wide margins.
- **Right-edge rail and handedness.** The rail assumes a right-handed grip. A
  mirroring setting is deliberately deferred until the layout has been used.
