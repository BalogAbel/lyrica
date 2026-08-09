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
`Igé` / `dben bízok én` and `Szelleme` / `d újítson meg!` — a word carrying a
chord change is split into segments, and when the resulting group is wider than
the line it wraps inside the group. `groupSegmentsIntoWords`
(`song_reader_word_groups.dart`) exists to prevent exactly this and does not
cover the case where the group itself overflows.

This is a correctness defect, not styling, and it becomes more visible as phone
line lengths tighten. It is fixed in this slice, with its own estimator
consistency case, because the estimator already models per-word wrapping and the
fix must stay inside that model.

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

Four PRs. The split is not cosmetic: PR2 is the only one that can break the
estimator invariant, and it should be reviewable without chrome changes mixed in.

1. **Token layer + dark theme.** Introduce `ReaderTheme`, move every existing
   hardcoded reader value into it at its *current* value, add the dark
   `ThemeData` and wire `darkTheme:`. Closes UX-7. ADR for the token layer.
   Light-theme rendering is pixel-identical to today and **no estimator constant
   moves**, which is what makes this reviewable as a refactor; the visible change
   is that users on a dark system setting now get a dark reader.
2. **Typography and spacing.** Section 1, 2, 3 and 4 values, with the estimator
   moved in lockstep and the three traps above covered by new cases. Includes the
   mid-word wrap fix. Updates the reader-fit deferred doc's tables.
3. **Chrome restructure.** Fixed bottom bar, tap-revealed top bar and control
   rail, phone adaptation, safe-area handling. ADR for the chrome model.
4. **Docs closeout.** Repository review strike-throughs, any remaining ADR
   cross-references.

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
