# UX-1 Reader Wrap and UX-2 Date Picker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop the reader from breaking a lyric line inside a word (which drags the chord onto the wrong syllable), make the fit estimator mirror the real render, and replace the raw ISO-8601 `scheduled_for` text fields with a date and time picker.

**Architecture:** A pure `groupSegmentsIntoWords` module becomes the single source of truth for where a lyric line may break; both `SongLineView` and `song_reader_fit.dart` consume it. Shared layout constants move into one metrics file so the estimator and the renderer cannot drift apart silently. On the planning side, one `ScheduledForField` widget owns the picker flow and is used by both the create and the edit dialog.

**Tech Stack:** Flutter, `flutter_test` widget tests, Material `showDatePicker` / `showTimePicker`.

**Spec:** `docs/specs/2026-07-27-ux1-reader-wrap-and-ux2-date-picker.md`

**Branch:** `refactor/ui-decomposition-phase2` (already checked out; S4 is already committed on it). Do not branch, do not merge.

---

## Ground rules for every task

- Run `cd apps/lyron_app && dart format lib test` before every commit; `verify` fails on unformatted code.
- Full suite: `cd apps/lyron_app && flutter test`. Single test: `flutter test test/<path> --plain-name '<name>'`.
- Failing test first for every behaviour change. A test that passes the moment you write it is not a regression test — check it actually fails first, and say so in the report.
- Never widen a provider subscription; never re-derive an organization id (ARCH-2 / ARCH-5, unchanged from S4).

---

## Discovered scope note

`scheduled_for` is edited as a raw ISO string in **two** places, not one:

- `lib/src/presentation/planning/widgets/plan_editor_dialog.dart` (edit plan), and
- `lib/src/presentation/planning/plan_list_screen.dart:128-249`, a duplicated private `_PlanEditorDialog` used for **create** plan.

Fixing only the edit dialog would leave plan creation on the raw ISO field. Both are converted, through one shared widget.

`AppStrings.planScheduledForInvalidMessage` and `AppStrings.planScheduledForLabel` ("Scheduled for (UTC ISO-8601)") are asserted by three existing tests
(`plan_list_screen_test.dart:385`, `plan_detail_screen_test.dart:2136`,
`widgets/plan_editor_dialog_test.dart:153`). Those assertions pin behaviour this
slice deliberately removes — invalid input becomes unexpressible — so they are
replaced, not preserved. Say so in the commit.

---

## File Structure

**Created**

| File | Responsibility |
|------|----------------|
| `apps/lyron_app/lib/src/presentation/song_reader/song_reader_word_groups.dart` | pure segment → word-group grouping |
| `apps/lyron_app/lib/src/presentation/song_reader/song_reader_metrics.dart` | layout constants shared by the renderer and the estimator |
| `apps/lyron_app/lib/src/presentation/planning/widgets/scheduled_for_field.dart` | read-only display + date/time picker + clear |
| `apps/lyron_app/test/presentation/song_reader/song_reader_word_groups_test.dart` | grouping rules |
| `apps/lyron_app/test/presentation/song_reader/song_reader_estimate_render_consistency_test.dart` | estimate vs. real render |
| `apps/lyron_app/test/presentation/planning/widgets/scheduled_for_field_test.dart` | picker flow, UTC correctness |

**Modified**

| File | Change |
|------|--------|
| `.../song_reader/widgets/song_line_view.dart` | Wrap children become word groups |
| `.../song_reader/song_reader_fit.dart` | greedy group packing, chord row per run, run spacing, drop `linePadding` |
| `.../planning/widgets/plan_editor_dialog.dart` | ISO field → `ScheduledForField` |
| `.../planning/plan_list_screen.dart` | same, plus reuse the extracted `RetryableErrorState` |
| `.../planning/plan_detail_screen.dart` | `_formatScheduledFor` shows date **and** time |
| `.../shared/app_strings.dart` | new picker labels; remove the ISO-specific ones |
| `docs/architecture/repository-review-2026-06-22.md` | UX-1, UX-2 and the §10 testing gap updated |

---

## Task 1: The word-group module

**Files:**
- Create: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_word_groups.dart`
- Test: `apps/lyron_app/test/presentation/song_reader/song_reader_word_groups_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_word_groups.dart';

