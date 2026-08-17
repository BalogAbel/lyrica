# Reader Type Scale Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the reader type scale from `docs/specs/2026-08-09-song-presentation.md` sections 1-4 and 7 — 22/19px lyrics at `w500`, 15/13px chords in a tinted chip, uppercase letter-spaced section labels, 12px side padding, fixed left edge — with the fit estimator still a valid upper bound at every step.

**Architecture:** Two commits. Commit 1 is inert plumbing: every row-height and gap constant the estimator and the renderer share becomes a field of one `SongReaderMetrics` value object, defaulted to today's numbers, threaded through the estimator the same way `SongReaderFitTextScale` already is. No fixture may move. Commit 2 makes those values breakpoint-dependent by moving them (and the type scale) into the `ReaderTheme` token layer: a new `ReaderThemeSet` `ThemeExtension` carries a phone set and a tablet set, and `ReaderTheme.of(context)` resolves between them from `MediaQuery.sizeOf(context).width`. Renderer and estimator both resolve through that one call, so they cannot see different breakpoints.

**Tech Stack:** Flutter 3.44.9 / Dart, Material 3, `ThemeExtension`, `TextPainter`, `flutter_test`.

---

## Background you need before touching anything

Read these first. They are short and each one prevents a specific mistake:

- `docs/specs/2026-08-09-song-presentation.md` — sections "Design decisions" 1-4 and 7, "Invariants this work must not break", and "Slice / PR split" item 3. **The numbers in section 1 are settled with the product owner. Do not redesign them, do not propose alternatives.**
- `docs/architecture/decisions/ADR-033-reader-design-token-layer.md` — the ADR this plan amends.
- `apps/lyron_app/lib/src/presentation/song_reader/song_reader_fit.dart` lines 95-143 — the height constants and the asymmetric-clamp doc comment.

### The one-sided contract

Three suites assert `estimated >= rendered`, one-sidedly:

- `apps/lyron_app/test/presentation/song_reader/song_line_view_estimate_consistency_test.dart`
- `apps/lyron_app/test/presentation/song_reader/song_reader_block_estimate_consistency_test.dart`
- `apps/lyron_app/test/presentation/song_reader/song_reader_estimate_render_consistency_test.dart`

`resolveFitFontScale` picks the largest scale whose *estimated* height fits. An estimate below the rendered height is the exact overflow fit-to-screen exists to prevent.

**If a fixture goes red because the estimate fell BELOW the render: that is a real bug.** Do not raise the fixture's numbers and do not loosen a tolerance. Use `superpowers:systematic-debugging`, find which change made the model narrower than reality, and fix the model.

If the estimate moved UP (a looser but still valid bound), that is acceptable — record the new number in `docs/deferred/2026-07-28-reader-fit-conservatism-margin.md` in Task 17.

### The asymmetry rule

Modelling a **narrower** line than the renderer really gets can only add estimated wraps → estimate goes up → safe.
Modelling a **wider** line than the renderer really gets removes wraps → estimate goes down → breaks the contract.

Every width decision in this plan follows that rule. `minEffectiveLineWidth` is 1.0 and must stay a pure numeric guard — do not raise it (see the comment at `song_reader_fit.dart:118-142` for what happened last time).

### Three traps that silently under-estimate

1. **Chord chips add width.** The chip's 3px horizontal padding on each side is part of what the chord label occupies. Task 12 handles this on both sides.
2. **Section labels become uppercase and letter-spaced.** `headerCharWidth` is measured today from a mixed-case sample with no tracking. Both change glyph advance. Task 13 re-measures.
3. **Lyrics move to `w500`.** `lyricCharWidth` measures from the tokens, so this *should* come through automatically — Task 11 proves it with an assertion rather than assuming it.

### The density regression this round must repair

