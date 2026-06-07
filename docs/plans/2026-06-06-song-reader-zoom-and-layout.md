# Song Reader Zoom And Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Put the reader scrollbar at the physical screen edge at every width, guarantee the song body never scrolls horizontally, and add pinch-to-zoom plus a double-tap fit-to-screen whose level is remembered per user and song locally.

**Architecture:** Keep the parsed song and projection canonical. Extract the existing height estimation into a pure function reused by both the section grid and a new fit-to-screen calculator. Restructure the reader so the `Scrollbar` + scroll view are full-width and all max-width/padding live inside the scroll content. Bound each lyric segment to the line width so it always reflows. Drive zoom through the existing `sharedFontScale`, widened to 0.25–3.0, with a two-pointer scale gesture and a fit/restore double-tap; persist the value through a local `shared_preferences`-backed store keyed by user+song.

**Tech Stack:** Flutter, Material 3, Riverpod, drift (existing), shared_preferences (new), flutter_test.

**Spec:** `docs/specs/2026-06-06-song-reader-zoom-and-layout.md`

**Branch:** `feat/song-reader-zoom` (already created).

**Working directory for all `flutter` commands:** `apps/lyron_app`.

---

### Task 1: Widen the shared font-scale range to 0.25–3.0

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_state.dart`
- Test: `apps/lyron_app/test/presentation/song_reader/song_reader_state_test.dart` (create if absent; otherwise add cases)

- [ ] **Step 1: Write failing tests for the new bounds**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';

void main() {
  group('SongReaderState font scale bounds', () {
    test('clamps below the new minimum to 0.25', () {
      final state = SongReaderState(sharedFontScale: 0.1);
      expect(state.sharedFontScale, 0.25);
    });

    test('allows values between 0.25 and 3.0 unchanged', () {
      expect(SongReaderState(sharedFontScale: 0.25).sharedFontScale, 0.25);
      expect(SongReaderState(sharedFontScale: 2.5).sharedFontScale, 2.5);
      expect(SongReaderState(sharedFontScale: 3.0).sharedFontScale, 3.0);
    });

    test('clamps above the new maximum to 3.0', () {
      expect(SongReaderState(sharedFontScale: 5.0).sharedFontScale, 3.0);
    });

    test('non-finite or non-positive falls back to default 1.0', () {
      expect(SongReaderState(sharedFontScale: 0).sharedFontScale, 1.0);
      expect(SongReaderState(sharedFontScale: double.nan).sharedFontScale, 1.0);
    });
  });
}
```

- [ ] **Step 2: Run the tests; verify they fail**

Run: `flutter test test/presentation/song_reader/song_reader_state_test.dart`
Expected: FAIL — current max is 2.0, current min is 0.5.

- [ ] **Step 3: Update the clamp constants**

In `song_reader_state.dart`, change `_normalizeSharedFontScale`:

```dart
  static const minSharedFontScale = 0.25;
  static const maxSharedFontScale = 3.0;
  static const defaultSharedFontScale = 1.0;

  static double _normalizeSharedFontScale(double value) {
    if (!value.isFinite || value <= 0) {
      return defaultSharedFontScale;
    }
    if (value < minSharedFontScale) {
      return minSharedFontScale;
    }
    if (value > maxSharedFontScale) {
      return maxSharedFontScale;
    }
    return value;
  }
```

(Replace the existing private `minScale`/`maxScale`/`defaultScale` locals with these public static constants so other files can reuse them.)

- [ ] **Step 4: Run the tests; verify they pass**

Run: `flutter test test/presentation/song_reader/song_reader_state_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/lyron_app/lib/src/presentation/song_reader/song_reader_state.dart apps/lyron_app/test/presentation/song_reader/song_reader_state_test.dart
git commit -m "feat(reader): widen shared font scale range to 0.25-3.0"
```

---

### Task 2: Extract a pure height-estimation + fit-scale calculator

This makes `SongReaderSectionGrid`'s height estimate reusable and is the single source of truth for fit-to-screen.