SongReaderSegmentProjection _segment(String text, {String? chord}) =>
    SongReaderSegmentProjection(text: text, displayChord: chord);

void main() {
  test('keeps a chord-split word in one group', () {
    // "[C]por[D]cikám," — no whitespace at the segment join.
    final groups = groupSegmentsIntoWords([
      _segment('por', chord: 'C'),
      _segment('cikám,', chord: 'D'),
    ]);

    expect(groups, hasLength(1));
    expect(groups.single.segments.map((s) => s.text), ['por', 'cikám,']);
  });

  test('starts a new group after a trailing space', () {
    final groups = groupSegmentsIntoWords([
      _segment('minden ', chord: 'C'),
      _segment('porcikám', chord: 'D'),
    ]);

    expect(groups, hasLength(2));
  });

  test('starts a new group when the next segment leads with a space', () {
    final groups = groupSegmentsIntoWords([
      _segment('minden', chord: 'C'),
      _segment(' porcikám', chord: 'D'),
    ]);

    expect(groups, hasLength(2));
  });

  test('attaches a chord-only segment to the group that follows it', () {
    final groups = groupSegmentsIntoWords([
      _segment('', chord: 'C'),
      _segment('porcikám', chord: 'D'),
    ]);

    expect(groups, hasLength(1));
    expect(groups.single.segments, hasLength(2));
  });

  test('splits a segment that contains an internal space', () {
    final groups = groupSegmentsIntoWords([_segment('minden porcikám')]);

    expect(groups, hasLength(1));
    expect(groups.single.segments.single.text, 'minden porcikám');
  });

  test('returns no groups for an empty segment list', () {
    expect(groupSegmentsIntoWords(const []), isEmpty);
  });
}
```

Note the fifth case: a single segment carrying an internal space is ONE group. The
grouping only controls where the outer `Wrap` may break between segments; the
inner `Text` still wraps at its own spaces. Do not try to sub-split segment text.

Adjust `_segment` to the real `SongReaderSegmentProjection` constructor — read
`lib/src/presentation/song_reader/song_reader_projection.dart` first and use the
actual parameter names.

- [ ] **Step 2: Run it and watch it fail**

Run: `cd apps/lyron_app && flutter test test/presentation/song_reader/song_reader_word_groups_test.dart`
Expected: FAIL — `Target of URI doesn't exist`.

- [ ] **Step 3: Implement**

```dart
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';

/// A run of adjacent segments that belong to the same word.
///
/// ChordPro splits a lyric line at chord positions, so a chord placed inside a
/// word produces two adjacent segments with no whitespace between them. Grouping
/// them keeps the line's `Wrap` from breaking inside the word and carrying the
/// second segment's chord onto the wrong syllable.
class SongReaderWordGroup {
  const SongReaderWordGroup(this.segments);

  final List<SongReaderSegmentProjection> segments;
}

/// Groups [segments] so a break is only possible where the source text had
/// whitespace.
List<SongReaderWordGroup> groupSegmentsIntoWords(
  List<SongReaderSegmentProjection> segments,
) {
  final groups = <SongReaderWordGroup>[];
  var current = <SongReaderSegmentProjection>[];

  for (final segment in segments) {
    final startsNewGroup =
        current.isNotEmpty &&
        (_endsWithWhitespace(current.last.text) ||
            _startsWithWhitespace(segment.text));
    if (startsNewGroup) {
      groups.add(SongReaderWordGroup(current));
      current = <SongReaderSegmentProjection>[];
    }
    current.add(segment);
  }

  if (current.isNotEmpty) {
    groups.add(SongReaderWordGroup(current));
  }
  return groups;
}

bool _endsWithWhitespace(String value) =>
    value.isNotEmpty && value.trimRight().length != value.length;

bool _startsWithWhitespace(String value) =>
    value.isNotEmpty && value.trimLeft().length != value.length;
```

- [ ] **Step 4: Run it and watch it pass**

Run the same command. Expected: 6 PASS.

- [ ] **Step 5: Commit**