PR2 (#70) made every lyric line one box per word inside the outer `Wrap`. That means `lineRunSpacing` — 10px today — now also lands *between a single line's own wrapped rows*, not only between separate `Wrap` children. Measured on a 380px column: one wrapped lyric line went from 114px to 144px.

Today that fact is recorded only in a fixture comment in `song_reader_section_grid_test.dart` (the `420 → 540` `availableHeight` change). Task 10 sets the new value; Task 16 writes the fact into the spec.

---

## File structure

**Modified — estimator and shared metrics**

- `apps/lyron_app/lib/src/presentation/song_reader/song_reader_metrics.dart` — grows from three bare constants into the home of `SongReaderMetrics`, the one value object both sides read. Still the only definition of each number.
- `apps/lyron_app/lib/src/presentation/song_reader/song_reader_fit.dart` — its module-level height constants move into `SongReaderMetrics`; every estimator function takes `metrics` the way it already takes `textScale`.
- `apps/lyron_app/lib/src/presentation/song_reader/song_reader_char_metrics.dart` — `SongReaderCharWidths` gains `metrics`, so the three call sites that already call `measureSongReaderCharWidths(context)` get the resolved metrics from the same `BuildContext` that resolves the styles.

**Modified — token layer**

- `apps/lyron_app/lib/src/app/reader_theme.dart` — `ReaderTheme` stops being the registered extension and becomes the *resolved* token bundle (same class name, same field names, so no call site changes). A new `ReaderThemeSet extends ThemeExtension<ReaderThemeSet>` holds `{compact, regular}` and is what `app_theme.dart` registers. `ReaderTheme.of(context)` resolves via `MediaQuery.sizeOf(context).width`.
- `apps/lyron_app/lib/src/app/app_theme.dart` — registers `ReaderThemeSet` instead of `ReaderTheme`.

**Modified — renderer**

- `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_line_view.dart` — reads spacing from tokens; draws the chord chip.
- `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_section_grid.dart` — reads spacing from tokens; uppercases the section label.
- `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_compact_surface.dart` — fixed left edge instead of `Center` + shrink-wrap.
- `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_shell.dart` — content padding 24 → `12 horizontal, 14 vertical`.

**Docs (AGENTS.md rule 4 — this PR carries them, there is no follow-up docs PR)**

- `docs/architecture/decisions/ADR-033-reader-design-token-layer.md` — amended.
- `docs/specs/2026-08-09-song-presentation.md` — the `lineRunSpacing` meaning change and the 114→144px measurement.
- `docs/deferred/2026-07-28-reader-fit-conservatism-margin.md` — tables re-measured, item NOT resolved.

**Out of scope — do not touch**

- Reader chrome: bottom bar, top bar, side rail, `song_reader_app_bar.dart`, `song_reader_control_bar.dart`, `song_reader_bottom_context_bar.dart`, `song_reader_title_bar.dart`. That is PR4.
- `song_reader_expanded_surface.dart` beyond passing the new `metrics` through. The expanded shell adopts tokens, it is not restructured.
- `song_reader_word_groups.dart` and `splitSegmentsAtWordBoundaries`. PR2 owns those.
- `pubspec.lock` / any dependency version. If a command wants to change it, stop and ask. PR2 leaked a few of these; do not repeat it.
- The two uncommitted changes sitting on `main` (`android/gradle.properties`, `pubspec.yaml` build number). They are not ours. Never `git add` them.

---

## Commands

Run from `apps/lyron_app/`:

- One test file: `flutter test test/presentation/song_reader/song_reader_fit_test.dart`
- One test by name: `flutter test test/path/file_test.dart --plain-name "the test name"`
- The three consistency suites (run these after every visual change, not once at the end):
  ```bash
  flutter test test/presentation/song_reader/song_line_view_estimate_consistency_test.dart test/presentation/song_reader/song_reader_block_estimate_consistency_test.dart test/presentation/song_reader/song_reader_estimate_render_consistency_test.dart
  ```
- Everything: `flutter test`
- Lints: `flutter analyze`

---

# COMMIT 1 — inert plumbing

**The whole point of this commit is that nothing moves.** Precedent in this codebase: `headerCharWidth` and `FlowBlock.blockText` were introduced exactly this way, with defaults, so ~40 existing call sites kept compiling and kept their meaning.

**Proof obligation: after Task 5, `flutter test` passes with zero fixture edits.** If a fixture had to change, the change was not inert — revert and find out why.

---

### Task 1: `SongReaderMetrics` value object

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_metrics.dart` (whole file)
- Test: `apps/lyron_app/test/presentation/song_reader/song_reader_metrics_test.dart` (create)

- [ ] **Step 1: Write the failing test**

Create `apps/lyron_app/test/presentation/song_reader/song_reader_metrics_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_metrics.dart';

void main() {
  group('SongReaderMetrics.legacy', () {
    // These are the values the estimator and the renderer used before the
    // metrics became a passed-in value. They are pinned here so that the
    // "inert plumbing" commit cannot silently change behaviour: every other
    // test in the suite measures against these numbers.
    test('reproduces the pre-extraction constants exactly', () {
      const m = SongReaderMetrics.legacy;

      expect(m.lineRunSpacing, 10.0);
      expect(m.chordOnlySpacing, 22.0);
      expect(m.chordToLyricGap, 2.0);
      expect(m.sectionGap, 20.0);
      expect(m.sectionLabelRowHeight, 28.0);
      expect(m.sectionLabelToLineGap, 12.0);
      expect(m.lineGap, 10.0);
      expect(m.chordRowHeight, 20.0);
      expect(m.lyricRowHeight, 24.0);
      expect(m.directiveLineHeight, 36.0);
      expect(m.tabBlockVerticalPadding, 16.0);
      expect(m.lineWidgetBottomPadding, 2.0);
      expect(m.chordChipHorizontalPadding, 0.0);
    });

    test('headerHeight is the label row plus the gap under it', () {
      // The estimator charged a flat headerHeight of 40 while the renderer
      // drew a ~28px label followed by a literal SizedBox(height: 12).
      // Splitting the constant is what lets the renderer stop hardcoding 12.
      expect(SongReaderMetrics.legacy.headerHeight, 40.0);
    });
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
flutter test test/presentation/song_reader/song_reader_metrics_test.dart
```

Expected: compile error, `SongReaderMetrics` is not defined.

- [ ] **Step 3: Write `SongReaderMetrics`**

Replace the whole of `apps/lyron_app/lib/src/presentation/song_reader/song_reader_metrics.dart`:

```dart
import 'package:flutter/foundation.dart';

/// Layout metrics shared by the reader renderer and the fit estimator.
///
/// These live in ONE object because the estimator has to reproduce the
/// renderer's spacing exactly: a value the two sides define separately drifts
/// silently, and the drift shows up as `estimated < rendered`, which is the
/// overflow that fit-to-screen exists to prevent.
///
/// They used to be module-level `const double`s. They became a value object
/// when the type scale gained a 600px breakpoint (see
/// docs/specs/2026-08-09-song-presentation.md section 7): row heights and gaps
/// differ between the phone and the tablet/desktop set, so a compile-time
/// constant can no longer express them. The resolution happens in exactly one
/// place, `ReaderTheme.of(context)`, which both the renderer and
/// `measureSongReaderCharWidths` call with the same `BuildContext`.
@immutable
class SongReaderMetrics {
  const SongReaderMetrics({
    required this.lineRunSpacing,
    required this.chordOnlySpacing,
    required this.chordToLyricGap,
    required this.sectionGap,
    required this.sectionLabelRowHeight,
    required this.sectionLabelToLineGap,
    required this.lineGap,
    required this.chordRowHeight,
    required this.lyricRowHeight,
    required this.directiveLineHeight,
    required this.tabBlockVerticalPadding,
    required this.lineWidgetBottomPadding,
    required this.chordChipHorizontalPadding,
  });

  /// Vertical gap between runs of a lyric line's `Wrap`.
  ///
  /// Its MEANING changed in PR2 (#70) and its value follows in PR3. Before
  /// PR2 a single-segment line was one `Text` that wrapped internally at plain
  /// text leading, and this spacing only ever separated distinct `Wrap`
  /// children. Since PR2 a line is one box per word, so this spacing also
  /// lands between a single line's OWN wrapped rows. Measured on a 380px
  /// column, one wrapped lyric line went from 114px to 144px at the old value
  /// of 10.
  final double lineRunSpacing;

  /// Horizontal gap between the chord slots of a chord-only line (an
  /// instrumental bar), where there are no words to group.
  final double chordOnlySpacing;

  /// Vertical gap between a segment's chord label and its lyric text.
  final double chordToLyricGap;

  /// Vertical gap between two sections.
  final double sectionGap;

  /// Rendered height of one row of the section label ("Verse 1").
  final double sectionLabelRowHeight;

  /// Gap between a section's label and its first line.
  final double sectionLabelToLineGap;

  /// Gap after each content line inside a section.
  final double lineGap;

  /// Rendered height of one chord row.
  final double chordRowHeight;

  /// Rendered height of one lyric row.
  ///
  /// This must equal the lyric style's real rendered line height, i.e.
  /// `lyricStyle.fontSize * lyricStyle.height`. `ReaderTheme` derives the
  /// style's `height` from this value rather than the other way round, so the
  /// two cannot disagree.
  final double lyricRowHeight;

  /// Rendered height of one directive line (leading or inline).
  final double directiveLineHeight;

  /// Total vertical padding a tab block adds around its raw lines.
  final double tabBlockVerticalPadding;

  /// `SongLineView`'s own `Padding(padding: EdgeInsets.only(bottom: ...))`,
  /// charged once per lyric line because it is part of the widget's measured
  /// render height.
  final double lineWidgetBottomPadding;

  /// Horizontal padding on EACH side of the chord chip.
  ///
  /// Zero means "no chip". Non-zero widens what a chord label occupies, so the
  /// estimator must charge `2 * chordChipHorizontalPadding` per drawn chord —
  /// otherwise a chord that wraps in the render does not wrap in the estimate.
  final double chordChipHorizontalPadding;

  /// What the estimator charges for one rendered row of a section label,
  /// including the gap that follows the label.
  double get headerHeight => sectionLabelRowHeight + sectionLabelToLineGap;

  /// The values in force before the metrics became a passed-in value.
  ///
  /// This is the default for every estimator function in
  /// `song_reader_fit.dart`, so pure unit tests that never construct a
  /// [SongReaderMetrics] keep their original meaning — the same technique
  /// `SongReaderFitTextScale.identity` uses.
  static const legacy = SongReaderMetrics(
    lineRunSpacing: 10.0,
    chordOnlySpacing: 22.0,
    chordToLyricGap: 2.0,
    sectionGap: 20.0,
    sectionLabelRowHeight: 28.0,
    sectionLabelToLineGap: 12.0,
    lineGap: 10.0,
    chordRowHeight: 20.0,
    lyricRowHeight: 24.0,
    directiveLineHeight: 36.0,
    tabBlockVerticalPadding: 16.0,
    lineWidgetBottomPadding: 2.0,
    chordChipHorizontalPadding: 0.0,
  );

  SongReaderMetrics copyWith({
    double? lineRunSpacing,
    double? chordOnlySpacing,
    double? chordToLyricGap,
    double? sectionGap,
    double? sectionLabelRowHeight,
    double? sectionLabelToLineGap,
    double? lineGap,
    double? chordRowHeight,
    double? lyricRowHeight,
    double? directiveLineHeight,
    double? tabBlockVerticalPadding,
    double? lineWidgetBottomPadding,
    double? chordChipHorizontalPadding,
  }) {
    return SongReaderMetrics(
      lineRunSpacing: lineRunSpacing ?? this.lineRunSpacing,
      chordOnlySpacing: chordOnlySpacing ?? this.chordOnlySpacing,
      chordToLyricGap: chordToLyricGap ?? this.chordToLyricGap,
      sectionGap: sectionGap ?? this.sectionGap,
      sectionLabelRowHeight: sectionLabelRowHeight ?? this.sectionLabelRowHeight,
      sectionLabelToLineGap:
          sectionLabelToLineGap ?? this.sectionLabelToLineGap,
      lineGap: lineGap ?? this.lineGap,
      chordRowHeight: chordRowHeight ?? this.chordRowHeight,
      lyricRowHeight: lyricRowHeight ?? this.lyricRowHeight,
      directiveLineHeight: directiveLineHeight ?? this.directiveLineHeight,
      tabBlockVerticalPadding:
          tabBlockVerticalPadding ?? this.tabBlockVerticalPadding,
      lineWidgetBottomPadding:
          lineWidgetBottomPadding ?? this.lineWidgetBottomPadding,
      chordChipHorizontalPadding:
          chordChipHorizontalPadding ?? this.chordChipHorizontalPadding,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SongReaderMetrics &&
        other.lineRunSpacing == lineRunSpacing &&
        other.chordOnlySpacing == chordOnlySpacing &&
        other.chordToLyricGap == chordToLyricGap &&
        other.sectionGap == sectionGap &&
        other.sectionLabelRowHeight == sectionLabelRowHeight &&
        other.sectionLabelToLineGap == sectionLabelToLineGap &&
        other.lineGap == lineGap &&
        other.chordRowHeight == chordRowHeight &&
        other.lyricRowHeight == lyricRowHeight &&
        other.directiveLineHeight == directiveLineHeight &&
        other.tabBlockVerticalPadding == tabBlockVerticalPadding &&
        other.lineWidgetBottomPadding == lineWidgetBottomPadding &&
        other.chordChipHorizontalPadding == chordChipHorizontalPadding;
  }

  @override
  int get hashCode => Object.hash(
    lineRunSpacing,
    chordOnlySpacing,
    chordToLyricGap,
    sectionGap,
    sectionLabelRowHeight,
    sectionLabelToLineGap,
    lineGap,
    chordRowHeight,
    lyricRowHeight,
    directiveLineHeight,
    tabBlockVerticalPadding,
    lineWidgetBottomPadding,
    chordChipHorizontalPadding,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Deprecated module-level constants
//
// Kept for the duration of the inert commit so that call sites can migrate one
// file at a time. Task 5 deletes them; nothing may reference them after that.
// ─────────────────────────────────────────────────────────────────────────────

const double lineRunSpacing = 10.0;
const double chordOnlySpacing = 22.0;
const double chordToLyricGap = 2.0;
```

- [ ] **Step 4: Run the test**

```bash
flutter test test/presentation/song_reader/song_reader_metrics_test.dart
```

Expected: PASS, 2 tests.

- [ ] **Step 5: Run the whole suite — nothing may move**

```bash
flutter test
```

Expected: same pass/fail set as on `main`. If anything changed, stop.

- [ ] **Step 6: Commit**

```bash
git add apps/lyron_app/lib/src/presentation/song_reader/song_reader_metrics.dart apps/lyron_app/test/presentation/song_reader/song_reader_metrics_test.dart
git commit -m "refactor(reader): introduce SongReaderMetrics value object"
```

---

### Task 2: Thread `metrics` through the estimator

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_fit.dart`
- Test: `apps/lyron_app/test/presentation/song_reader/song_reader_fit_metrics_param_test.dart` (create)

This is the biggest mechanical task in the plan. Work through the file top to bottom.

- [ ] **Step 1: Write the failing test**

Create `apps/lyron_app/test/presentation/song_reader/song_reader_fit_metrics_param_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_fit.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_metrics.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';

SongReaderSectionProjection _section() {
  return const SongReaderSectionProjection(
    label: 'Verse',
    number: 1,
    isUnknown: false,
    lines: [
      SongReaderLyricLineProjection(
        segments: [
          SongReaderSegmentProjection(displayChord: 'C', text: 'one two '),
          SongReaderSegmentProjection(displayChord: 'G', text: 'three four'),
        ],
      ),
    ],
  );
}

void main() {
  group('estimator metrics parameter', () {
    test('omitting metrics reproduces the legacy constants', () {
      final withDefault = estimateSongContentHeight(
        sections: [_section()],
        viewMode: SongReaderViewMode.chordsAndLyrics,
        availableWidth: 300,
        fontScale: 1.0,
      );
      final explicitLegacy = estimateSongContentHeight(
        sections: [_section()],
        viewMode: SongReaderViewMode.chordsAndLyrics,
        availableWidth: 300,
        fontScale: 1.0,
        metrics: SongReaderMetrics.legacy,
      );

      expect(withDefault, explicitLegacy);
    });

    test('a taller lyric row raises the estimate', () {
      // Proves the parameter is actually consumed rather than accepted and
      // ignored — the failure mode a defaulted parameter invites.
      final base = estimateSongContentHeight(
        sections: [_section()],
        viewMode: SongReaderViewMode.chordsAndLyrics,
        availableWidth: 300,
        fontScale: 1.0,
        metrics: SongReaderMetrics.legacy,
      );
      final taller = estimateSongContentHeight(
        sections: [_section()],
        viewMode: SongReaderViewMode.chordsAndLyrics,
        availableWidth: 300,
        fontScale: 1.0,
        metrics: SongReaderMetrics.legacy.copyWith(lyricRowHeight: 48.0),
      );

      expect(taller, greaterThan(base));
    });

    test('a wider section gap raises the estimate', () {
      final base = estimateSongContentHeight(
        sections: [_section()],
        viewMode: SongReaderViewMode.chordsAndLyrics,
        availableWidth: 300,
        fontScale: 1.0,
        metrics: SongReaderMetrics.legacy,
      );
      final wider = estimateSongContentHeight(
        sections: [_section()],
        viewMode: SongReaderViewMode.chordsAndLyrics,
        availableWidth: 300,
        fontScale: 1.0,
        metrics: SongReaderMetrics.legacy.copyWith(sectionGap: 60.0),
      );

      expect(wider, base + 40.0);
    });
  });
}
```

If `SongReaderSectionProjection` / `SongReaderSegmentProjection` constructors differ from the shape above, copy the exact shape from an existing fixture in `apps/lyron_app/test/presentation/song_reader/song_reader_fit_test.dart` rather than guessing.

- [ ] **Step 2: Run it and watch it fail**

```bash
flutter test test/presentation/song_reader/song_reader_fit_metrics_param_test.dart
```

Expected: compile error — `metrics` is not a named parameter.

- [ ] **Step 3: Add the parameter to every estimator entry point**

In `song_reader_fit.dart`, add this named parameter — with exactly this default — to each of:

`_segmentRowHeight`, `_lineItemHeight`, `flowBlockHeight`, `estimateSectionHeight`, `estimateSongContentHeight`, `resolveFlowLayoutForSections`, `estimateRenderedLayout`, `resolveFitFontScale`.

```dart
  SongReaderMetrics metrics = SongReaderMetrics.legacy,
```

(For the two private helpers `_segmentRowHeight` and `_lineItemHeight`, make it `required SongReaderMetrics metrics` instead — they are only called from inside this file, and a required parameter there means the compiler catches a missed call site instead of silently falling back to legacy.)

Then pass `metrics: metrics` at every internal call site: `estimateSongContentHeight` → `estimateSectionHeight` → `_lineItemHeight`; `flowBlockHeight` → `_lineItemHeight`; `_lineItemHeight` → `_segmentRowHeight`; `resolveFlowLayoutForSections` → `flowBlockHeight`; `estimateRenderedLayout` → `flowBlockHeight` and → `resolveFlowLayoutForSections`; `resolveFitFontScale` → `estimateRenderedLayout`.

`resolveFlowLayout` takes pre-computed heights and needs no `metrics`.

- [ ] **Step 4: Replace every module-level constant use inside the file**

Replace, in the function bodies only:

| was | becomes |
|---|---|
| `chordRowHeight` | `metrics.chordRowHeight` |
| `lyricRowHeight` | `metrics.lyricRowHeight` |
| `chordToLyricGap` | `metrics.chordToLyricGap` |
| `chordOnlySpacing` | `metrics.chordOnlySpacing` |
| `lineRunSpacing` | `metrics.lineRunSpacing` |
| `lineGap` | `metrics.lineGap` |
| `lineWidgetBottomPadding` | `metrics.lineWidgetBottomPadding` |
| `tabBlockVerticalPadding` | `metrics.tabBlockVerticalPadding` |
| `directiveLineHeight` | `metrics.directiveLineHeight` |
| `headerHeight` | `metrics.headerHeight` |
| `sectionGap` | `metrics.sectionGap` |

Do NOT touch `denseLayoutMinWidth`, `columnUsefulMaxRatio`, `columnHeightToleranceFactor`, `columnBalanceMinRatio`, `characterWidthEstimate`, `minEffectiveLineWidth`, `maxEffectiveLineWidth` — those are layout-decision or guard constants, not spacing, and they stay module-level.

Note the one non-obvious site: `estimateRenderedLayout` computes `final tileWidth = (availableWidth - sectionGap) / 2;` — that becomes `metrics.sectionGap` too, and `song_reader_section_grid.dart` must use the same value (Task 4).

Add the import at the top of `song_reader_fit.dart` if it is not already there:

```dart
import 'package:lyron_app/src/presentation/song_reader/song_reader_metrics.dart';
```

**Do not delete the module-level constants yet.** Six test files and four widget files still reference them by bare name:

```
test/presentation/song_reader/song_line_view_estimate_consistency_test.dart
test/presentation/song_reader/song_reader_block_estimate_consistency_test.dart
test/presentation/song_reader/song_reader_estimate_render_consistency_test.dart
test/presentation/song_reader/song_reader_fit_test.dart
test/presentation/song_reader/widgets/song_reader_section_grid_test.dart
lib/.../widgets/{song_line_view,song_reader_section_grid,song_reader_compact_surface,song_reader_expanded_surface}.dart
```

Leave the constants in place, marked deprecated the same way `song_reader_metrics.dart` marks its three, so this task compiles with zero collateral edits. Task 5 removes them and migrates the references in one sweep.

Move the `lineWidgetBottomPadding` doc comment's measurement note onto the corresponding `SongReaderMetrics` field so the reasoning is not lost when the constant goes.

- [ ] **Step 5: Run the new test**

```bash
flutter test test/presentation/song_reader/song_reader_fit_metrics_param_test.dart
```

Expected: PASS, 3 tests.

- [ ] **Step 6: Prove inertness**

```bash
flutter test
flutter analyze
```

Expected: the same results as before this task, **with no test file edited**. Other files (widgets) may not compile yet if they imported the deleted constants — fix those by importing `song_reader_metrics.dart` and using `SongReaderMetrics.legacy.<field>` for now; Task 4 replaces that with the real resolution.

- [ ] **Step 7: Commit**

```bash
git add apps/lyron_app/lib apps/lyron_app/test/presentation/song_reader/song_reader_fit_metrics_param_test.dart
git commit -m "refactor(reader): pass layout metrics into the fit estimator"
```

---

### Task 3: `SongReaderCharWidths` carries the metrics

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_char_metrics.dart`
- Test: `apps/lyron_app/test/presentation/song_reader/song_reader_char_metrics_test.dart` (create if absent, otherwise extend)

Why here: the three widgets that drive the estimator (`song_reader_section_grid.dart`, `song_reader_compact_surface.dart`, `song_reader_expanded_surface.dart`) already call `measureSongReaderCharWidths(context)`. Putting the metrics in the same bundle means the styles and the spacing are resolved from **one** `BuildContext`, in one call — which is what makes it impossible for the renderer and the estimator to see different breakpoints in Commit 2.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_char_metrics.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_metrics.dart';

void main() {
  testWidgets('measureSongReaderCharWidths returns the reader metrics', (
    tester,
  ) async {
    late SongReaderCharWidths measured;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            measured = measureSongReaderCharWidths(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(measured.metrics, SongReaderMetrics.legacy);
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
flutter test test/presentation/song_reader/song_reader_char_metrics_test.dart
```

Expected: compile error — `metrics` is not defined on `SongReaderCharWidths`.

- [ ] **Step 3: Implement**

In `song_reader_char_metrics.dart`, add to the `SongReaderCharWidths` constructor and class:

```dart
  /// The resolved [SongReaderMetrics] for this build's `BuildContext`.
  ///
  /// Bundled with the char widths deliberately: both come from the SAME
  /// `ReaderTheme.of(context)` call, so the row heights the estimator charges
  /// and the styles the renderer draws with can never be resolved at two
  /// different breakpoints.
  final SongReaderMetrics metrics;
```

with `required this.metrics,` in the constructor, and in `measureSongReaderCharWidths`:

```dart
    metrics: tokens.metrics,
```

For this commit `ReaderTheme` has no `metrics` field yet, so return `SongReaderMetrics.legacy` directly and leave a `// Commit 2 replaces this with tokens.metrics.` comment above it. Do not add the field to `ReaderTheme` yet — that is Task 8.

- [ ] **Step 4: Run the test**

```bash
flutter test test/presentation/song_reader/song_reader_char_metrics_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/lyron_app/lib/src/presentation/song_reader/song_reader_char_metrics.dart apps/lyron_app/test/presentation/song_reader/song_reader_char_metrics_test.dart
git commit -m "refactor(reader): bundle layout metrics with the measured char widths"
```

---

### Task 4: Renderer reads its spacing from the metrics

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_line_view.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_section_grid.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_compact_surface.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_expanded_surface.dart`

The renderer currently hardcodes two gaps that the estimator models as constants: `SizedBox(height: 12)` after a section header (`song_reader_section_grid.dart:178`) and `SizedBox(height: 10)` after each line (`:183`). Those literals are why `headerHeight` had to be a single opaque 40. Both become metrics fields here.

- [ ] **Step 1: Write the failing test**

Add to `apps/lyron_app/test/presentation/song_reader/widgets/song_reader_section_grid_test.dart`:

```dart
  testWidgets('section grid spaces blocks with the reader metrics', (
    tester,
  ) async {
    // Pins the renderer's gaps to the SAME numbers the estimator charges.
    // Before this test the grid hardcoded 12 after a header and 10 after a
    // line, while the estimator carried them inside headerHeight/lineGap:
    // two definitions of one number, which is exactly how estimator drift
    // starts.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SongReaderSectionGrid(
            sections: [_verseSection()],
            viewMode: SongReaderViewMode.chordsAndLyrics,
            sharedFontScale: 1.0,
            columnCount: 1,
            availableHeight: 800,
          ),
        ),
      ),
    );

    final gaps = tester
        .widgetList<SizedBox>(find.byType(SizedBox))
        .map((box) => box.height)
        .whereType<double>()
        .toSet();

    expect(gaps, contains(SongReaderMetrics.legacy.sectionLabelToLineGap));
    expect(gaps, contains(SongReaderMetrics.legacy.lineGap));
  });
```

Use the file's existing section fixture helper instead of `_verseSection()` if one already exists there; read the top of the file first.

- [ ] **Step 2: Run it**

```bash
flutter test test/presentation/song_reader/widgets/song_reader_section_grid_test.dart
```

Expected: it may already pass by coincidence (12 == 12, 10 == 10). That is fine and expected — this test's job is to lock the equality, not to drive a change. Confirm it passes.

- [ ] **Step 3: Route the renderer through the metrics**

In `song_reader_section_grid.dart`:

- In `build`, after `final charWidths = measureSongReaderCharWidths(context);`, add `final metrics = charWidths.metrics;`.
- `final tileWidth = (availableWidth - sectionGap) / 2;` → `metrics.sectionGap`.
- `const SizedBox(width: sectionGap)` → `SizedBox(width: metrics.sectionGap)` (drops `const`).
- Pass `metrics: metrics` to `resolveFlowLayoutForSections`.
- `_buildBlockWidgets` gains a `required SongReaderMetrics metrics` parameter (all four call sites pass it), and inside it:
  - `const SizedBox(height: sectionGap)` → `SizedBox(height: metrics.sectionGap)`
  - `const SizedBox(height: 12)` → `SizedBox(height: metrics.sectionLabelToLineGap)`
  - `const SizedBox(height: 10)` → `SizedBox(height: metrics.lineGap)`

In `song_line_view.dart`:

- `final tokens = ReaderTheme.of(context);` is already there. Add `final metrics = SongReaderMetrics.legacy;` with the comment `// Commit 2 replaces this with tokens.metrics.`
- `runSpacing: lineRunSpacing` (both occurrences) → `runSpacing: metrics.lineRunSpacing`
- `final spacing = hasLyricSegments ? 0.0 : chordOnlySpacing;` → `metrics.chordOnlySpacing`
- `const SizedBox(height: chordToLyricGap)` → the segment view needs the value passed in; add a `required double chordToLyricGap` field to `_SongLineSegmentView` and pass `metrics.chordToLyricGap`.
- `padding: const EdgeInsets.only(bottom: 2)` → `EdgeInsets.only(bottom: metrics.lineWidgetBottomPadding)`
- Drop the now-unused `song_reader_metrics.dart` constant import only if nothing else in the file uses it; you still need the file's `SongReaderMetrics` class import.

In `song_reader_compact_surface.dart` and `song_reader_expanded_surface.dart`: pass `metrics: charWidths.metrics` to the `resolveFitFontScale` call.

- [ ] **Step 4: Run the full suite — still inert**

```bash
flutter test
flutter analyze
```

Expected: everything green, **no fixture edited**. `flutter analyze` clean.

- [ ] **Step 5: Commit**

```bash
git add apps/lyron_app/lib apps/lyron_app/test
git commit -m "refactor(reader): render spacing from the shared layout metrics"
```

---

### Task 5: Delete the deprecated module-level constants

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_metrics.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_fit.dart`
- Modify: the five test files listed below (reference renames only)

- [ ] **Step 1: Find every remaining reference**

```bash
cd apps/lyron_app && grep -rn "\bsectionGap\b\|\bheaderHeight\b\|\blineGap\b\|\bchordRowHeight\b\|\blyricRowHeight\b\|\bdirectiveLineHeight\b\|\btabBlockVerticalPadding\b\|\blineWidgetBottomPadding\b\|\blineRunSpacing\b\|\bchordOnlySpacing\b\|\bchordToLyricGap\b" lib test | grep -v "metrics\.\|SongReaderMetrics\.\|m\."
```

- [ ] **Step 2: Migrate the test references**

In these five files, replace each bare constant with `SongReaderMetrics.legacy.<name>` and add the `song_reader_metrics.dart` import:

- `test/presentation/song_reader/song_line_view_estimate_consistency_test.dart`
- `test/presentation/song_reader/song_reader_block_estimate_consistency_test.dart`
- `test/presentation/song_reader/song_reader_estimate_render_consistency_test.dart`
- `test/presentation/song_reader/song_reader_fit_test.dart`
- `test/presentation/song_reader/widgets/song_reader_section_grid_test.dart`

**This is an identifier rename and nothing else.** `SongReaderMetrics.legacy.sectionGap` is 20.0, exactly what `sectionGap` was. No numeric literal in any expectation may change. If a test goes red after the rename, the rename was wrong — do not adjust the expectation.

- [ ] **Step 3: Delete the deprecated constants**

Remove the "Deprecated module-level constants" block from `song_reader_metrics.dart` and the eight height constants from `song_reader_fit.dart`. Keep `characterWidthEstimate`, `minEffectiveLineWidth`, `maxEffectiveLineWidth`, `denseLayoutMinWidth`, `columnUsefulMaxRatio`, `columnHeightToleranceFactor`, `columnBalanceMinRatio`.

- [ ] **Step 4: Verify**

```bash
flutter analyze
flutter test
```

Expected: clean analyze, 1240 passed / 19 skipped plus the new tests, **and no numeric expectation edited anywhere**.

```bash
git diff main -- apps/lyron_app/test | grep '^[-+].*expect' | grep -E '[0-9]+\.[0-9]'
```

Expected: every `+` line has a matching `-` line whose numbers are identical, differing only in the identifier.

- [ ] **Step 4: Commit — this closes the inert commit**

Squash the four commits so far into the single inert commit the PR body promises:

```bash
git reset --soft $(git merge-base HEAD main)
git add apps/lyron_app/lib apps/lyron_app/test
git commit -m "$(cat <<'EOF'
refactor(reader): make estimator row heights and gaps passed-in values

Every row-height and gap constant the fit estimator and the renderer share
moves into one SongReaderMetrics value object, threaded through the estimator
the same way SongReaderFitTextScale already is and defaulted to today's
numbers. The section header's flat 40px splits into the label row (28) plus
the gap under it (12), so the section grid can stop hardcoding that gap as a
literal SizedBox while the estimator charges it inside headerHeight.

This is deliberately inert: no rendered pixel and no estimate changes, and no
test fixture moves. The 600px type-scale breakpoint in the next commit makes
these values context-dependent, which a compile-time constant cannot express.

Same technique as headerCharWidth and FlowBlock.blockText: defaulted
parameters so existing call sites keep both compiling and their meaning.
EOF
)"
```

Then confirm the diff really is inert:

```bash
git diff main --stat -- apps/lyron_app/test
```

Expected: only the two new test files (`song_reader_metrics_test.dart`, `song_reader_fit_metrics_param_test.dart`, `song_reader_char_metrics_test.dart`) and the added grid test — **no changed expectation in any pre-existing test.** If a pre-existing fixture number changed, the commit is not inert. Stop and use `superpowers:systematic-debugging`.

---

# COMMIT 2 — the new values

---

### Task 6: `ReaderThemeSet` and the 600px breakpoint

**Files:**
- Modify: `apps/lyron_app/lib/src/app/reader_theme.dart`
- Modify: `apps/lyron_app/lib/src/app/app_theme.dart`
- Test: `apps/lyron_app/test/app/reader_theme_test.dart`

**Design decision recorded here (this is what amends ADR-033):** the spec's 600px breakpoint makes row heights and gaps width-dependent, so they cannot stay compile-time constants and they cannot live only in `song_reader_metrics.dart`. They move into the token layer, which is where the type scale they must match already lives. ADR-033 says "Spacing is deliberately NOT here"; that decision is superseded, and Task 15 rewrites it rather than leaving it to contradict the code.

The shape chosen, and why:

- `ReaderTheme` **keeps its name and its field names** but stops being the registered extension — it is now the *resolved* bundle for one breakpoint. Every existing call site (`ReaderTheme.of(context).lyricStyle`, and all of `song_line_view.dart`, `song_reader_section_grid.dart`, `song_reader_char_metrics.dart`) is untouched by this.
- A new `ReaderThemeSet extends ThemeExtension<ReaderThemeSet>` holds `{compact, regular}` and is what `app_theme.dart` registers. `ThemeData` is built once at app start with no `MediaQuery` in scope, so the extension must carry BOTH sets and resolve later.
- `ReaderTheme.of(context)` does the resolution, from `MediaQuery.sizeOf(context).width`. This is the load-bearing choice: `measureSongReaderCharWidths(context)` calls the same function with the same `BuildContext` as the widget that renders, so the estimator and the renderer physically cannot resolve to different sets.

Width, not `shortestSide` — `resolveSongReaderLayout` already keys off `viewportWidth`, and a third threshold that measured a different quantity than the other two would be a trap.

**Test what this task actually introduces — the resolution mechanism — not the values.** The values arrive in Task 7. Asserting `fontSize == 19.0` here would leave a red test sitting across a task boundary, which makes the next failure impossible to attribute. Instead, build a `ReaderThemeSet` whose two members differ artificially and assert that the right one comes back.

- [ ] **Step 1: Write the failing test**

Add to `apps/lyron_app/test/app/reader_theme_test.dart`:

```dart
  group('breakpoint resolution', () {
    // Two sets distinguishable by one marker value, so these tests assert the
    // RESOLUTION, not the type scale (Task 7 owns the real numbers).
    ReaderThemeSet markedSet() {
      final base = ThemeData(useMaterial3: true);
      final tokens = ReaderTheme.stageLight(
        colorScheme: base.colorScheme,
        textTheme: base.textTheme,
        compact: false,
      );
      return ReaderThemeSet(
        compact: tokens.copyWith(
          lyricStyle: tokens.lyricStyle.copyWith(fontSize: 11.0),
        ),
        regular: tokens.copyWith(
          lyricStyle: tokens.lyricStyle.copyWith(fontSize: 99.0),
        ),
      );
    }

    Future<ReaderTheme> tokensAt(WidgetTester tester, double width) async {
      late ReaderTheme resolved;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true).copyWith(
            extensions: <ThemeExtension<dynamic>>[markedSet()],
          ),
          home: MediaQuery(
            data: MediaQueryData(size: Size(width, 900)),
            child: Builder(
              builder: (context) {
                resolved = ReaderTheme.of(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      return resolved;
    }

    testWidgets('at 599px the compact set applies', (tester) async {
      expect((await tokensAt(tester, 599)).lyricStyle.fontSize, 11.0);
    });

    testWidgets('at exactly 600px the regular set applies', (tester) async {
      // The spec says "phone (< 600 logical px)", so 600 is the FIRST tablet
      // width, not the last phone width.
      expect((await tokensAt(tester, 600)).lyricStyle.fontSize, 99.0);
    });

    testWidgets('at 834px (tablet portrait, the target) the regular set '
        'applies', (tester) async {
      expect((await tokensAt(tester, 834)).lyricStyle.fontSize, 99.0);
    });

    testWidgets('with no MediaQuery the regular set applies', (tester) async {
      // Conservative direction: the regular set carries the LARGER type, so an
      // estimator built without a MediaQuery over-estimates rather than under-
      // estimates. Under the one-sided contract that is the safe failure.
      late ReaderTheme resolved;
      await tester.pumpWidget(
        Theme(
          data: ThemeData(useMaterial3: true).copyWith(
            extensions: <ThemeExtension<dynamic>>[markedSet()],
          ),
          child: Builder(
            builder: (context) {
              resolved = ReaderTheme.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(resolved.lyricStyle.fontSize, 99.0);
    });

    testWidgets('the estimator and the renderer resolve the same set', (
      tester,
    ) async {
      // The invariant the whole token layer exists for: whatever width is in
      // effect, measureSongReaderCharWidths sees the SAME metrics the widget
      // renders with, because both go through ReaderTheme.of(context).
      late ReaderTheme widgetTokens;
      late SongReaderCharWidths estimatorInput;

      await tester.pumpWidget(
        MaterialApp(
          theme: buildLightTheme(),
          home: MediaQuery(
            data: const MediaQueryData(size: Size(400, 900)),
            child: Builder(
              builder: (context) {
                widgetTokens = ReaderTheme.of(context);
                estimatorInput = measureSongReaderCharWidths(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      expect(estimatorInput.metrics, widgetTokens.metrics);
      expect(
        estimatorInput.textScale.lyricBaseFontSize,
        widgetTokens.lyricStyle.fontSize,
      );
    });
  });
```

- [ ] **Step 2: Run it and watch it fail**

```bash
flutter test test/app/reader_theme_test.dart
```

Expected: fails — `ReaderTheme` has no `metrics`, and the font sizes are still M3 defaults.

- [ ] **Step 3: Implement the set and the resolution**

In `reader_theme.dart`, `ReaderTheme` stops extending `ThemeExtension` and becomes a plain `@immutable` class. Delete its `lerp` override (a `ThemeExtension` needs one; a plain bundle does not). Keep `copyWith` — tests use it.

Add the breakpoint constant and the set:

```dart
/// Below this width the reader uses the compact (phone) type scale; at or
/// above it, the regular (tablet/desktop) set.
///
/// This is the third width threshold in the reader, alongside
/// `denseLayoutMinWidth` (1180, two-column content) and the expanded shell's
/// 1600 — see song_reader_fit.dart and song_reader_layout.dart. All three key
/// off viewport WIDTH, deliberately, rather than one of them measuring
/// `shortestSide`. 600 is also Material 3's own phone/tablet boundary.
const double readerRegularTypeScaleMinWidth = 600.0;

/// The registered `ThemeExtension`: both reader token sets, unresolved.
///
/// `ThemeData` is built once at app start with no `MediaQuery` in scope, so
/// the breakpoint cannot be applied here. It is applied in
/// [ReaderTheme.of], which every reader widget AND
/// `measureSongReaderCharWidths` go through — that shared resolution point is
/// what stops the renderer and the fit estimator from ever seeing different
/// row heights.
@immutable
class ReaderThemeSet extends ThemeExtension<ReaderThemeSet> {
  const ReaderThemeSet({required this.compact, required this.regular});

  /// Tokens for viewports narrower than [readerRegularTypeScaleMinWidth].
  final ReaderTheme compact;

  /// Tokens for viewports at or above [readerRegularTypeScaleMinWidth].
  final ReaderTheme regular;

  ReaderTheme resolve(double width) =>
      width < readerRegularTypeScaleMinWidth ? compact : regular;

  @override
  ReaderThemeSet copyWith({ReaderTheme? compact, ReaderTheme? regular}) {
    return ReaderThemeSet(
      compact: compact ?? this.compact,
      regular: regular ?? this.regular,
    );
  }

  @override
  ReaderThemeSet lerp(ThemeExtension<ReaderThemeSet>? other, double t) {
    if (other is! ReaderThemeSet) return this;
    return ReaderThemeSet(
      compact: compact.lerpTo(other.compact, t),
      regular: regular.lerpTo(other.regular, t),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ReaderThemeSet &&
        other.compact == compact &&
        other.regular == regular;
  }

  @override
  int get hashCode => Object.hash(compact, regular);
}
```

Rename `ReaderTheme`'s existing `lerp` to `ReaderTheme lerpTo(ReaderTheme other, double t)` (same body, non-nullable `other`, drop the `is!` guard, and lerp `metrics` by simply returning `t < 0.5 ? metrics : other.metrics` — row heights must stay a coherent set, and a half-interpolated metrics object is meaningless).

Replace `ReaderTheme.of`:

```dart
  /// The reader tokens for [context], resolved at its viewport width.
  ///
  /// Falls back to [ReaderTheme.stageLight] over the ambient theme when no
  /// [ReaderThemeSet] is registered, so a bare `MaterialApp` in a widget test
  /// renders the same type scale the app does. `app_theme_test.dart` pins the
  /// fallback to the registered light set so the two cannot drift.
  static ReaderTheme of(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.maybeSizeOf(context)?.width ??
        readerRegularTypeScaleMinWidth;
    final compact = width < readerRegularTypeScaleMinWidth;
    return theme.extension<ReaderThemeSet>()?.resolve(width) ??
        ReaderTheme.stageLight(
          colorScheme: theme.colorScheme,
          textTheme: theme.textTheme,
          compact: compact,
        );
  }
```

`MediaQuery.maybeSizeOf` rather than `sizeOf`: a tree with no `MediaQuery` at all must not throw. Defaulting to the regular set there is the conservative direction — the regular set has the LARGER type, so an estimator built without a `MediaQuery` over-estimates rather than under-estimates.

In `app_theme.dart`, register the set:

```dart
    extensions: <ThemeExtension<dynamic>>[
      ReaderThemeSet(
        compact: ReaderTheme.stageLight(
          colorScheme: base.colorScheme,
          textTheme: base.textTheme,
          compact: true,
        ),
        regular: ReaderTheme.stageLight(
          colorScheme: base.colorScheme,
          textTheme: base.textTheme,
          compact: false,
        ),
      ),
    ],
```

and the matching `ReaderTheme.stageDark(textTheme: base.textTheme, compact: true/false)` pair in `buildDarkTheme()`.

Task 7 writes the real `stageLight` / `stageDark` bodies. In THIS task, rename `fromM3` → `stageLight`, add a `required bool compact` parameter that is accepted and not yet used (add `// Task 7 gives this meaning.`), and leave the body producing today's M3-derived values. `ReaderTheme` also gains its `metrics` field here, set to `SongReaderMetrics.legacy` in both factories regardless of `compact` — Task 7 replaces that.

With the tests written as above, this task ends fully green: they assert the resolution mechanism, not the values.

- [ ] **Step 4: Update the mechanical `fromM3` → `stageLight` references**

```bash
grep -rn "fromM3" apps/lyron_app/lib apps/lyron_app/test
```

Update every hit. `apps/lyron_app/test/app/app_theme_test.dart` pins the fallback to the registered light tokens — keep that pin, pointing it at `ReaderThemeSet.regular` and adding a second assertion for `.compact`.

- [ ] **Step 5: Verify**

```bash
flutter analyze
flutter test
```

Expected: analyze clean, the whole suite green including the five new breakpoint tests. Task 6 changes no rendered value, so no pre-existing expectation may move.

- [ ] **Step 6: Commit**

```bash
git add apps/lyron_app/lib/src/app apps/lyron_app/test/app
git commit -m "feat(reader): resolve reader tokens at the 600px breakpoint"
```

---

### Task 7: The type scale itself

**Files:**
- Modify: `apps/lyron_app/lib/src/app/reader_theme.dart`
- Test: `apps/lyron_app/test/app/reader_theme_test.dart`

The numbers, straight from the spec's section 1 table. Do not adjust them.

| token | regular (>=600) | compact (<600) |
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

Plus, decided by this round rather than the spec:

| token | regular | compact | why |
|---|---|---|---|
| `lineRunSpacing` | 2 | 2 | See below. |
| `chordChipHorizontalPadding` | 3 | 3 | Spec section 2. |
| `chordOnlySpacing` | 22 | 22 | Unchanged; it is a horizontal gap between chord slots, unaffected by the type scale. |
| `directiveLineHeight` | 36 | 36 | Unchanged; directives are not in the spec's table and PR4 owns the chrome. |
| `tabBlockVerticalPadding` | 16 | 16 | Unchanged, same reason. |
| `lineWidgetBottomPadding` | 2 | 2 | Unchanged; it is a literal padding in `SongLineView`, not a type-scale value. |

**`lineRunSpacing` = 2, and the reasoning, because a reviewer will ask.** Since PR2 this spacing lands between a single lyric line's own wrapped rows, where before it only separated distinct `Wrap` children — 10px there costs ~20-30px per line on a phone, where wrapping is the normal state. It is not zero because the new lyric leading is tight (`height` is derived as `24/22 ≈ 1.09`, against `1.25` before), so wrapped rows would otherwise nearly touch. At 2 the pitch inside one wrapped line is 26px against 24 + 6 = 30px between two distinct lines, so a continuation still reads as closer to its own line than to the next one — the hierarchy the wrap is supposed to convey.

**Row heights and text styles must agree.** The estimator charges `lyricRowHeight` per rendered row; the renderer's real row height is `fontSize * style.height`. Derive `height` from the row height in the factory so the two cannot drift:

```dart
    const lyricFontSize = 22.0;
    const lyricRowHeight = 24.0;
    // height is DERIVED, never typed as a separate literal: the estimator
    // charges lyricRowHeight per rendered row, and a Text's real row height is
    // fontSize * height. Two independent literals here is exactly the drift
    // that puts the estimate below the render.
    lyricStyle: TextStyle(
      fontSize: lyricFontSize,
      height: lyricRowHeight / lyricFontSize,
      fontWeight: FontWeight.w500,
      color: lyricColor,
    ),
```

- [ ] **Step 1: Write the failing test**

Add to `apps/lyron_app/test/app/reader_theme_test.dart`:

```dart
  group('type scale', () {
    for (final (name, compact, lyricSize, lyricRow, chordSize, chordRow,
            labelSize, labelRow)
        in [
      ('regular', false, 22.0, 24.0, 15.0, 18.0, 15.0, 20.0),
      ('compact', true, 19.0, 21.0, 13.0, 16.0, 13.0, 18.0),
    ]) {
      test('$name light tokens match the spec table', () {
        final base = ThemeData(useMaterial3: true);
        final tokens = ReaderTheme.stageLight(
          colorScheme: base.colorScheme,
          textTheme: base.textTheme,
          compact: compact,
        );

        expect(tokens.lyricStyle.fontSize, lyricSize);
        expect(tokens.lyricStyle.fontWeight, FontWeight.w500);
        expect(tokens.chordStyle.fontSize, chordSize);
        expect(tokens.chordStyle.fontWeight, FontWeight.w700);
        expect(tokens.sectionLabelStyle.fontSize, labelSize);
        expect(tokens.metrics.lyricRowHeight, lyricRow);
        expect(tokens.metrics.chordRowHeight, chordRow);
        expect(tokens.metrics.sectionLabelRowHeight, labelRow);
        expect(tokens.metrics.lineGap, 6.0);
        expect(tokens.metrics.sectionGap, 14.0);
        expect(tokens.metrics.sectionLabelToLineGap, 4.0);
        expect(tokens.metrics.chordToLyricGap, 0.0);
        expect(tokens.metrics.lineRunSpacing, 2.0);
        expect(tokens.metrics.chordChipHorizontalPadding, 3.0);
      });

      test('$name dark tokens use the same metrics as light', () {
        // A theme swap must never move a single pixel of layout: the fit
        // estimate is computed once for the content, not once per theme.
        final base = ThemeData(useMaterial3: true);
        final light = ReaderTheme.stageLight(
          colorScheme: base.colorScheme,
          textTheme: base.textTheme,
          compact: compact,
        );
        final dark = ReaderTheme.stageDark(
          textTheme: base.textTheme,
          compact: compact,
        );

        expect(dark.metrics, light.metrics);
        expect(dark.lyricStyle.fontSize, light.lyricStyle.fontSize);
        expect(dark.lyricStyle.height, light.lyricStyle.height);
      });

      test('$name lyric row height equals the rendered line height', () {
        final base = ThemeData(useMaterial3: true);
        final tokens = ReaderTheme.stageLight(
          colorScheme: base.colorScheme,
          textTheme: base.textTheme,
          compact: compact,
        );

        expect(
          tokens.lyricStyle.fontSize! * tokens.lyricStyle.height!,
          closeTo(tokens.metrics.lyricRowHeight, 0.001),
        );
        expect(
          tokens.chordStyle.fontSize! * tokens.chordStyle.height!,
          closeTo(tokens.metrics.chordRowHeight, 0.001),
        );
        expect(
          tokens.sectionLabelStyle.fontSize! *
              tokens.sectionLabelStyle.height!,
          closeTo(tokens.metrics.sectionLabelRowHeight, 0.001),
        );
      });
    }
  });
```

- [ ] **Step 2: Run it and watch it fail**

```bash
flutter test test/app/reader_theme_test.dart
```

Expected: FAIL on the font sizes.

- [ ] **Step 3: Add `metrics` to `ReaderTheme` and write the two factories**

Add the field:

```dart
  /// Row heights and gaps for this token set's breakpoint.
  ///
  /// Spacing lives here, with the type scale it has to match, because the
  /// 600px breakpoint makes it width-dependent — see ADR-033, which was
  /// amended for exactly this.
  final SongReaderMetrics metrics;
```

`required this.metrics` in the constructor, `metrics` in `copyWith`, `==` and `hashCode`.

Write a private metrics builder so light and dark cannot diverge:

```dart
SongReaderMetrics _readerMetrics({required bool compact}) {
  return SongReaderMetrics(
    // Between the wrapped rows of ONE lyric line since PR2 (#70), not only
    // between distinct Wrap children — 10 here cost ~20-30px per wrapped line
    // on a phone. Not 0: the lyric leading is now 24/22 ≈ 1.09, so wrapped
    // rows would nearly touch. At 2 a continuation row sits 26px below its own
    // line against 30px to the next line, keeping the hierarchy readable.
    lineRunSpacing: 2.0,
    chordOnlySpacing: 22.0,
    chordToLyricGap: 0.0,
    sectionGap: 14.0,
    sectionLabelRowHeight: compact ? 18.0 : 20.0,
    sectionLabelToLineGap: 4.0,
    lineGap: 6.0,
    chordRowHeight: compact ? 16.0 : 18.0,
    lyricRowHeight: compact ? 21.0 : 24.0,
    directiveLineHeight: 36.0,
    tabBlockVerticalPadding: 16.0,
    lineWidgetBottomPadding: 2.0,
    chordChipHorizontalPadding: 3.0,
  );
}
```

Then in `stageLight` and `stageDark`, build every style from those metrics. Light colours stay as they are today (`colorScheme.primary` for chord and section label, `onSurface`-derived for lyric); dark colours stay as `stageDark` already has them (`#CDCAC0`, `#7ACFA8`, `#6FA98D`, `#D8B892`). The chip colour is the only new colour:

```dart
      // Spec section 2: a filled, low-contrast chip in BOTH themes. A solid
      // saturated chip on the dark page would be the brightest thing on
      // screen, pulling the eye off the words being sung.
      chordChipColor: colorScheme.primary.withValues(alpha: 0.13),   // light
      chordChipColor: const Color(0xFF7ACFA8).withValues(alpha: 0.15), // dark
```

The section label style (both themes):

```dart
    const labelFontSize = compact ? 13.0 : 15.0;   // use a local, not a ternary in the literal
    sectionLabelStyle: TextStyle(
      fontSize: labelFontSize,
      height: metrics.sectionLabelRowHeight / labelFontSize,
      fontWeight: FontWeight.w700,
      // Spec section 3: 0.07em, expressed in logical px because Flutter's
      // letterSpacing is absolute.
      letterSpacing: labelFontSize * 0.07,
      color: sectionLabelColor,
    ),
```

Leave `commentStyle`, `directiveStyle`, `leadingDirectiveStyle`, `tabStyle`, `tabBackgroundColor`, `unknownSectionLabelColor` exactly as they are — they are not in the spec's table and changing them is scope creep.

- [ ] **Step 4: Run the token tests**

```bash
flutter test test/app/reader_theme_test.dart
```

Expected: PASS, including the four breakpoint tests from Task 6.

- [ ] **Step 5: Run the three consistency suites and record what moved**

```bash
flutter test test/presentation/song_reader/song_line_view_estimate_consistency_test.dart test/presentation/song_reader/song_reader_block_estimate_consistency_test.dart test/presentation/song_reader/song_reader_estimate_render_consistency_test.dart
```

Failures are expected here — the type scale changed. For each one, read the failure and classify it:

- **estimate moved UP, still >= rendered** → fine, update the fixture, note the new number for Task 17.
- **estimate fell BELOW rendered** → a real defect. STOP. Use `superpowers:systematic-debugging`. Do not raise the fixture, do not widen a tolerance. The likely causes, in order: the chip padding is not charged (Task 12), the section label sample is still mixed-case and untracked (Task 13), or a style's `height` no longer matches its row-height metric (Step 3 above).

- [ ] **Step 6: Commit**

```bash
git add apps/lyron_app/lib/src/app apps/lyron_app/test
git commit -m "feat(reader): apply the specified reader type scale"
```

---

### Task 8: Wire the resolved metrics into the renderer and the estimator

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_char_metrics.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_line_view.dart`

Task 3 and Task 4 left two `SongReaderMetrics.legacy` placeholders with a `// Commit 2 replaces this with tokens.metrics.` comment. Replace them now.

- [ ] **Step 1: Write the failing test**

Add to `apps/lyron_app/test/presentation/song_reader/song_reader_char_metrics_test.dart`:

```dart
  testWidgets('char metrics carry the resolved breakpoint metrics', (
    tester,
  ) async {
    late SongReaderCharWidths compactMeasured;
    late SongReaderCharWidths regularMeasured;

    Future<SongReaderCharWidths> measureAt(double width) async {
      late SongReaderCharWidths result;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildLightTheme(),
          home: MediaQuery(
            data: MediaQueryData(size: Size(width, 900)),
            child: Builder(
              builder: (context) {
                result = measureSongReaderCharWidths(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      return result;
    }

    compactMeasured = await measureAt(375);
    regularMeasured = await measureAt(834);

    expect(compactMeasured.metrics.lyricRowHeight, 21.0);
    expect(regularMeasured.metrics.lyricRowHeight, 24.0);
    // The larger type must measure wider, or the estimator is reading a style
    // the renderer does not draw with.
    expect(
      regularMeasured.lyricCharWidth,
      greaterThan(compactMeasured.lyricCharWidth),
    );
  });
```

- [ ] **Step 2: Run it and watch it fail**

```bash
flutter test test/presentation/song_reader/song_reader_char_metrics_test.dart
```

Expected: FAIL — `metrics.lyricRowHeight` is 24.0 at both widths (still `legacy`).

- [ ] **Step 3: Implement**

In `song_reader_char_metrics.dart`, replace the placeholder with `metrics: tokens.metrics,` and delete the comment.

In `song_line_view.dart`, replace `final metrics = SongReaderMetrics.legacy;` with `final metrics = tokens.metrics;` and delete the comment.

- [ ] **Step 4: Run the test**

```bash
flutter test test/presentation/song_reader/song_reader_char_metrics_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/lyron_app/lib apps/lyron_app/test
git commit -m "feat(reader): read layout metrics from the resolved tokens"
```

---

### Task 9: The chord chip

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_line_view.dart`
- Test: `apps/lyron_app/test/presentation/song_reader/widgets/song_line_view_test.dart`

Spec section 2: filled low-contrast chip, bold coloured label, 3px horizontal padding, 3px corner radius, in both themes.

- [ ] **Step 1: Write the failing test**

```dart
  testWidgets('a chord renders inside a tinted chip', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLightTheme(),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(834, 1194)),
          child: Scaffold(
            body: SongLineView(
              line: const SongReaderLyricLineProjection(
                segments: [
                  SongReaderSegmentProjection(
                    displayChord: 'C',
                    text: 'hello',
                  ),
                ],
              ),
              viewMode: SongReaderViewMode.chordsAndLyrics,
              sharedFontScale: 1.0,
            ),
          ),
        ),
      ),
    );

    final chip = tester.widget<Container>(
      find.ancestor(
        of: find.text('C'),
        matching: find.byType(Container),
      ).first,
    );
    final decoration = chip.decoration! as BoxDecoration;

    expect(decoration.borderRadius, BorderRadius.circular(3));
    expect(decoration.color, isNotNull);
    expect(
      chip.padding,
      const EdgeInsets.symmetric(horizontal: 3),
    );
  });

  testWidgets('no chip is drawn when the tokens define no chip colour', (
    tester,
  ) async {
    // The chip is a token, not a hardcoded decision — a token set with a null
    // chordChipColor must render the bare label, as it did before PR3.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Theme(
            data: ThemeData(useMaterial3: true).copyWith(
              extensions: <ThemeExtension<dynamic>>[
                ReaderThemeSet(
                  compact: _tokensWithoutChip(compact: true),
                  regular: _tokensWithoutChip(compact: false),
                ),
              ],
            ),
            child: SongLineView(
              line: const SongReaderLyricLineProjection(
                segments: [
                  SongReaderSegmentProjection(
                    displayChord: 'C',
                    text: 'hello',
                  ),
                ],
              ),
              viewMode: SongReaderViewMode.chordsAndLyrics,
              sharedFontScale: 1.0,
            ),
          ),
        ),
      ),
    );

    expect(
      find.ancestor(of: find.text('C'), matching: find.byType(Container)),
      findsNothing,
    );
  });
```

Add the helper at the top of the file:

```dart
ReaderTheme _tokensWithoutChip({required bool compact}) {
  final base = ThemeData(useMaterial3: true);
  return ReaderTheme.stageLight(
    colorScheme: base.colorScheme,
    textTheme: base.textTheme,
    compact: compact,
  ).copyWith(chordChipColor: null);
}
```

`copyWith` uses `??`, so it cannot clear a value back to null. Change `ReaderTheme.copyWith`'s `chordChipColor` parameter to take a sentinel-free explicit form: add a `bool clearChordChipColor = false` flag, or simplest, construct the token set directly in the helper instead of via `copyWith`. Pick whichever is smaller and say which in the commit message.

- [ ] **Step 2: Run it and watch it fail**

```bash
flutter test test/presentation/song_reader/widgets/song_line_view_test.dart
```

Expected: FAIL — no `Container` around the chord label.

- [ ] **Step 3: Implement**

In `_SongLineSegmentView.build`, replace `Text(segment.displayChord!, style: chordStyle)` with:

```dart
          if (chordChipColor == null)
            Text(segment.displayChord!, style: chordStyle)
          else
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: chordChipHorizontalPadding,
              ),
              decoration: BoxDecoration(
                color: chordChipColor,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(segment.displayChord!, style: chordStyle),
            ),
```

Add `final Color? chordChipColor;` and `final double chordChipHorizontalPadding;` to `_SongLineSegmentView`, passed from `SongLineView.build` as `tokens.chordChipColor` and `metrics.chordChipHorizontalPadding`.

The chip must NOT add vertical padding — `chordRowHeight` (18/16) budgets the label's line box only, and vertical padding there would push the render above the estimate.

- [ ] **Step 4: Run the tests**

```bash
flutter test test/presentation/song_reader/widgets/song_line_view_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/lyron_app/lib apps/lyron_app/test
git commit -m "feat(reader): render chords in a tinted chip"
```

---

### Task 10: Charge the chip's width in the estimator

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_fit.dart`
- Test: `apps/lyron_app/test/presentation/song_reader/song_reader_fit_test.dart`

**Trap (a) from the spec.** A chord label now occupies `label width + 2 * chordChipHorizontalPadding`. If the estimator does not charge it, a chord that wraps in the render will not wrap in the estimate — an under-estimate, straight through the contract's floor.

- [ ] **Step 1: Write the failing test**

```dart
  group('chord chip width', () {
    test('a chip widens what a chorded segment occupies', () {
      const line = SongReaderLyricLineProjection(
        segments: [
          SongReaderSegmentProjection(displayChord: 'Cmaj7', text: 'a'),
          SongReaderSegmentProjection(displayChord: 'Gsus4', text: 'b'),
        ],
      );
      final section = const SongReaderSectionProjection(
        label: 'Unlabeled',
        number: null,
        isUnknown: false,
        lines: [line],
      );

      // A width chosen so the two chorded segments only just fit WITHOUT the
      // chip padding; adding 4 x 3px must push one onto a second run.
      const width = 120.0;
      final withoutChip = estimateSongContentHeight(
        sections: [section],
        viewMode: SongReaderViewMode.chordsAndLyrics,
        availableWidth: width,
        fontScale: 1.0,
        chordCharWidth: 11.0,
        lyricCharWidth: 11.0,
        metrics: SongReaderMetrics.legacy.copyWith(
          chordChipHorizontalPadding: 0.0,
        ),
      );
      final withChip = estimateSongContentHeight(
        sections: [section],
        viewMode: SongReaderViewMode.chordsAndLyrics,
        availableWidth: width,
        fontScale: 1.0,
        chordCharWidth: 11.0,
        lyricCharWidth: 11.0,
        metrics: SongReaderMetrics.legacy.copyWith(
          chordChipHorizontalPadding: 3.0,
        ),
      );

      expect(withChip, greaterThan(withoutChip));
    });
  });
```

If the chosen width happens not to straddle a wrap boundary, adjust `width` until it does and leave a comment recording the two occupied widths — do not weaken the assertion to `greaterThanOrEqualTo`.

- [ ] **Step 2: Run it and watch it fail**

```bash
flutter test test/presentation/song_reader/song_reader_fit_test.dart --plain-name "a chip widens what a chorded segment occupies"
```

Expected: FAIL — the two estimates are equal.

- [ ] **Step 3: Implement**

`_segmentPixelWidth` gains `required double chordChipHorizontalPadding` and charges it only when a chord is actually drawn:

```dart
  final chordWidth = (showChords && segment.displayChord != null)
      // The chip's horizontal padding is part of what the label occupies in
      // the render (song_line_view.dart wraps the Text in a Container with
      // EdgeInsets.symmetric(horizontal: ...)). Omitting it here lets a chord
      // that wraps on screen fit in the estimate — an under-estimate.
      ? segment.displayChord!.length * chordCharWidth * chordFactor +
            2 * chordChipHorizontalPadding
      : 0.0;
```

Pass `chordChipHorizontalPadding: metrics.chordChipHorizontalPadding` at both call sites in `_lineItemHeight`.

In `_segmentRowHeight`, the chord's own row count must see the same narrowing. The chip padding is not per-character, so charge it by narrowing the available width rather than by widening the char width — narrower is the safe direction:

```dart
  final chordRows = hasChord
      ? _wordWrapLineCount(
          text: segment.displayChord!,
          // The chip's padding eats into the width the LABEL itself gets.
          // Narrowing the modelled width can only add rows (safe); widening
          // the char width would mis-model the per-character advance.
          effectiveLineWidth: (effectiveLineWidth -
                  2 * chordChipHorizontalPadding)
              .clamp(minEffectiveLineWidth, maxEffectiveLineWidth),
          charWidth: chordCharWidth * chordFactor,
        )
      : 0;
```

- [ ] **Step 4: Run the test and the consistency suites**

```bash
flutter test test/presentation/song_reader/song_reader_fit_test.dart
flutter test test/presentation/song_reader/song_line_view_estimate_consistency_test.dart test/presentation/song_reader/song_reader_block_estimate_consistency_test.dart test/presentation/song_reader/song_reader_estimate_render_consistency_test.dart
```

Expected: the new test passes; consistency suites are green or moved UP only.

- [ ] **Step 5: Commit**

```bash
git add apps/lyron_app/lib apps/lyron_app/test
git commit -m "fix(reader): charge the chord chip's padding in the fit estimate"
```

---

### Task 11: Prove the `w500` lyric width came through

**Files:**
- Test: `apps/lyron_app/test/presentation/song_reader/song_reader_char_metrics_test.dart`

**Trap (c) from the spec.** `lyricCharWidth` measures from the tokens, so the weight change *should* arrive automatically. Verify, do not assume — this test is the whole task.

- [ ] **Step 1: Write the test**

```dart
  testWidgets('lyricCharWidth reflects the w500 lyric weight', (tester) async {
    double widthFor(TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(
          text: 'abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLMNOPQRSTUVWXYZ '
              '0123456789',
          style: style,
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final result = painter.width;
      painter.dispose();
      return result;
    }

    late SongReaderCharWidths measured;
    late ReaderTheme tokens;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildLightTheme(),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(834, 1194)),
          child: Builder(
            builder: (context) {
              tokens = ReaderTheme.of(context);
              measured = measureSongReaderCharWidths(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(tokens.lyricStyle.fontWeight, FontWeight.w500);

    // The measurement must track the ACTUAL rendered weight, not a w400
    // baseline. A heavier face is wider, and a width measured at w400 would
    // fit more characters per estimated line than really fit — an
    // under-estimate.
    final atW400 = widthFor(tokens.lyricStyle.copyWith(
      fontWeight: FontWeight.w400,
    ));
    final atW500 = widthFor(tokens.lyricStyle);

    expect(atW500, greaterThanOrEqualTo(atW400));
    expect(measured.lyricCharWidth * 63, closeTo(atW500, 0.5));
  });
```

`63` is the sample length used in `song_reader_char_metrics.dart` (`_lyricMeasureSample`). Read the constant and use its real `.length` rather than a literal if it has changed.

- [ ] **Step 2: Run it**

```bash
flutter test test/presentation/song_reader/song_reader_char_metrics_test.dart
```

Expected: PASS. If `atW500 == atW400`, the bundled test font has one weight — that is an environment fact, not a defect; keep the `greaterThanOrEqualTo` and rely on the `fontWeight` assertion plus the `closeTo` check, and note it in the commit message.

If the `closeTo` assertion fails, the estimator is measuring a style the renderer does not draw with. That is a real defect — `superpowers:systematic-debugging`.

- [ ] **Step 3: Commit**

```bash
git add apps/lyron_app/test/presentation/song_reader/song_reader_char_metrics_test.dart
git commit -m "test(reader): pin lyricCharWidth to the rendered lyric weight"
```

---

### Task 12: Uppercase, letter-spaced section labels

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_section_grid.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_fit.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_char_metrics.dart`
- Test: `apps/lyron_app/test/presentation/song_reader/widgets/song_reader_section_grid_test.dart`

**Trap (b) from the spec.** Three things must move together or the estimate under-counts a wrapped label:

1. The renderer uppercases the label text.
2. `buildFlowBlocks` / `estimateSectionHeight` must model the **uppercased** string (uppercase glyphs are wider, and the estimator counts characters against a measured average).
3. `_headerMeasureSample` must be uppercase, and the style it is measured with must carry `letterSpacing` (Task 7 already put it on `sectionLabelStyle`, and `TextPainter` honours it).

- [ ] **Step 1: Write the failing test**

```dart
  testWidgets('section labels render uppercase', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLightTheme(),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(834, 1194)),
          child: Scaffold(
            body: SongReaderSectionGrid(
              sections: const [
                SongReaderSectionProjection(
                  label: 'Verse',
                  number: 1,
                  isUnknown: false,
                  lines: [],
                ),
              ],
              viewMode: SongReaderViewMode.chordsAndLyrics,
              sharedFontScale: 1.0,
              columnCount: 1,
              availableHeight: 800,
            ),
          ),
        ),
      ),
    );

    expect(find.text('VERSE 1'), findsOneWidget);
    expect(find.text('Verse 1'), findsNothing);
  });
```

And in `song_reader_fit_test.dart`:

```dart
  test('a section header block models the uppercased label', () {
    // The renderer draws "VERSE 1"; uppercase glyphs are wider than the
    // mixed-case source, so modelling the source string would under-count how
    // many rows a long label wraps into.
    final blocks = buildFlowBlocks(
      sections: const [
        SongReaderSectionProjection(
          label: 'Verse',
          number: 1,
          isUnknown: false,
          lines: [],
        ),
      ],
      hasLeadingDirective: false,
    );

    expect(
      blocks.firstWhere((b) => b.kind == FlowBlockKind.sectionHeader).blockText,
      'VERSE 1',
    );
  });
```

- [ ] **Step 2: Run them and watch them fail**

```bash
flutter test test/presentation/song_reader/widgets/song_reader_section_grid_test.dart --plain-name "section labels render uppercase"
flutter test test/presentation/song_reader/song_reader_fit_test.dart --plain-name "a section header block models the uppercased label"
```

Expected: both FAIL.

- [ ] **Step 3: Implement**

Put the transform in ONE place so the two sides cannot diverge. Add to `song_reader_section_grid.dart`, exported:

```dart
/// The string a section label is actually DRAWN as.
///
/// The estimator models this exact string (song_reader_fit.dart's
/// buildFlowBlocks and estimateSectionHeight), not the source label: uppercase
/// glyphs are wider, so modelling the source would under-count how many rows a
/// long label wraps into.
String songReaderSectionLabelText(String label, int? number) {
  final composed = number == null ? label : '$label $number';
  return composed.toUpperCase();
}
```

In `_buildHeaderWidget`, draw `songReaderSectionLabelText(section.label, section.number)`.

In `song_reader_fit.dart`, both `buildFlowBlocks` (the `headerLabel` local) and `estimateSectionHeight` (its own `headerLabel` local) call the same function. This means `song_reader_fit.dart` imports from `widgets/song_reader_section_grid.dart`, which is the wrong direction — instead move `songReaderSectionLabelText` into `song_reader_metrics.dart` (already imported by both, and already the home of shared renderer/estimator facts) and have the grid import it from there.

In `song_reader_char_metrics.dart`, change the header sample:

```dart
// UPPERCASE, because the section label is drawn uppercase
// (songReaderSectionLabelText). Uppercase glyph advances differ from
// mixed-case ones, and the style this is measured with carries letterSpacing,
// which TextPainter includes in the measured width.
const _headerMeasureSample = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ 0123456789';
```

- [ ] **Step 4: Run them**

```bash
flutter test test/presentation/song_reader/widgets/song_reader_section_grid_test.dart
flutter test test/presentation/song_reader/song_reader_fit_test.dart
```

Expected: PASS.

- [ ] **Step 5: Run the consistency suites**

```bash
flutter test test/presentation/song_reader/song_line_view_estimate_consistency_test.dart test/presentation/song_reader/song_reader_block_estimate_consistency_test.dart test/presentation/song_reader/song_reader_estimate_render_consistency_test.dart
```

Expected: green, or moved UP only.

- [ ] **Step 6: Commit**

```bash
git add apps/lyron_app/lib apps/lyron_app/test
git commit -m "feat(reader): draw and model section labels uppercase"
```

---

### Task 13: 12px side padding and a fixed left edge

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_shell.dart:50`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_compact_surface.dart:314-334`
- Test: `apps/lyron_app/test/presentation/song_reader/widgets/song_reader_compact_surface_test.dart`

Spec section 4. Today `Center` + `ConstrainedBox` pass LOOSE constraints down, so the section grid's `Column` shrink-wraps to its own longest line and is then centred — every section starts from a floating, content-dependent left edge. The fix is a tight width, not a different alignment widget: an `Align` around a `ConstrainedBox` would shrink-wrap exactly the same way.

- [ ] **Step 1: Write the failing test**

```dart
  testWidgets('content starts at a fixed left edge, not centred on its '
      'longest line', (tester) async {
    // Two songs with very different longest-line lengths must put their first
    // section label at the SAME x. Before PR3 the shrink-wrap made that x
    // depend on the content.
    Future<double> labelLeftFor(String longLine) async {
      await tester.pumpWidget(
        _compactSurfaceWith(sections: [_sectionWithLine(longLine)]),
      );
      await tester.pumpAndSettle();
      return tester.getTopLeft(find.text('VERSE 1')).dx;
    }

    final narrow = await labelLeftFor('short');
    final wide = await labelLeftFor(
      'a considerably longer lyric line that occupies much more width',
    );

    expect(narrow, wide);
  });

  testWidgets('content padding is 12 horizontal', (tester) async {
    await tester.pumpWidget(
      _compactSurfaceWith(sections: [_sectionWithLine('short')]),
    );
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.text('VERSE 1')).dx, 12.0);
  });