**Files:**
- Create: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_fit.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_section_grid.dart`
- Test: `apps/lyron_app/test/presentation/song_reader/song_reader_fit_test.dart`

- [ ] **Step 1: Write failing unit tests for the calculator**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_fit.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';

SongReaderSectionProjection _section(int lyricLines) => SongReaderSectionProjection(
      label: 'Unlabeled',
      number: null,
      lines: [
        for (var i = 0; i < lyricLines; i++)
          SongReaderLyricLineProjection(segments: const [
            SongReaderSegmentProjection(displayChord: null, text: 'a fairly ordinary lyric line here'),
          ]),
      ],
    );

void main() {
  group('estimateSongContentHeight', () {
    test('grows with more content', () {
      final small = estimateSongContentHeight(
        sections: [_section(2)], viewMode: SongReaderViewMode.lyricsOnly,
        availableWidth: 360, fontScale: 1.0,
      );
      final big = estimateSongContentHeight(
        sections: [_section(40)], viewMode: SongReaderViewMode.lyricsOnly,
        availableWidth: 360, fontScale: 1.0,
      );
      expect(big, greaterThan(small));
    });

    test('grows with font scale', () {
      final s1 = estimateSongContentHeight(
        sections: [_section(10)], viewMode: SongReaderViewMode.lyricsOnly,
        availableWidth: 360, fontScale: 1.0,
      );
      final s2 = estimateSongContentHeight(
        sections: [_section(10)], viewMode: SongReaderViewMode.lyricsOnly,
        availableWidth: 360, fontScale: 2.0,
      );
      expect(s2, greaterThan(s1));
    });
  });

  group('resolveFitFontScale', () {
    test('returns a scale whose estimated height fits the viewport', () {
      final scale = resolveFitFontScale(
        sections: [_section(30)], viewMode: SongReaderViewMode.lyricsOnly,
        availableWidth: 360, availableHeight: 640,
        minScale: SongReaderState.minSharedFontScale,
        maxScale: SongReaderState.maxSharedFontScale,
      );
      final height = estimateSongContentHeight(
        sections: [_section(30)], viewMode: SongReaderViewMode.lyricsOnly,
        availableWidth: 360, fontScale: scale,
      );
      expect(height, lessThanOrEqualTo(640 + 0.5));
      expect(scale, inInclusiveRange(SongReaderState.minSharedFontScale, SongReaderState.maxSharedFontScale));
    });

    test('a short song fits at max scale', () {
      final scale = resolveFitFontScale(
        sections: [_section(1)], viewMode: SongReaderViewMode.lyricsOnly,
        availableWidth: 360, availableHeight: 2000,
        minScale: SongReaderState.minSharedFontScale,
        maxScale: SongReaderState.maxSharedFontScale,
      );
      expect(scale, SongReaderState.maxSharedFontScale);
    });

    test('a huge song clamps to min scale', () {
      final scale = resolveFitFontScale(
        sections: [_section(500)], viewMode: SongReaderViewMode.lyricsOnly,
        availableWidth: 360, availableHeight: 200,
        minScale: SongReaderState.minSharedFontScale,
        maxScale: SongReaderState.maxSharedFontScale,
      );
      expect(scale, SongReaderState.minSharedFontScale);
    });
  });
}
```

(Adjust the `SongReaderSectionProjection` / `SongReaderLyricLineProjection` / `SongReaderSegmentProjection` constructors in the helper to match their real signatures in `song_reader_projection.dart`.)

- [ ] **Step 2: Run the tests; verify they fail (import not found)**

Run: `flutter test test/presentation/song_reader/song_reader_fit_test.dart`
Expected: FAIL — `song_reader_fit.dart` does not exist.

- [ ] **Step 3: Create the pure calculator by lifting the grid's math**

Move the height-estimation constants and the body of `_estimatedSectionHeight` / `_columnHeightEstimate` out of `song_reader_section_grid.dart` into `song_reader_fit.dart` as top-level pure functions:

