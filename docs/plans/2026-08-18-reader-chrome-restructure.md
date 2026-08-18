# Reader Chrome Restructure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the chrome model from `docs/specs/2026-08-09-song-presentation.md` section 6 and 7 — an always-visible bottom bar that occupies layout space, a tap-revealed top bar and a tap-revealed control rail that both *float over* the content, phone adaptation and per-surface safe-area handling — without moving the fit calculation's available height when the chrome is revealed.

**Architecture:** The compact surface stops being a `Column` of competing chrome and becomes `Column[ Expanded(Stack[content, top bar, rail]), bottom bar ]`. Inside that `Stack` the content is the only non-positioned child, so it alone determines the `Stack`'s size and the two `Positioned` overlays cannot influence the constraints the fit `LayoutBuilder` sees. `Scaffold.appBar` is removed entirely: the reader's top bar becomes one of those overlays, which is where the bulk of the recovered vertical space comes from. The blanket `SafeArea` in `SongReaderBodyShell` is replaced by per-surface inset handling, because a bar that must measure `58 + home-indicator inset` cannot sit inside an ancestor that already ate the inset.

**Tech Stack:** Flutter 3.44.9 / Dart, Material 3, `Stack`/`Positioned`, `MediaQuery.viewPaddingOf`, `ThemeExtension` (`ReaderTheme`), `flutter_test`.

---

## Background you need before touching anything

Read these first. Each one prevents a specific mistake:

- `docs/specs/2026-08-09-song-presentation.md` — sections 6 ("Chrome"), "Platform conformance", 7 ("Breakpoints and the expanded shell"), "Invariants this work must not break", "Phone behaviour", "Testing". **The structure is settled with the product owner and was checked against Apple's HIG. Do not redesign it and do not propose alternatives.**
- `docs/architecture/decisions/ADR-033-reader-design-token-layer.md` — the token layer this work consumes.
- `docs/architecture/decisions/ADR-023-*` and `ADR-024-*` — the reader error taxonomy that must survive unchanged.

### The invariant this whole PR is about

The fit calculation's available height is read at `song_reader_compact_surface.dart:300-313`:

```
Expanded( child: LayoutBuilder( builder: (context, constraints) {
  final availableHeight = constraints.maxHeight - _contentPaddingV;
```

Today that `Expanded` shares its `Column` with `SongReaderControlBar` (+12px gap) and `SongReaderBottomContextBar` (+16px gap), so **revealing the controls shrinks the content area**. After this PR, revealing the top bar and the rail must not change `constraints.maxHeight` by a single pixel.

Get this wrong and nothing looks broken. `resolveFitFontScale` picks the largest scale whose *estimated* height fits a *stale, too-large* available height, and fit-to-screen starts overflowing — the exact failure the feature exists to prevent.

**Task 1 writes the guard test for this, before any restructuring.** Do not reorder it.

### What this PR does NOT touch

- **`song_reader_fit.dart`'s per-line estimation math.** This PR changes a fit *input* (available height), not the model. If you find yourself editing how a line's height is estimated, stop and re-read this paragraph. The three consistency suites
  (`song_line_view_estimate_consistency_test.dart`, `song_reader_block_estimate_consistency_test.dart`, `song_reader_estimate_render_consistency_test.dart`)
  must stay green throughout, and `estimated >= rendered` stays one-sided.
- **`docs/deferred/2026-07-28-reader-fit-conservatism-margin.md` is not resolved by this work.** The estimator stays a deliberate upper bound. Touch that document only if a measured table in it actually moves.
- **The expanded shell.** `song_reader_expanded_surface.dart`, `song_reader_expanded_context_panel.dart` and `song_reader_expanded_tools_panel.dart` keep their current chrome. Spec section 7 scopes the chrome model to the compact shell only. Converging the two shells is a future slice.
- **No idle auto-hide.** A control must not vanish while someone on stage is reaching for it. Do not add a timer.
- **No rail-mirroring / handedness setting.** Deliberately deferred until the layout has been used.

### The 600px breakpoint already exists

Spec section 7 asks for a named 600 logical px constant. PR1/PR3 already landed it:
`readerRegularTypeScaleMinWidth` at `apps/lyron_app/lib/src/app/reader_theme.dart:13`, whose doc comment already names it "the third width threshold" alongside `denseLayoutMinWidth` (`song_reader_fit.dart:166`) and the expanded shell's 1600 (`song_reader_layout.dart:33`).

**Reuse it. Do not declare a second 600.** One definition per value is the rule the token layer was built on.

### Error taxonomy

ADR-023/024 states must all survive: unavailable song, access denied, retryable backend failure, preserved-title tombstone, unresolved remote-delete conflict, unavailable planning context. The new bottom bar must render sensibly in the scoped states where there is no song to describe — Task 9 covers this explicitly.

---

## File structure

**New**