```bash
cd apps/lyron_app && dart format lib test && cd ..
git add apps/lyron_app/lib/src/presentation/song_reader/song_reader_word_groups.dart \
        apps/lyron_app/test/presentation/song_reader/song_reader_word_groups_test.dart
git commit -m "feat(song-reader): add pure segment-to-word grouping

ChordPro splits a lyric line at chord positions, so a chord inside a word
yields two segments with no whitespace between them. This module marks which
adjacent segments belong to the same word so the renderer and the fit
estimator can agree on where a line may break."
```

---

## Task 2: Stop the mid-word break in the renderer

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_line_view.dart`
- Test: `apps/lyron_app/test/presentation/song_reader/widgets/song_line_view_test.dart` (create)

- [ ] **Step 1: Write the failing regression test at 375 px**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_line_view.dart';

void main() {
  testWidgets('keeps a chord-split word on one visual row at 375px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // A line long enough to wrap, whose LAST word is split by a chord.
    // Build it from the real projection type; the two trailing segments
    // ("porciká" / "m,") have no whitespace between them.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 375,
            child: SongLineView(
              line: /* projection built below */,
              viewMode: SongReaderViewMode.chordsAndLyrics,
              sharedFontScale: 1.0,
            ),
          ),
        ),
      ),
    );

    final left = tester.getTopLeft(find.text('porciká'));
    final right = tester.getTopLeft(find.text('m,'));

    expect(right.dy, left.dy, reason: 'the word must not be split across rows');
  });
}
```

Build the `SongReaderLyricLineProjection` from the real constructor — read
`song_reader_projection.dart` for the exact shape. Compose the line so that the
split word lands at the wrapping boundary at 375 px; if it does not wrap there,
lengthen the leading text until it does, and keep that fixture in the test.

- [ ] **Step 2: Run it and watch it fail**

Run: `cd apps/lyron_app && flutter test test/presentation/song_reader/widgets/song_line_view_test.dart`
Expected: FAIL, with the two `dy` values differing by roughly one row height. Record the failure output — it goes in the report. If it passes on the first run, the fixture does not reproduce the bug: lengthen the line until it does, before touching `song_line_view.dart`.

- [ ] **Step 3: Render word groups instead of segments**

In `song_line_view.dart`, replace the `Wrap`'s children:

```dart
children: [
  for (final group in groupSegmentsIntoWords(line.segments))
    ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Wrap(
        spacing: 0,
        runSpacing: lineRunSpacing,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          for (final segment in group.segments)
            _SongLineSegmentView(
              segment: segment,
              viewMode: viewMode,
              chordStyle: chordStyle,
              lyricStyle: lyricStyle,
              maxWidth: maxWidth,
            ),
        ],
      ),
    ),
],
```

The inner `Wrap` normally lays a group out on one run, so no break happens inside
a word. When a single group is wider than `maxWidth` — a long word carrying
several chords — the inner `Wrap` breaks it, which is today's behaviour, now
reached only as a last resort. Keep the outer `Wrap`'s existing `spacing`
(`hasLyricSegments ? 0.0 : _chordOnlySpacing`) and `runSpacing` as they are.

- [ ] **Step 4: Run the reader suite**

Run: `cd apps/lyron_app && flutter test test/presentation/song_reader/`
Expected: the new test PASSES and every existing reader test still passes. If an existing test now fails, read it before changing anything: it may be pinning the old broken break behaviour, in which case update it deliberately and say so — or it may be a real regression.

- [ ] **Step 5: Commit**

```bash
cd apps/lyron_app && dart format lib test && cd ..
git add apps/lyron_app/lib/src/presentation/song_reader/widgets/song_line_view.dart \
        apps/lyron_app/test/presentation/song_reader/widgets/song_line_view_test.dart
git commit -m "fix(song-reader): stop breaking a lyric line inside a word

The line Wrap took one child per ChordPro segment, and a chord inside a word
produces two segments with no whitespace between them, so Wrap was free to
break mid-word and carry the second chord onto the wrong syllable. Children
are now word groups; a group only breaks internally when it is wider than the
line on its own."
```

---

## Task 3: Shared metrics