```dart
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';

const _sectionGap = 20.0;
const _headerHeight = 40.0;
const _lineGap = 10.0;
const _linePadding = 24.0;
const _characterWidthEstimate = 10.0;
const _chordRowHeight = 20.0;
const _lyricRowHeight = 24.0;
const _directiveLineHeight = 36.0;
const _tabBlockVerticalPadding = 16.0;

double estimateSectionHeight({
  required SongReaderSectionProjection section,
  required SongReaderViewMode viewMode,
  required double maxWidth,
  required double fontScale,
}) {
  final hasHeader = !(section.label == 'Unlabeled' && section.number == null);
  final headerHeight = hasHeader ? _headerHeight : 0.0;
  final effectiveLineWidth = (maxWidth - _linePadding).clamp(120.0, 1200.0);
  final charsPerLine =
      (effectiveLineWidth / (_characterWidthEstimate * fontScale)).floor().clamp(12, 140);
  var linesHeight = 0.0;
  for (final item in section.lines) {
    switch (item) {
      case SongReaderLyricLineProjection():
        final text = item.segments.map((s) => s.text).join();
        final lyricLength = text.trimRight().length;
        final hasChord = viewMode == SongReaderViewMode.chordsAndLyrics &&
            item.segments.any((s) => s.displayChord != null);
        final wrapCount = lyricLength == 0 ? 1 : (lyricLength / charsPerLine).ceil().clamp(1, 14);
        final chordRowHeight = hasChord ? (_chordRowHeight * fontScale) : 0.0;
        linesHeight += chordRowHeight + wrapCount * (_lyricRowHeight * fontScale) + _lineGap;
      case SongReaderCommentProjection():
        final len = item.text.length;
        final wrap = len == 0 ? 1 : (len / charsPerLine).ceil().clamp(1, 14);
        linesHeight += wrap * (_lyricRowHeight * fontScale) + _lineGap;
      case SongReaderTabProjection():
        linesHeight += item.rawLines.length * (_lyricRowHeight * fontScale) + _lineGap + _tabBlockVerticalPadding;
      case SongReaderDirectiveProjection():
        linesHeight += _directiveLineHeight;
    }
  }
  return headerHeight + linesHeight + _sectionGap;
}

double estimateSongContentHeight({
  required List<SongReaderSectionProjection> sections,
  required SongReaderViewMode viewMode,
  required double availableWidth,
  required double fontScale,
}) {
  return sections.fold<double>(
    0,
    (sum, s) => sum + estimateSectionHeight(
      section: s, viewMode: viewMode, maxWidth: availableWidth, fontScale: fontScale,
    ),
  );
}

/// Largest font scale in [minScale, maxScale] whose estimated total height
/// fits [availableHeight]. Width never constrains because lyric segments reflow.
double resolveFitFontScale({
  required List<SongReaderSectionProjection> sections,
  required SongReaderViewMode viewMode,
  required double availableWidth,
  required double availableHeight,
  required double minScale,
  required double maxScale,
}) {
  double heightAt(double scale) => estimateSongContentHeight(
        sections: sections, viewMode: viewMode,
        availableWidth: availableWidth, fontScale: scale,
      );
  if (heightAt(maxScale) <= availableHeight) return maxScale;
  if (heightAt(minScale) > availableHeight) return minScale;
  var lo = minScale, hi = maxScale;
  for (var i = 0; i < 24; i++) {
    final mid = (lo + hi) / 2;
    if (heightAt(mid) <= availableHeight) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return lo;
}
```

- [ ] **Step 4: Re-point the section grid at the shared functions**

In `song_reader_section_grid.dart`, delete the now-duplicated private constants and `_estimatedSectionHeight` / `_columnHeightEstimate` / `_singleColumnHeightEstimate` bodies, importing `song_reader_fit.dart` and calling `estimateSectionHeight(... fontScale: sharedFontScale ...)` / `estimateSongContentHeight(...)` instead. Keep the column-splitting logic in the grid; only the height math moves. The grid's `_directiveLineHeight` usage stays (re-export it from `song_reader_fit.dart` or keep a local copy used only for the leading directive).

- [ ] **Step 5: Run fit tests and the existing grid tests; verify they pass**