```

Write `_compactSurfaceWith` and `_sectionWithLine` as local helpers modelled on the existing pump helpers already in that test file — read them first and match their shape, including how they supply the required `SongReaderCompactSurface` callbacks.

- [ ] **Step 2: Run them and watch them fail**

```bash
flutter test test/presentation/song_reader/widgets/song_reader_compact_surface_test.dart --plain-name "fixed left edge"
```

Expected: FAIL — the two x values differ.

- [ ] **Step 3: Implement**

`song_reader_shell.dart:50`:

```dart
  // Spec section 4: 12px side padding. Measured against the reference song,
  // 12/16/24px all allow the same largest non-wrapping lyric size, but a
  // narrower margin can only help songs with longer lines, never hurt them.
  static const _contentPadding = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 14,
  );
```

`song_reader_compact_surface.dart`, replacing the `Center` + `ConstrainedBox`:

```dart
                              // A fixed left edge, not a centred shrink-wrap.
                              // Center + ConstrainedBox passed LOOSE
                              // constraints down, so the section grid's Column
                              // sized itself to its own longest line and was
                              // then centred — every section started from a
                              // content-dependent left edge. A tight width is
                              // what fixes that; swapping Center for Align
                              // would shrink-wrap identically.
                              child: SizedBox(
                                width: math.min(
                                  constraints.maxWidth,
                                  widget.maxContentWidth,
                                ),
                                child: Padding(
                                  padding: widget.contentPadding,
                                  child: SongReaderSectionGrid(
                                    // ... unchanged
                                  ),
                                ),
                              ),