**Files:**
- Create: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_metrics.dart`
- Modify: `song_line_view.dart`, `song_reader_fit.dart`

- [ ] **Step 1: Move the constants**

`song_line_view.dart` declares `_lineRunSpacing = 10.0` and
`_chordOnlySpacing = 22.0` privately; `song_reader_fit.dart` declares its own
`lineGap = 10.0` and the chord/lyric row heights. The renderer's run spacing and
the chord-to-lyric gap are the two the estimator must reproduce exactly.

Create `song_reader_metrics.dart`:

```dart
/// Layout constants shared by the reader renderer and the fit estimator.
///
/// These live in one place because the estimator has to reproduce the
/// renderer's spacing exactly; duplicated constants drift silently.
const double lineRunSpacing = 10.0;
const double chordOnlySpacing = 22.0;
const double chordToLyricGap = 2.0;
```

`chordToLyricGap` is the `SizedBox(height: 2)` between a chord and its lyric in
`_SongLineSegmentView` — read the current value from the widget rather than
trusting this number, and use the real one.

Import it from both files, delete the private duplicates, and replace the literal
`2` in `_SongLineSegmentView` with `chordToLyricGap`.

- [ ] **Step 2: Verify nothing changed**

Run: `cd apps/lyron_app && flutter analyze && flutter test test/presentation/song_reader/`
Expected: analyze clean, all reader tests pass. This step must be behaviour-neutral.

- [ ] **Step 3: Commit**

```bash
cd apps/lyron_app && dart format lib test && cd ..
git add apps/lyron_app/lib/src/presentation/song_reader/
git commit -m "refactor(song-reader): share the reader layout constants

The renderer's run spacing and chord-to-lyric gap were duplicated in the fit
estimator and kept in sync only by discipline. Both now import one metrics
file, which the next commit relies on."
```

---

## Task 4: Make the fit estimator mirror the render

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_fit.dart`
- Test: `apps/lyron_app/test/presentation/song_reader/song_reader_fit_test.dart`

- [ ] **Step 1: Write the failing chord-rows-per-run test**

Add to `song_reader_fit_test.dart`:

```dart
  test('charges a chord row for every wrapped run that carries a chord', () {
    // A line whose word groups pack into exactly two runs at this width, with
    // a chord in each run. The old formula charged one chord row for the whole
    // line; the render draws one per run.
    final line = /* SongReaderLyricLineProjection with chords spread across
                    enough word groups to force two runs at columnWidth */;

    final oneRun = estimateSectionHeight(
      section: /* section holding a single-run version of the line */,
      viewMode: SongReaderViewMode.chordsAndLyrics,
      maxWidth: 1000,
      fontScale: 1.0,
    );
    final twoRuns = estimateSectionHeight(
      section: /* section holding `line` */,
      viewMode: SongReaderViewMode.chordsAndLyrics,
      maxWidth: 240,
      fontScale: 1.0,
    );

    expect(
      twoRuns - oneRun,
      greaterThanOrEqualTo(chordRowHeight + lyricRowHeight + lineRunSpacing),
      reason: 'the second run must add its own chord row, lyric row and run gap',
    );
  });
```

Match `estimateSectionHeight`'s real signature — read it before writing the
call. Build the fixtures from the real projection constructors.

- [ ] **Step 2: Run it and watch it fail**

Run: `cd apps/lyron_app && flutter test test/presentation/song_reader/song_reader_fit_test.dart --plain-name 'chord row for every wrapped run'`
Expected: FAIL — today the second run adds only a lyric row.

- [ ] **Step 3: Rewrite the lyric-line branch of `_lineItemHeight`**

Current code (`song_reader_fit.dart:166-189`) computes
`effectiveLineWidth = (columnWidth - linePadding).clamp(120.0, 1200.0)` and
`wrapCount = ceil(lyricLength / charsPerLine)`. Replace the lyric case with
greedy word-group packing:

- `effectiveLineWidth` becomes `columnWidth.clamp(120.0, 1200.0)` — the
  `linePadding` subtraction goes away, because nothing in the render path
  reserves those 24 px. Delete the `linePadding` constant; `grep` confirms
  `song_reader_fit.dart:166` is its only use.
- group width is `group.segments.map((s) => s.text.length).sum * characterWidthEstimate * fontScale`;
- pack groups greedily into runs of `effectiveLineWidth`; a group wider than a
  full run occupies `ceil(groupWidth / effectiveLineWidth)` runs on its own,
  matching the inner-`Wrap` fallback in the renderer;