- `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_bottom_bar.dart` — the always-visible bar. Replaces `song_reader_bottom_context_bar.dart`.
- `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_top_bar.dart` — the floating top bar. Replaces the reader's use of `song_reader_app_bar.dart`.
- `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_control_rail.dart` — the floating right-edge rail. Replaces `song_reader_control_bar.dart` in the compact shell.
- `apps/lyron_app/lib/src/presentation/song_reader/song_reader_chrome_metrics.dart` — bar heights and rail insets, breakpoint-resolved.
- `apps/lyron_app/test/presentation/song_reader/widgets/song_reader_chrome_geometry_test.dart` — the guard test from Task 1.
- `apps/lyron_app/test/presentation/song_reader/widgets/song_reader_bottom_bar_test.dart`
- `apps/lyron_app/test/presentation/song_reader/widgets/song_reader_top_bar_test.dart`
- `apps/lyron_app/test/presentation/song_reader/widgets/song_reader_control_rail_test.dart`
- `docs/architecture/decisions/ADR-034-reader-chrome-model.md`

**Modified**

- `song_reader_compact_surface.dart` — `Column` becomes `Column[Expanded(Stack), bottom bar]`.
- `song_reader_shell.dart` — drops the blanket `SafeArea` (line 99), passes the new chrome props.
- `song_reader_screen.dart` — stops building a `Scaffold.appBar` for the compact shell.
- `session_scoped_reader_context.dart` + its resolver — gains `position` and `itemCount` for `3 / 7`.
- `song_reader_compact_surface_test.dart`, `song_reader_screen_test.dart` — follow the new tree.

**Deleted**