```

Add `import 'dart:math' as math;` if absent. The 960px `maxContentWidth` cap is retained — it does not bind at tablet widths.

Do not change `song_reader_expanded_surface.dart`'s layout; the expanded shell is out of scope beyond adopting tokens.

- [ ] **Step 4: Run the widget tests**

```bash
flutter test test/presentation/song_reader/widgets/song_reader_compact_surface_test.dart
```

Expected: PASS.

- [ ] **Step 5: Run everything**

```bash
flutter test
```

Expected: green, or fixtures that moved UP only.

- [ ] **Step 6: Commit**

```bash
git add apps/lyron_app/lib apps/lyron_app/test
git commit -m "feat(reader): left-align reader content at a fixed 12px edge"
```

---

### Task 14: The spec's three new estimator cases

**Files:**
- Test: `apps/lyron_app/test/presentation/song_reader/song_reader_estimate_render_consistency_test.dart`

The spec's Testing section names exactly three new cases. Each renders a real widget, measures it, and asserts `estimated >= rendered`. Model them on the fixtures already in that file — read one first and match its pump/measure helper exactly rather than inventing a second measurement path.

- [ ] **Step 1: Write the three cases**

```dart
  testWidgets('a chord label with chip padding at a width where it wraps', (
    tester,
  ) async {
    // The chip's 3px per side is the difference between wrapping and not at
    // this width; without it the estimate would sit below the render.
    await _expectEstimateAtLeastRendered(
      tester,
      width: 140,
      sections: [
        _section(lines: [
          _lyricLine([
            ('Cmaj7sus4', 'aaa '),
            ('G#m7b5', 'bbb'),
          ]),
        ]),
      ],
    );
  });

  testWidgets('an uppercased, letter-spaced section label at a narrow width', (
    tester,
  ) async {
    await _expectEstimateAtLeastRendered(
      tester,
      width: 120,
      sections: [
        _section(
          label: 'Instrumental Bridge Repeat',
          number: 2,
          lines: [_lyricLine([(null, 'x')])],
        ),
      ],
    );
  });

  testWidgets('a w500 lyric line at a width where the weight shifts the wrap '
      'point', (tester) async {
    await _expectEstimateAtLeastRendered(
      tester,
      width: 200,
      sections: [
        _section(lines: [
          _lyricLine([(null, 'one two three four five six seven eight')]),
        ]),
      ],
    );
  });