- a run's height is `lyricRowHeight * fontScale`, plus
  `chordRowHeight * fontScale + chordToLyricGap` when that run holds a segment
  with a `displayChord` **and** the view mode shows chords;
- the line's height is the sum of run heights, plus
  `(runCount - 1) * lineRunSpacing`, plus the existing `lineGap`.

Keep the existing collapse rule unchanged — `hasLyrics` via
`segments.any((s) => s.text.trim().isNotEmpty)` returning `0.0` in
`lyricsOnly` mode — it already matches `song_line_view.dart:33-38`.

Keep the comment/tab/directive branches as they are; they are out of scope.

- [ ] **Step 4: Run the fit suite and triage**

Run: `cd apps/lyron_app && flutter test test/presentation/song_reader/song_reader_fit_test.dart`

The new test must pass. Existing tests are mostly monotonicity assertions and
should hold. For any that fails:

1. Decide whether it pins a **behaviour** (e.g. "the fit scale must not overflow")
   or a **number** (e.g. a specific scale value).
2. A failing behaviour assertion is a bug in your implementation — fix the code.
3. A failing number assertion is expected: the estimate is deliberately more
   accurate now. Update it, and record which tests you changed and why in the
   commit body. Do not silently loosen a bound.

- [ ] **Step 5: Full suite**

Run: `cd apps/lyron_app && dart format lib test && flutter analyze && flutter test`
Expected: analyze clean, whole suite green.

- [ ] **Step 6: Commit**

```bash
cd apps/lyron_app && dart format lib test && cd ..
git add apps/lyron_app/lib/src/presentation/song_reader/song_reader_fit.dart \
        apps/lyron_app/test/presentation/song_reader/song_reader_fit_test.dart
git commit -m "fix(song-reader): estimate line height the way the reader renders it

The estimator divided a joined character count by an assumed characters-per-
line, charged one chord row per line, added a single flat gap, and reserved
24px of padding the renderer never reserves. It now packs the same word groups
the renderer lays out, charges a chord row for every run that carries a chord,
and adds the renderer's run spacing between runs.

The auto-fit scale changes as a result; that is the correction, not a
regression."
```

---

## Task 5: The estimate/render consistency test

This is the test the repository review's §10 asks for. It must be measured into existence, not guessed.

**Files:**
- Create: `apps/lyron_app/test/presentation/song_reader/song_reader_estimate_render_consistency_test.dart`

- [ ] **Step 1: Write the dimension-agreement assertions**

Pump a `SongReaderCompactSurface` at 375×812 with a fixture song, then assert the
fit calculator and the render grid receive the same padding-adjusted dimensions.
`song_reader_fit_to_screen_test.dart:218-264` already does the plumbing half —
read it and reuse its harness rather than inventing a second one. Assert
explicitly:

- the width handed to the estimator equals
  `min(constraints.maxWidth, maxContentWidth) - contentPadding.horizontal`;
- the height handed to the estimator equals
  `constraints.maxHeight - contentPadding.vertical`;
- the section grid's own `LayoutBuilder` width equals the estimator's width.

- [ ] **Step 2: Measure the real rendered height**

Add a test that renders the fixture song and reads the actual content height from
the render tree:

```dart
    final contentSize = tester.getSize(find.byType(SongReaderSectionGrid));
    final estimated = estimateSongContentHeight(
      sections: fixtureSections,
      viewMode: SongReaderViewMode.chordsAndLyrics,
      availableWidth: measuredWidth,
      fontScale: 1.0,
      // remaining arguments per the real signature
    );

    // ignore: avoid_print
    print('rendered=${contentSize.height} estimated=$estimated '
        'relativeError=${(estimated - contentSize.height).abs() / contentSize.height}');
```

Run it once, read the printed relative error, and **write that number down**. It
is the input to the next step.

- [ ] **Step 3: Pin the bound from the measurement**

Replace the `print` with two assertions:

- a relative bound just above the measured error, rounded up to a readable
  figure (if the measured error is 0.07, pin 0.10 — close enough to catch a
  regression, loose enough not to be flaky across font metrics);
- an absolute ceiling of one `lyricRowHeight` per rendered line, so a large song
  cannot hide a systematic per-line error inside a percentage.