- `song_reader_bottom_context_bar.dart`, `song_reader_control_bar.dart` and their tests (superseded; their assertions move into the new bars' tests).
- `song_reader_title_bar.dart` — dead code, zero call sites. Removing it is in scope: rule 7, every commit leaves the repo clearer.

**Untouched:** `song_reader_app_bar.dart` stays *only* if the expanded shell still uses it; if the compact shell was its only consumer, delete it too. Check before deciding.

---

## Tasks

### Task 1 — The guard test, before anything else

- [ ] Write `song_reader_chrome_geometry_test.dart`. It pumps the compact surface at a fixed size, captures the fit input, toggles the reveal, and asserts the fit input is **identical**.
- [ ] Capture the fit input by the value that actually feeds `resolveFitFontScale`: the `availableHeight`/`availableWidth` handed to `SongReaderSectionGrid` (`compact_surface.dart:357`). Read it off the pumped `SongReaderSectionGrid` widget rather than re-deriving it, so the test fails if the plumbing changes.
- [ ] Assert on both axes: the rail is a right-edge overlay, so width must not move either.
- [ ] Also assert the rendered content `Rect` (top-left of the section grid) is unchanged by the reveal.
- [ ] On today's code this test **must fail** — that is the point. Record the failing numbers in the commit message.
- [ ] Commit the failing test on its own so the diff shows the behaviour change explicitly.

### Task 2 — Chrome metrics

- [ ] `song_reader_chrome_metrics.dart`: `bottomBarHeight` = 64.0 regular / 58.0 compact, resolved off `readerRegularTypeScaleMinWidth` (imported, not re-declared), plus the rail's edge inset and the top bar height.
- [ ] The bottom bar's *total* height is `bottomBarHeight + viewPadding.bottom`; the metrics object carries the bar height only, the widget adds the inset. Keep that split — it is what makes the widget testable without a fake `MediaQuery` per case.
- [ ] Test the resolution at 599 / 600 / 601 px.

### Task 3 — The overlay restructure

- [ ] `song_reader_compact_surface.dart`: `Column[ Expanded(Stack[content, if(revealed) top bar, if(revealed) rail]), bottomBar ]`.
- [ ] Content is the **only non-positioned** `Stack` child. Both overlays are `Positioned`. This is the mechanism the guard test proves; do not use `Align`, `fit: StackFit.expand` on the overlays, or anything else that could feed back into sizing.
- [ ] Remove the control bar and bottom context bar from the `Column`, with their 12px and 16px gaps.
- [ ] `song_reader_screen.dart`: no `Scaffold.appBar` for the compact shell.
- [ ] Task 1's test must now pass. Run the three estimator consistency suites in the same step.

### Task 4 — Per-surface safe area

- [ ] Remove the blanket `SafeArea` at `song_reader_shell.dart:99`.
- [ ] Bottom bar consumes `MediaQuery.viewPaddingOf(context).bottom` itself: height `58 + inset` on phone, `64` on tablet, content vertically centred in the bar's *bar-height* portion so the inset reads as breathing room under it, not as a shifted label.
- [ ] Top bar consumes the top inset; the rail consumes the right inset in landscape.
- [ ] Content runs edge to edge underneath the overlays.
- [ ] Test with an injected `MediaQuery(viewPadding: EdgeInsets.only(bottom: 34))` — 34 is the iPhone home-indicator inset. **The iOS Simulator is not available on this machine (Command Line Tools only, no `simctl`), so this test is the safe-area evidence.** Say so in the PR body.

### Task 5 — Set position (`3 / 7`)

- [ ] `SessionScopedReaderContext` gains `position` (1-based) and `itemCount`, resolved where the context is built from `PlanDetail`.
- [ ] Keep `==`/`hashCode` in sync — the class hand-writes both.
- [ ] Test the resolver: first item, middle item, last item, single-item session.

### Task 6 — Bottom bar contents

- [ ] Plan-scoped, tablet: previous item (chevron + title) | current title, key, capo, `3 / 7` | next item (title + chevron).
- [ ] Catalogue: current title, key, capo, centred. No chevrons.
- [ ] Plan-scoped, **phone**: chevrons only, no neighbour titles.
- [ ] Capo only when `isCapoDirectiveVisible` (`song_reader_projection.dart:23-25`).
- [ ] Carry over the assertions from `song_reader_bottom_context_bar_test.dart`: full-width neighbour hit targets, disabled neighbours at reduced opacity, renders with no neighbours.

### Task 7 — Top bar

- [ ] Leading edge: back, using the **standard back symbol** (`BackButtonIcon`), never a "Back" text label — spec, *Platform conformance*.
- [ ] Then song title, the recoverable-warnings indicator, the overflow menu.
- [ ] **The title is deliberately duplicated with the bottom bar.** An empty title area was rejected by the product owner. Do not "fix" it; add a code comment saying so, or the next reader will.
- [ ] Floats over the content: it needs its own background treatment so text stays legible over lyrics in both themes. Take the colour from `ReaderTheme`; do not hardcode.

### Task 8 — Control rail

- [ ] Right edge, vertical groups: transpose −/value/+, capo −/value/+, font A−/A+.
- [ ] Capo group hidden in piano mode, exactly as `song_reader_control_bar_test.dart` asserts today. Move those assertions across.
- [ ] Same disabled-state behaviour (`onCapoDown == null`).

### Task 9 — Reveal behaviour and the error states

- [ ] One tap reveals **both** overlays; a second tap dismisses **both**. Extend the existing state (`areCompactControlsVisible`, `song_reader_state.dart:18`) rather than adding a second flag — the tap plumbing already exists at `compact_surface.dart:190-225` and `song_reader_shell.dart:208`.
- [ ] `SongReaderImmersiveMode` keeps driving `SystemChrome` off that same bool. Do not fork it.
- [ ] No idle auto-hide.
- [ ] Walk every ADR-023/024 state and assert the bottom bar renders sensibly where there is no song to describe.

### Task 10 — Remaining enumerated tests

- [ ] Bottom bar contents in plan vs. catalogue mode.
- [ ] Neighbour titles present on tablet, absent on phone.
- [ ] Capo shown only when the directive is visible.
- [ ] Reveal toggle shows and hides top bar and rail **together**.
- [ ] Content geometry unchanged by the reveal (Task 1).
- [ ] Left-alignment regression: content starts at a fixed left edge rather than being centred on its longest line. This assertion **already exists** in `song_reader_compact_surface_test.dart` — carry it through the restructure intact and confirm it still exercises the `Align.topLeft` + tight-width path at `compact_surface.dart:335-362`.

### Task 11 — ADR

- [ ] `ADR-034-reader-chrome-model.md`, following ADR-033's format. Record: three surfaces with three persistences; why both floating surfaces are excluded from the fit input; why there is no auto-hide; the HIG reasoning for back-at-top rather than back-in-the-bottom-bar; the deliberate title duplication; and that the model is scoped to the compact shell.
- [ ] Strike through the closed item in the repository review doc, as PR1–PR3 did.

### Task 12 — Verification

- [ ] Eight screenshots: 834×1194 and 375×812, light and dark, before and after. The "before" set is already captured. Reuse the same headless-Chrome/CDP driver so before and after are comparable.
- [ ] Verify the **+131px** tablet claim against the running app rather than trusting the arithmetic. Measure the content area's available height before and after and report the real number, even if it is not 131.
- [ ] `scripts/verify.sh`, then CI green on `verify`, `backend_write_contracts`, `migrations`, `flutter build web`, coverage and dependency-audit gates.
- [ ] Refresh `graphify-out/`.

---

## Review checkpoints

Per `superpowers:requesting-code-review`, and because Phase 2's reader work took eight review rounds from reviewing late on a large diff:

1. **After Task 3** — the structural change. This is where the invariant lives.
2. **After Task 4** — the phone/safe-area adaptation.
3. **Before the PR** — the whole diff.

## Open questions, for the user on real hardware

These are recorded in the spec as device questions and cannot be settled in a browser:

- 12px side padding versus edge-swipe zones and rounded corners on a tablet. If text crowds the swipe zone, the fix is **asymmetric padding**, not a return to wide margins.
- OLED smearing on pure black during scroll. Not judgeable in a simulator — hand it to the user.