```

Name the helpers to match whatever the file already uses; the point is the three scenarios and the one-sided assertion, not these exact helper names.

- [ ] **Step 2: Run them**

```bash
flutter test test/presentation/song_reader/song_reader_estimate_render_consistency_test.dart
```

Expected: PASS. A failure where estimated < rendered is a real defect — `superpowers:systematic-debugging`, no fixture bumping.

- [ ] **Step 3: Run all three suites at both breakpoints**

```bash
flutter test test/presentation/song_reader/song_line_view_estimate_consistency_test.dart test/presentation/song_reader/song_reader_block_estimate_consistency_test.dart test/presentation/song_reader/song_reader_estimate_render_consistency_test.dart
```

If the suites pump at a single surface size, add a phone-width variant of at least one fixture in each suite so the compact token set is covered too — an untested breakpoint is an untested estimator.

- [ ] **Step 4: Commit**

```bash
git add apps/lyron_app/test
git commit -m "test(reader): cover chip, uppercase label and w500 wrap points"
```

---

### Task 15: Amend ADR-033

**Files:**
- Modify: `docs/architecture/decisions/ADR-033-reader-design-token-layer.md`

ADR-033's Decision section currently ends with: *"Spacing constants (song_reader_metrics.dart, song_reader_fit.dart) are deliberately NOT moved into the extension — they already live in one shared place, are theme-independent, and copying them in would recreate a second definition of something that already has exactly one."* That is now false. Amend, do not silently contradict.

- [ ] **Step 1: Rewrite the spacing sentence**

Replace it with:

```markdown
Spacing was initially left out of the extension on the grounds that it already
lived in one shared place and did not vary by theme. **Amended 2026-08-12 (PR3
of this slice).** The second half of that reasoning still holds — spacing does
not vary by theme, and `ReaderTheme.stageLight` and `ReaderTheme.stageDark`
are pinned to identical `SongReaderMetrics` by `reader_theme_test.dart`. The
first half did not survive the 600px type-scale breakpoint
(`docs/specs/2026-08-09-song-presentation.md` section 7): row heights and gaps
now differ between the phone and tablet/desktop sets, so they cannot be
compile-time constants, and the value that resolves them is the same viewport
width that resolves the type scale they have to match. Keeping them apart would
have meant two independent breakpoint resolutions — the exact drift this
extension exists to prevent, reintroduced one level up.