Write the measured value into a comment above the assertions, with the date, so
the next person knows what the bound was derived from rather than guessing at it.

- [ ] **Step 4: Prove the test bites**

Temporarily change `chordRowHeight` in `song_reader_fit.dart` by +50%, re-run
this test, and confirm it FAILS. Restore the constant and confirm
`git diff --stat apps/lyron_app/lib/` is empty. Report both results — a
consistency test that cannot fail is worthless.

- [ ] **Step 5: Run and commit**

Run: `cd apps/lyron_app && flutter test test/presentation/song_reader/`

```bash
cd apps/lyron_app && dart format lib test && cd ..
git add apps/lyron_app/test/presentation/song_reader/song_reader_estimate_render_consistency_test.dart
git commit -m "test(song-reader): pin estimate/render consistency

Asserts the fit calculator and the render grid receive identical
padding-adjusted dimensions, and that the estimated content height tracks the
real rendered height within a measured bound. Closes the estimate/render half
of the review's fit-layout testing gap; the performance half stays open."
```

---

## Task 6: The scheduled-for field widget

**Files:**
- Create: `apps/lyron_app/lib/src/presentation/planning/widgets/scheduled_for_field.dart`
- Create: `apps/lyron_app/test/presentation/planning/widgets/scheduled_for_field_test.dart`
- Modify: `apps/lyron_app/lib/src/shared/app_strings.dart`

- [ ] **Step 1: Confirm the picker signatures against the SDK**

Do not write the call from memory. Find the pinned Flutter SDK and read the real
declarations:

```bash
grep -rn "Future<DateTime?> showDatePicker" "$(dirname "$(dirname "$(readlink -f "$(which flutter)")")")/packages/flutter/lib/src/material/date_picker.dart" | head
grep -rn "Future<TimeOfDay?> showTimePicker" "$(dirname "$(dirname "$(readlink -f "$(which flutter)")")")/packages/flutter/lib/src/material/time_picker.dart" | head
```

Note which parameters are required in this SDK version — `initialDate` in
particular has changed nullability across releases. Report what you found.

- [ ] **Step 2: Write the failing tests**

```dart
  testWidgets('picking a date and time yields a UTC instant', (tester) async {
    DateTime? captured;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScheduledForField(
            value: null,
            onChanged: (value) => captured = value,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('scheduled-for-pick')));
    await tester.pumpAndSettle();
    // date picker is open — accept its initial selection
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    // time picker is open — accept its initial selection
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.isUtc, isTrue);
  });

  testWidgets('renders the stored instant as local time', (tester) async {
    final stored = DateTime.utc(2026, 4, 5, 8, 30);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScheduledForField(value: stored, onChanged: (_) {}),
        ),
      ),
    );

    final context = tester.element(find.byType(ScheduledForField));
    final localizations = MaterialLocalizations.of(context);
    final local = stored.toLocal();
    final expected =
        '${localizations.formatMediumDate(local)} '
        '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';

    expect(find.text(expected), findsOneWidget);
  });

  testWidgets('clearing reports null', (tester) async {
    var cleared = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScheduledForField(
            value: DateTime.utc(2026, 4, 5, 8, 30),
            onChanged: (value) => cleared = value == null,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('scheduled-for-clear')));
    await tester.pump();

    expect(cleared, isTrue);
  });

  testWidgets('cancelling the date picker leaves the value untouched', (
    tester,
  ) async {
    var changes = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScheduledForField(
            value: DateTime.utc(2026, 4, 5, 8, 30),
            onChanged: (_) => changes += 1,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('scheduled-for-pick')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(changes, 0);
  });
```