Run: `flutter test test/presentation/song_reader/song_reader_fit_test.dart`
Run: `flutter test test/presentation/song_reader/` (existing grid/column tests must still pass — column behavior is unchanged)
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add apps/lyron_app/lib/src/presentation/song_reader/song_reader_fit.dart apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_section_grid.dart apps/lyron_app/test/presentation/song_reader/song_reader_fit_test.dart
git commit -m "refactor(reader): extract pure height estimation + fit-scale calculator"
```

---

### Task 3: Guarantee no horizontal overflow in lyric lines

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_line_view.dart`
- Test: `apps/lyron_app/test/presentation/song_reader/song_line_view_test.dart`

- [ ] **Step 1: Write a failing widget test for a long unbreakable token**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_line_view.dart';

void main() {
  testWidgets('long lyric segment wraps and does not overflow', (tester) async {
    final line = SongReaderLyricLineProjection(segments: const [
      SongReaderSegmentProjection(
        displayChord: 'G',
        text: 'supercalifragilisticexpialidocioussupercalifragilisticexpialidocious',
      ),
    ]);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 200,
          child: SongLineView(
            line: line,
            viewMode: SongReaderViewMode.chordsAndLyrics,
            sharedFontScale: 3.0,
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull); // no RenderFlex overflow
    final size = tester.getSize(find.byType(SongLineView));
    expect(size.width, lessThanOrEqualTo(200 + 0.5));
  });
}
```

- [ ] **Step 2: Run; verify it fails with an overflow exception**

Run: `flutter test test/presentation/song_reader/song_line_view_test.dart`
Expected: FAIL — current `Wrap` lets the segment exceed 200px (overflow exception / width > 200).

- [ ] **Step 3: Bound each segment to the available line width**

In `song_line_view.dart`, wrap the `Wrap` in a `LayoutBuilder`, pass `constraints.maxWidth` into `_SongLineSegmentView`, and constrain the segment's lyric `Text`:

```dart
return Padding(
  padding: const EdgeInsets.only(bottom: 2),
  child: LayoutBuilder(
    builder: (context, constraints) {
      final maxLineWidth = constraints.maxWidth.isFinite
          ? constraints.maxWidth
          : MediaQuery.sizeOf(context).width;
      return Wrap(
        spacing: spacing,
        runSpacing: _lineRunSpacing,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          for (final segment in line.segments)
            _SongLineSegmentView(
              segment: segment,
              viewMode: viewMode,
              chordStyle: chordStyle,
              lyricStyle: lyricStyle,
              maxWidth: maxLineWidth,
            ),
        ],
      );
    },
  ),
);
```

In `_SongLineSegmentView`, add `final double maxWidth;` and wrap the lyric `Text`:

```dart
if (showLyric)
  ConstrainedBox(
    constraints: BoxConstraints(maxWidth: maxWidth),
    child: Text(segment.text, style: lyricStyle, softWrap: true),
  ),
```

- [ ] **Step 4: Run; verify it passes**

Run: `flutter test test/presentation/song_reader/song_line_view_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/lyron_app/lib/src/presentation/song_reader/widgets/song_line_view.dart apps/lyron_app/test/presentation/song_reader/song_line_view_test.dart
git commit -m "fix(reader): wrap long lyric segments to prevent horizontal overflow"
```

---

### Task 4: Full-width scrollbar at the physical edge

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_screen.dart` (the `Center`/`ConstrainedBox`/`Padding` block at ~818-833)
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_compact_surface.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_expanded_surface.dart`
- Test: `apps/lyron_app/test/presentation/song_reader/song_reader_scrollbar_test.dart`

- [ ] **Step 1: Write a failing widget test asserting full-width scroll view**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// import the compact surface + build a minimal projection with several sections.

void main() {
  testWidgets('scroll view spans full width so the thumb is at the edge', (tester) async {
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Pump SongReaderCompactSurface (or the screen) with a short song.
    // ... build widget under test ...

    final scrollable = find.byType(Scrollbar);
    expect(scrollable, findsOneWidget);
    final box = tester.getSize(find.byType(SingleChildScrollView));
    expect(box.width, greaterThanOrEqualTo(1400 - 0.5)); // not capped to 960
  });
}
```