The constants therefore became `SongReaderMetrics`
(`song_reader_metrics.dart`), a value object carried by `ReaderTheme` and
threaded through the estimator the way `SongReaderFitTextScale` already was.
There is still exactly one definition per value; it is now resolved rather than
constant. The registered extension is `ReaderThemeSet`, holding a `compact` and
a `regular` `ReaderTheme`, because `ThemeData` is built at app start with no
`MediaQuery` in scope. `ReaderTheme.of(context)` performs the resolution from
`MediaQuery.sizeOf(context).width`, and both the reader widgets and
`measureSongReaderCharWidths` go through it with the same `BuildContext` — so
the renderer and the estimator cannot resolve to different sets.
```

- [ ] **Step 2: Fix the two stale PR numbers**

The slice was re-split on 2026-08-10 and the ADR still uses the old numbering:

- Scope line: "rebuilt in PR3" → "rebuilt in PR4".
- Consequences: "deferred to PR3 of this slice, which rebuilds the chrome" → "PR4".
- `reader_theme.dart`'s `chordChipColor` doc says "PR2 introduces the tinted chip" → "PR3 introduces the tinted chip" (and update it to past tense, since it now exists).

- [ ] **Step 3: Add the consequence**

Append to Consequences:

```markdown
- The reader's row heights and gaps are now breakpoint-dependent and resolved
  through `ReaderTheme.of(context)`. A widget that needs them must go through
  that call rather than importing a constant; `song_reader_metrics.dart` no
  longer exports any.