Add the time-picker-cancel twin, and a test asserting an existing value seeds the
date picker (the picker opens on the stored instant's local date). If `'OK'` /
`'Cancel'` are not the actual button labels in this Flutter version, find the
real ones from `MaterialLocalizations` rather than hardcoding a guess.

- [ ] **Step 3: Run and watch them fail**

Run: `cd apps/lyron_app && flutter test test/presentation/planning/widgets/scheduled_for_field_test.dart`
Expected: FAIL — the widget does not exist.

- [ ] **Step 4: Implement `ScheduledForField`**

A `StatelessWidget` taking `DateTime? value` (a UTC instant) and
`ValueChanged<DateTime?> onChanged`. It renders the local formatted date and
time, or a not-scheduled label, plus a pick button
(`ValueKey('scheduled-for-pick')`) and a clear button
(`ValueKey('scheduled-for-clear')`, hidden when the value is already null).

Picking: `showDatePicker` seeded from `value?.toLocal()` (or `DateTime.now()`),
with a `firstDate` / `lastDate` window wide enough for real planning — five years
either side of now. On a non-null result, `showTimePicker` seeded from
`TimeOfDay.fromDateTime(value?.toLocal() ?? DateTime.now())`. On a non-null
result, combine into a local `DateTime` and call `onChanged(local.toUtc())`.
Either cancellation returns without calling `onChanged`. Guard the second picker
with `context.mounted` after the first `await`.

New strings in `app_strings.dart` (match the surrounding naming):
`planScheduledForPickAction`, `planScheduledForClearAction`,
`planScheduledForEmptyLabel`. Change `planScheduledForLabel` from
"Scheduled for (UTC ISO-8601)" to plain "Scheduled for" — the ISO format is no
longer the user's problem.

- [ ] **Step 5: Run and commit**

Run the widget test file: all PASS.

```bash
cd apps/lyron_app && dart format lib test && cd ..
git add apps/lyron_app/lib/src/presentation/planning/widgets/scheduled_for_field.dart \
        apps/lyron_app/test/presentation/planning/widgets/scheduled_for_field_test.dart \
        apps/lyron_app/lib/src/shared/app_strings.dart
git commit -m "feat(planning): add a scheduled-for date and time field

Renders the stored UTC instant as local date and time and edits it through the
Material date and time pickers, converting back to UTC on the way out, so the
displayed local time and the persisted instant cannot drift apart."
```

---

## Task 7: Use the field in both dialogs

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/planning/widgets/plan_editor_dialog.dart`
- Modify: `apps/lyron_app/lib/src/presentation/planning/plan_list_screen.dart`
- Modify: `apps/lyron_app/lib/src/presentation/planning/plan_detail_screen.dart`
- Modify: `apps/lyron_app/lib/src/shared/app_strings.dart`
- Test: the three existing test files listed in the scope note

- [ ] **Step 1: Replace the edit dialog's ISO field**

In `plan_editor_dialog.dart`, drop `_scheduledForController`, `_scheduledForError`,
`_tryParseScheduledFor` and the file-level `_parseOptionalDateTime`. Hold the
value in state as `DateTime? _scheduledFor`, seeded from
`widget.initialScheduledFor`, and render `ScheduledForField`. The save button no
longer validates — it puts `_scheduledFor` straight into the `PlanEditDraft`.

- [ ] **Step 2: Replace the create dialog's ISO field**

`plan_list_screen.dart:128-249` holds a duplicated private `_PlanEditorDialog`
for plan creation with the same ISO field. Apply the same change there, using the
same `ScheduledForField`.

- [ ] **Step 3: Show the time in the plan header**

`_formatScheduledFor` in `plan_detail_screen.dart` currently returns only
`formatMediumDate`. Extend it to date **and** time via
`MaterialLocalizations.formatTimeOfDay(TimeOfDay.fromDateTime(local))`, so a
scheduled time is visible where it can be set. Use the same composition as
`ScheduledForField` so the two never disagree — if that means a small shared
formatting helper, add it next to the field widget.

- [ ] **Step 4: Update the three tests that pin the removed behaviour**

`plan_list_screen_test.dart:385`, `plan_detail_screen_test.dart:2136` and
`widgets/plan_editor_dialog_test.dart:153` assert
`AppStrings.planScheduledForInvalidMessage` appears for bad input. That message
is gone — invalid input is no longer expressible. Replace each with a test of the
new behaviour: picking a date and time produces a UTC value in the draft. Then
delete `planScheduledForInvalidMessage` from `app_strings.dart` and confirm with
`grep -rn planScheduledForInvalidMessage apps/lyron_app` that nothing references
it.

- [ ] **Step 5: Full suite**

Run: `cd apps/lyron_app && dart format lib test && flutter analyze && flutter test`
Expected: analyze clean, whole suite green.

- [ ] **Step 6: Commit**

```bash
cd apps/lyron_app && dart format lib test && cd ..
git add apps/lyron_app/lib/src/presentation/planning/ apps/lyron_app/lib/src/shared/app_strings.dart \
        apps/lyron_app/test/presentation/planning/
git commit -m "fix(planning): edit the plan schedule with a date and time picker

Both the create and the edit dialog used a raw ISO-8601 text field, and the
plan header rendered only the date, so a time the user typed was stored and
never shown back. Both dialogs now use the shared picker field and the header
shows the time.

The three tests that asserted the invalid-ISO error message are replaced: with
a picker, invalid input is no longer expressible."
```

---

## Task 8: Reuse the extracted error state in the plan list

Small cleanup in a file this slice already edits: `plan_list_screen.dart:281`
still declares its own private `_RetryableErrorState`, an exact duplicate of the
`RetryableErrorState` extracted in S4.

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/planning/plan_list_screen.dart`

- [ ] **Step 1: Compare the two implementations**

Read `plan_list_screen.dart:281` and
`widgets/retryable_error_state.dart`. If they differ in any way beyond the class
name, STOP and report the difference instead of merging them — a silent
behaviour change here would not be caught by the plan-list tests.

- [ ] **Step 2: Delete the duplicate and import the shared widget**

- [ ] **Step 3: Verify**

Run: `cd apps/lyron_app && flutter analyze && flutter test test/presentation/planning/`
Expected: analyze clean, all planning tests pass, unchanged.

- [ ] **Step 4: Commit**

```bash
cd apps/lyron_app && dart format lib test && cd ..
git add apps/lyron_app/lib/src/presentation/planning/plan_list_screen.dart
git commit -m "refactor(planning): reuse the extracted retryable error state

The plan list carried its own copy of the widget S4 extracted for plan detail."
```

---

## Task 9: Documentation

**Files:**
- Modify: `docs/architecture/repository-review-2026-06-22.md`

- [ ] **Step 1: Strike UX-1 and UX-2**

Follow the existing convention exactly (see the ARCH-1/ARCH-2/ARCH-3 entries).
Update the finding table rows near lines 63-64, the detail rows near lines
381-382, and the roadmap line near 506:

```markdown
- ~~UX-1: reader line-wrap/chord-alignment on narrow widths; UX-2: date picker.~~ **Done (ui-decomposition-phase2).**
```

- [ ] **Step 2: Update the §10 testing gap**

The §10 text asks for a fit-layout regression test asserting estimate/render
consistency. Record that this half is now covered by
`song_reader_estimate_render_consistency_test.dart`, and that the fit-layout
**performance** regression test remains open. Do not mark the whole gap closed —
only the half this slice actually closed.

- [ ] **Step 3: Commit**

```bash
git add docs/architecture/repository-review-2026-06-22.md
git commit -m "docs(architecture): mark UX-1 and UX-2 done

Also narrows the section 10 testing gap: estimate/render consistency is now
pinned by a test; the fit-layout performance regression test is still missing."
```

---

## Task 10: Slice verification

- [ ] **Step 1: Confirm the screens are still within the ARCH-3 target**

```bash
cd /Users/abelbalog/Documents/Development/private/lyrica
wc -l apps/lyron_app/lib/src/presentation/planning/plan_detail_screen.dart \
      apps/lyron_app/lib/src/presentation/planning/plan_list_screen.dart \
      apps/lyron_app/lib/src/presentation/song_editor/song_editor_screen.dart \
      apps/lyron_app/lib/src/presentation/song_reader/song_reader_screen.dart
```

Report the numbers. S5 should shrink `plan_list_screen.dart`, not grow any screen.

- [ ] **Step 2: Run the full local CI**

```bash
./scripts/run-ci-locally.sh verify
./scripts/run-ci-locally.sh migrations
./scripts/run-ci-locally.sh backend-write-contracts
```

All three must exit 0. Capture the exit codes and the test summary line; a claim
of green without them does not count.

- [ ] **Step 3: Refresh the knowledge graph**

```bash
graphify . --update
```

The graph was last refreshed for phase 0-1; this effort restructured the whole
presentation layer.

- [ ] **Step 4: Stop**

Do not merge and do not delete the branch. Report and wait.