(Build the surface with a minimal `SongReaderProjection`; reuse existing test helpers/fixtures in `test/presentation/song_reader/` for projection construction.)

- [ ] **Step 2: Run; verify it fails**

Run: `flutter test test/presentation/song_reader/song_reader_scrollbar_test.dart`
Expected: FAIL — the scroll view is currently capped at 960.

- [ ] **Step 3: Move max-width/centering/padding inside the scroll content**

In `song_reader_screen.dart`, replace the `Center > ConstrainedBox > Padding > Column(Expanded(readerSurface))` wrapper so the surface fills the full width (the surface owns the scroll view):

```dart
return Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [Expanded(child: readerSurface)],
);
```

Pass the content max-width and horizontal padding into the surface as parameters:

```dart
maxContentWidth: layout.shell == SongReaderShell.expanded
    ? _expandedContentWidth
    : _contentWidth,
contentPadding: _contentPadding,
```

In `song_reader_compact_surface.dart`, add a `ScrollController` (create in `initState`, dispose in `dispose`), and structure the scroll region so the `Scrollbar` and scroll view are full width while the content is centered/capped/padded inside:

```dart
Scrollbar(
  controller: _scrollController,
  child: SingleChildScrollView(
    controller: _scrollController,
    child: Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: widget.maxContentWidth),
        child: Padding(
          padding: widget.contentPadding,
          child: SongReaderSectionGrid(/* unchanged args */),
        ),
      ),
    ),
  ),
)
```

Apply the same `Scrollbar` + `ScrollController` + inner `Center/ConstrainedBox/Padding` pattern to the scroll view in `song_reader_expanded_surface.dart`.

- [ ] **Step 4: Run the scrollbar test + the full reader widget tests**

Run: `flutter test test/presentation/song_reader/`
Expected: PASS. Update any existing reader-layout test that asserted the old capped width.

- [ ] **Step 5: Commit**

```bash
git add apps/lyron_app/lib/src/presentation/song_reader/song_reader_screen.dart apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_compact_surface.dart apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_expanded_surface.dart apps/lyron_app/test/presentation/song_reader/song_reader_scrollbar_test.dart
git commit -m "fix(reader): full-width scrollbar with content centered inside scroll view"
```

---

### Task 5: Pinch-to-zoom (two-pointer scale gesture)

**Files:**
- Create: `apps/lyron_app/lib/src/presentation/song_reader/widgets/two_pointer_scale_recognizer.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_compact_surface.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_screen.dart` (add `onSetFontScale` handler + thread callback)
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_controller.dart` (no change if `setSharedFontScale` is enough; add a passthrough if needed)
- Test: `apps/lyron_app/test/presentation/song_reader/song_reader_pinch_test.dart`

- [ ] **Step 1: Add the two-pointer-only recognizer**

```dart
import 'package:flutter/gestures.dart';

/// A ScaleGestureRecognizer that only accepts the gesture once two pointers
/// are down, so single-finger drags fall through to the scroll view.
class TwoPointerScaleGestureRecognizer extends ScaleGestureRecognizer {
  TwoPointerScaleGestureRecognizer({super.debugOwner});

  final Set<int> _pointers = {};

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _pointers.add(event.pointer);
    super.addAllowedPointer(event);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _pointers.clear();
    super.didStopTrackingLastPointer(pointer);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      _pointers.remove(event.pointer);
    }
    super.handleEvent(event);
  }

  @override
  void rejectGesture(int pointer) {
    _pointers.remove(pointer);
    super.rejectGesture(pointer);
  }
}
```

> Implementation note: the precise way to make scale lose the arena for a single pointer may need `acceptGesture`/`rejectGesture` gating on `_pointers.length < 2`. Validate against the test in Step 3 (one-finger drag must scroll). If subclassing proves brittle, fall back to a `GestureDetector` with `onScaleUpdate` gated on `details.pointerCount >= 2` plus `Listener`-tracked pointer count.

- [ ] **Step 2: Write failing tests for pinch + preserved scroll**

```dart
// pseudo-structure; fill with the real surface builder + projection fixture
testWidgets('two-finger pinch increases font scale', (tester) async {
  double? lastScale;
  // build SongReaderCompactSurface with onSetFontScale: (s) => lastScale = s
  final center = tester.getCenter(find.byType(SongReaderCompactSurface));
  final g1 = await tester.startGesture(center.translate(-20, 0));
  final g2 = await tester.startGesture(center.translate(20, 0));
  await g1.moveBy(const Offset(-40, 0));
  await g2.moveBy(const Offset(40, 0));
  await tester.pump();
  await g1.up(); await g2.up();
  expect(lastScale, isNotNull);
  expect(lastScale, greaterThan(1.0));
});