```

- [ ] **Step 4: Commit**

```bash
git add docs/architecture/decisions/ADR-033-reader-design-token-layer.md apps/lyron_app/lib/src/app/reader_theme.dart
git commit -m "docs(adr-033): move reader spacing into the token layer"
```

---

### Task 16: Update the spec

**Files:**
- Modify: `docs/specs/2026-08-09-song-presentation.md`

Two things the spec does not yet record. Both are facts this round measured.

- [ ] **Step 1: Record the `lineRunSpacing` meaning change**

In section 1, after the token table, add:

```markdown
**`lineRunSpacing`: 10 → 2.** This value is not in the table above because it
did not exist as a type-scale decision until PR2 changed what it means. Before
PR2, a single-segment lyric line was one `Text` that wrapped internally at
plain text leading, and `lineRunSpacing` only ever separated distinct `Wrap`
children. Since PR2 a line is one box per word in the outer `Wrap`, so the same
10px now also lands between a single line's OWN wrapped rows. Measured on a
380px column, one wrapped lyric line went from **114px to 144px** — around
20-30px per line on a phone, where wrapping is the normal state (see "Phone
behaviour").

It is 2 rather than 0 because the new lyric leading is tight: `height` is
derived as `lyricRowHeight / lyricSize` (24/22 ≈ 1.09, against 1.25 before), so
wrapped rows would otherwise nearly touch. At 2 a continuation row sits 26px
below its own line against 24 + 6 = 30px to the next line, so a wrap still
reads as closer to its own line than to the following one.
```

- [ ] **Step 2: Record the derived-`height` invariant**

In "Invariants this work must not break", under "The fit estimator upper bound", add a fourth item:

```markdown
4. **A row-height token and its text style must agree.** The estimator charges
   `lyricRowHeight` / `chordRowHeight` / `sectionLabelRowHeight` per rendered
   row; a `Text`'s real row height is `fontSize * style.height`. The token
   factories therefore DERIVE each style's `height` from its row-height metric
   rather than typing both as literals, and `reader_theme_test.dart` asserts
   the equality. Two independent literals here is the same class of drift as
   two independent copies of a style.
```

- [ ] **Step 3: Mark the slice item done**

In "Slice / PR split", mark item 3 the way item 1 is marked: `3. **Type scale.** *(landed: #NN)*` — fill in the PR number in Task 19, after the PR exists.

- [ ] **Step 4: Commit**

```bash
git add docs/specs/2026-08-09-song-presentation.md
git commit -m "docs(spec): record the lineRunSpacing meaning change"
```

---

### Task 17: Re-measure the deferred conservatism doc

**Files:**
- Modify: `docs/deferred/2026-07-28-reader-fit-conservatism-margin.md`

That file is 576 lines. **Do not read it end to end.** Locate its tables first:

```bash
grep -n "^| \|^## \|^### " docs/deferred/2026-07-28-reader-fit-conservatism-margin.md
```

Then read only the sections around the tables you need to change.

This deferred item is **not resolved** by this work — the estimator stays a deliberate upper bound. Update the numbers, keep the item open.

- [ ] **Step 1: Re-measure**

For every row in every measured table, re-run the case under the new type scale and record the new rendered / estimated / margin figures. The consistency suites already compute both numbers; add a temporary `print` in the shared assertion helper, run the suites, collect the output, then remove the `print`.

- [ ] **Step 2: Add a dated section**

```markdown
## Type scale (2026-08-12)

Re-measured under PR3's type scale (`docs/specs/2026-08-09-song-presentation.md`
section 1): 22/19px lyrics at `w500`, 15/13px chords in a 3px-padded chip,
uppercase letter-spaced section labels, and `lineRunSpacing` 10 → 2.

The margins below moved because the modelled quantities moved, not because the
model changed direction: the estimator is still a one-sided upper bound, and
this item is still open. Two changes tightened it in the safe direction — the
chip's padding is now charged per drawn chord, and the section label is modelled
as the uppercased string it is actually drawn as — so where a margin shrank, it
shrank because the estimate got MORE accurate, not because the floor moved.
```

- [ ] **Step 3: Commit**

```bash
git add docs/deferred/2026-07-28-reader-fit-conservatism-margin.md
git commit -m "docs(deferred): re-measure reader fit margins under the new type scale"
```

---

### Task 18: Visual verification

**REQUIRED SUB-SKILL: `superpowers:verification-before-completion`.**

Screenshots, not assertions. The reader renders through CanvasKit, so its text is not in the DOM and cannot be asserted from it.

- [ ] **Step 1: Run the app**

```bash
./scripts/run-authenticated-app.sh
```

That script brings up local Supabase, seeds the demo user, and completes the magic-link sign-in.

- [ ] **Step 2: Capture four after-shots**

Open the same song in all four combinations and save each to the session scratchpad:

| size | theme |
|---|---|
| 834x1194 (tablet portrait — the primary target) | light |
| 834x1194 | dark |
| 375x812 | light |
| 375x812 | dark |

- [ ] **Step 3: Capture the matching before-shots**

```bash
git stash
```

(or check out `main` in a scratch worktree), capture the same four, restore.

- [ ] **Step 4: Check each pair against the spec**

- Lyrics visibly larger AND more song visible per screen — both, not one.
- Chords sit in a low-contrast chip in both themes; on the dark page the chip must not be the brightest thing on screen.
- Section labels uppercase and letter-spaced, no chip and no rule.
- Every section starts at the same left edge, ~12px in, regardless of its longest line.
- Wrapped rows of one line sit visibly closer together than two distinct lines.

- [ ] **Step 5: Put the four after-shots in the PR body**

If any check fails, that is a defect to fix, not a caveat to write down.

---

### Task 19: Ship

**REQUIRED SUB-SKILL: `superpowers:finishing-a-development-branch`.**

- [ ] **Step 1: Final full verification**

```bash
flutter analyze
flutter test
git status --short
```

Expected: analyze clean, whole suite green. `git status` must still show the two untracked-by-us modifications (`android/gradle.properties`, `pubspec.yaml`) as **unstaged and uncommitted**.

- [ ] **Step 2: Confirm no dependency drift**

```bash
git diff main --stat -- '*pubspec.yaml' '*pubspec.lock'
```

Expected: **empty**. If not, revert those files — PR2 leaked dependency bumps and this PR must not.

- [ ] **Step 3: Confirm the two-commit shape**

```bash
git log --oneline main..HEAD
```

Expected: exactly two commits — the inert plumbing, then the new values. Squash Commit 2's task commits into one if they are still separate.

- [ ] **Step 4: Confirm Commit 1 really was inert**

```bash
git show --stat $(git rev-list --reverse main..HEAD | head -1)
```

No pre-existing test fixture may appear with a changed expectation.

- [ ] **Step 5: Open the PR**

Body must contain: the spec sections implemented; the two-commit shape and why; the `lineRunSpacing` 10 → 2 decision with the 114→144px measurement; the ADR-033 amendment; which consistency fixtures moved and in which direction (with the reason each moved UP); and the four screenshots.

- [ ] **Step 6: Merge only on green CI**

Then fill the PR number into the spec's "Slice / PR split" item 3 (Task 16 Step 3).

---

## Self-review notes

**Spec coverage.** Section 1 typography → Tasks 7, 8. Section 1 spacing → Tasks 1, 2, 4, 7. Section 2 chip → Tasks 9, 10. Section 3 labels → Task 12. Section 4 horizontal layout → Task 13. Section 7 breakpoint → Task 6. Section 8 token layer → Tasks 6, 15. Testing section's three new estimator cases → Task 14; widget tests for left alignment → Task 13; visual verification → Task 18. Deferred-doc re-measure → Task 17.

**Deliberately not covered here**, because they belong to PR4 and the spec's split says so: bottom bar, tap-revealed top bar, control rail, phone chrome adaptation, safe-area handling, and the second ADR for the chrome model. Section 5's dark palette landed in PR1; section 6 is PR4 entirely.

**Known open point for the executing agent.** Task 9 Step 1 needs `ReaderTheme.copyWith` to be able to clear `chordChipColor` back to null, which `??` cannot express. Two acceptable fixes are given; pick the smaller one and record which in the commit message. This is the only place in the plan where the shape is left to the implementer, and it is a two-line decision with no bearing on the estimator contract.