testWidgets('one-finger drag still scrolls, not zoom', (tester) async {
  // build a tall song; record onSetFontScale calls
  await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -200));
  await tester.pump();
  // assert content scrolled (offset changed) and onSetFontScale not called
});
```

- [ ] **Step 3: Run; verify failure**

Run: `flutter test test/presentation/song_reader/song_reader_pinch_test.dart`
Expected: FAIL — no gesture wired yet.

- [ ] **Step 4: Wire the recognizer in the compact surface**

In `song_reader_compact_surface.dart`, add an `onSetFontScale` callback field and a baseline captured at scale start; use `RawGestureDetector` with the new recognizer alongside the existing `Listener` + `GestureDetector` (tap/double-tap). On `onScaleStart` capture `widget.projection.sharedFontScale`; on `onScaleUpdate` (only when `details.pointerCount >= 2`) call `widget.onSetFontScale((baseline * details.scale))`; on `onScaleEnd` call `widget.onPersistFontScale?.call()` (Task 7).

In `song_reader_screen.dart`, add `_setSharedFontScale(double scale)` mirroring `_adjustSharedFontScale` (scoped + non-scoped branches, calling `controller.setSharedFontScale(scale)`), and pass it as `onSetFontScale` to the compact surface (and expanded surface if desired).

- [ ] **Step 5: Run; verify pass**

Run: `flutter test test/presentation/song_reader/song_reader_pinch_test.dart`
Expected: PASS (both pinch-zoom and scroll-preserved).

- [ ] **Step 6: Commit**

```bash
git add apps/lyron_app/lib/src/presentation/song_reader/widgets/two_pointer_scale_recognizer.dart apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_compact_surface.dart apps/lyron_app/lib/src/presentation/song_reader/song_reader_screen.dart apps/lyron_app/test/presentation/song_reader/song_reader_pinch_test.dart
git commit -m "feat(reader): pinch-to-zoom adjusting shared font scale with reflow"
```

---

### Task 6: Double-tap → fit-to-screen (toggle)

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_compact_surface.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_screen.dart`
- Test: `apps/lyron_app/test/presentation/song_reader/song_reader_fit_to_screen_test.dart`

- [ ] **Step 1: Write a failing widget test for fit + restore**

```dart
testWidgets('double-tap fits the song, second double-tap restores', (tester) async {
  // build a tall song in a fixed viewport; record onSetFontScale calls
  await tester.tap(find.byType(SongReaderCompactSurface));
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(find.byType(SongReaderCompactSurface)); // double-tap
  await tester.pumpAndSettle();
  // expect a fit scale < 1.0 was applied for a long song
  // second double-tap:
  await tester.tap(find.byType(SongReaderCompactSurface));
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(find.byType(SongReaderCompactSurface));
  await tester.pumpAndSettle();
  // expect the original scale (1.0) restored
});
```

- [ ] **Step 2: Run; verify failure**

Run: `flutter test test/presentation/song_reader/song_reader_fit_to_screen_test.dart`
Expected: FAIL — double-tap still toggles auto-fit.

- [ ] **Step 3: Implement fit toggle in the surface**

In `song_reader_compact_surface.dart`, the surface already has `LayoutBuilder` constraints and `widget.projection.sections`. Add state `double? _preFitScale;`. Replace `onDoubleTap: widget.onSurfaceDoubleTap` with a local handler:

```dart
void _handleDoubleTap(BoxConstraints constraints) {
  if (_preFitScale == null) {
    _preFitScale = widget.projection.sharedFontScale;
    final fit = resolveFitFontScale(
      sections: widget.projection.sections,
      viewMode: widget.projection.viewMode,
      availableWidth: constraints.maxWidth,
      availableHeight: constraints.maxHeight,
      minScale: SongReaderState.minSharedFontScale,
      maxScale: SongReaderState.maxSharedFontScale,
    );
    widget.onSetFontScale(fit);
  } else {
    widget.onSetFontScale(_preFitScale!);
    _preFitScale = null;
  }
  widget.onPersistFontScale?.call();
}
```

Capture the constraints from the content `LayoutBuilder` so the double-tap handler has them. Remove the `onSurfaceDoubleTap`/`_toggleAutoFit` wiring from the screen (keep `isAutoFitEnabled` for the wide-screen dense layout, just no longer toggled by double-tap). Update/delete any test that asserted the old double-tap→auto-fit behavior.

- [ ] **Step 4: Run; verify pass**

Run: `flutter test test/presentation/song_reader/song_reader_fit_to_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_compact_surface.dart apps/lyron_app/lib/src/presentation/song_reader/song_reader_screen.dart apps/lyron_app/test/presentation/song_reader/song_reader_fit_to_screen_test.dart
git commit -m "feat(reader): double-tap fits song to screen and toggles back"
```

---

### Task 7: Persist zoom per user + per song (local)

**Files:**
- Modify: `apps/lyron_app/pubspec.yaml` (add `shared_preferences`)
- Create: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_preferences_store.dart`
- Modify: `apps/lyron_app/lib/src/application/providers.dart` (expose a provider) or a new `song_reader_providers.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_screen.dart` (seed on open, write on change)
- Test: `apps/lyron_app/test/presentation/song_reader/song_reader_preferences_store_test.dart`

- [ ] **Step 1: Add the dependency**

```bash
cd apps/lyron_app && flutter pub add shared_preferences
```

- [ ] **Step 2: Write a failing store roundtrip test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_preferences_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('writes and reads zoom keyed by user and song', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = SharedPreferencesSongReaderPreferencesStore(prefs);

    expect(await store.readZoom(userId: 'u1', songId: 's1'), isNull);
    await store.writeZoom(userId: 'u1', songId: 's1', zoom: 1.6);
    expect(await store.readZoom(userId: 'u1', songId: 's1'), 1.6);
    expect(await store.readZoom(userId: 'u2', songId: 's1'), isNull);
    expect(await store.readZoom(userId: 'u1', songId: 's2'), isNull);
  });
}
```

- [ ] **Step 3: Run; verify failure**

Run: `flutter test test/presentation/song_reader/song_reader_preferences_store_test.dart`
Expected: FAIL — store does not exist.

- [ ] **Step 4: Implement the store**

```dart
import 'package:shared_preferences/shared_preferences.dart';

abstract class SongReaderPreferencesStore {
  Future<double?> readZoom({required String userId, required String songId});
  Future<void> writeZoom({required String userId, required String songId, required double zoom});
}

class SharedPreferencesSongReaderPreferencesStore implements SongReaderPreferencesStore {
  SharedPreferencesSongReaderPreferencesStore(this._prefs);
  final SharedPreferences _prefs;

  String _key(String userId, String songId) => 'reader_zoom:$userId:$songId';

  @override
  Future<double?> readZoom({required String userId, required String songId}) async =>
      _prefs.getDouble(_key(userId, songId));

  @override
  Future<void> writeZoom({required String userId, required String songId, required double zoom}) async {
    await _prefs.setDouble(_key(userId, songId), zoom);
  }
}
```

- [ ] **Step 5: Run; verify pass**

Run: `flutter test test/presentation/song_reader/song_reader_preferences_store_test.dart`
Expected: PASS.

- [ ] **Step 6: Provider + screen wiring**

Add a provider exposing the store (build `SharedPreferences.getInstance()` once, e.g. a `FutureProvider`, or seed it in `bootstrap.dart` like other singletons). In `song_reader_screen.dart`:
- Resolve `userId` from `ref.read(supabaseClientProvider).auth.currentUser?.id` (skip persistence if null).
- On first successful `data` build, read the stored zoom and, if present, seed the controller via `setSharedFontScale` once (guard with a `bool _seededZoom`).
- Add `onPersistFontScale` that writes the current `sharedFontScale` debounced (a `Timer`, ~400ms) for `userId`+`widget.songId`; pass it to the compact surface; call it from pinch-end (Task 5) and fit/restore (Task 6).

- [ ] **Step 7: Widget test — seed-on-open**

```dart
testWidgets('reader seeds font scale from stored zoom', (tester) async {
  SharedPreferences.setMockInitialValues({'reader_zoom:u1:song-1': 2.0});
  // pump the screen with overrides: supabase user id = u1, songId = song-1
  // assert the rendered lyric text style fontSize reflects scale 2.0
});
```

Run: `flutter test test/presentation/song_reader/`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add apps/lyron_app/pubspec.yaml apps/lyron_app/pubspec.lock apps/lyron_app/lib/src/presentation/song_reader/song_reader_preferences_store.dart apps/lyron_app/lib/src/application/providers.dart apps/lyron_app/lib/src/presentation/song_reader/song_reader_screen.dart apps/lyron_app/test/presentation/song_reader/song_reader_preferences_store_test.dart
git commit -m "feat(reader): persist reader zoom per user and song locally"
```

---

### Task 8: Documentation + full verification

**Files:**
- Create: `docs/architecture/decisions/2026-06-06-reader-zoom-local-persistence.md`
- Modify: `docs/testing/testing-strategy.md` (only if new patterns warrant a note)
- Already created: spec + this plan.

- [ ] **Step 1: Write the ADR**

Record: decision = local `shared_preferences` KV keyed by `reader_zoom:{userId}:{songId}`; context = single scalar per user+song, no backend requirement; alternatives = drift table (rejected: schema migration + codegen overhead for one scalar) and Supabase (rejected: explicitly local-only); consequences = not synced across devices (acceptable for a view preference). Follow the existing ADR file format under `docs/architecture/decisions/`.

- [ ] **Step 2: Run the full suite + analyzer**

Run: `cd apps/lyron_app && flutter test`
Run: `cd apps/lyron_app && flutter analyze`
Expected: all green, no analyzer issues.

- [ ] **Step 3: Visual verification (Flutter web)**

Run: `cd apps/lyron_app && flutter run -d chrome` (or `flutter build web` + serve).
Drive via the Claude Preview MCP: `preview_start` the URL → `preview_resize` to ~390px, ~800px, ~1400px → `preview_screenshot` at each (open a long song and a short/narrow song). Confirm: thumb at the right edge at all widths; no horizontal scroll after zooming up; double-tap fits the whole song; reopening restores zoom. Save before/after screenshots for the PR.

- [ ] **Step 4: Commit docs**

```bash
git add docs/architecture/decisions/2026-06-06-reader-zoom-local-persistence.md docs/testing/testing-strategy.md
git commit -m "docs(reader): ADR for local reader-zoom persistence"
```

- [ ] **Step 5: Open the PR**

```bash
git push -u origin feat/song-reader-zoom
gh pr create --fill
```

Include the before/after screenshots and a checklist mapping to the spec's acceptance criteria.

---

## Self-Review Notes

- **Spec coverage:** AC1–3 → Task 4; AC4–5 → Task 3 (+ tab exception unchanged); AC6–7 → Task 5; AC8 → Task 6; AC9 → Task 1; AC10–11 → Task 7; AC12 → no projection/transpose code touched (verified by leaving projection files untouched).
- **Type consistency:** `resolveFitFontScale` / `estimateSongContentHeight` / `estimateSectionHeight` signatures defined in Task 2 are reused verbatim in Tasks 6. `onSetFontScale` (Task 5) and `onPersistFontScale` (Tasks 5–7) are the only new surface callbacks.
- **Risk:** the gesture-arena coexistence (Task 5) is the least certain; Step 4's fallback (GestureDetector gated on `pointerCount`) is the contingency. Validate with the one-finger-scroll test before committing.
