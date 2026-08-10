# Word-boundary wrapping in the reader — implementation plan (PR2 of 4)

> **For agentic workers:** REQUIRED SUB-SKILL: use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task by task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Spec:** `docs/specs/2026-08-09-song-presentation.md` (see "Defect pulled into scope")

**Goal:** Make the reader break lyric lines at word boundaries instead of inside a word that carries a chord change.

**Architecture:** The wrapping unit becomes the word. Each segment's text is split at its internal whitespace *before* grouping, so `groupSegmentsIntoWords` — whose rule is already correct — receives pieces it can actually group into single words. Both the renderer and the fit estimator call the same new splitter, so they keep describing the same layout.

**Tech stack:** Flutter, `Wrap`, `flutter_test`.

**No visual redesign here.** Typography, spacing, colours and chrome are untouched; those are PR3 and PR4. This PR changes only *where lines may break*.

---

## The defect

At 375px the reader renders `Igé` / `dben bízok én`, breaking inside `Igédben`.

`groupSegmentsIntoWords` (`apps/lyron_app/lib/src/presentation/song_reader/song_reader_word_groups.dart:23-33`) decides boundaries at **segment** granularity: a new group starts only where the previous segment's text ends with whitespace, or the next segment's text starts with it. A segment's own internal whitespace is never a boundary.

ChordPro splits a line at chord positions, so for

```
[E]Kegyelmed elég, több, mint elég, Igé[G#m]dben bízok én
```

the segments are `Kegyelmed elég, több, mint elég, Igé` and `dben bízok én`. Neither boundary carries whitespace, so both land in **one group** — a whole line of text. That group is wider than the line, so the renderer takes its over-wide branch (`song_line_view.dart:57-77`: a `ConstrainedBox` holding an inner `Wrap`) and packs the group's segments individually. The only break available is between the two segments, i.e. inside the word.

The file's doc comment claims "a break is only possible where the source text had whitespace". Today the opposite is true.

The estimator mirrors the renderer faithfully here (`song_reader_fit.dart:748-775`), so **the estimate is right and the render is wrong**. The fix moves both.

## The fix

Split each segment at its internal whitespace before grouping:

- keep the whitespace on the **left-hand** piece, so the concatenated rendered string is byte-identical and the existing "ends with whitespace" grouping rule still fires;
- carry `displayChord` on the **first** piece only — a chord is positioned at its segment's start, so later pieces have no chord of their own;
- leave chord-only segments (empty text) untouched, so an instrumental bar keeps its independent chord slots and its `chordOnlySpacing`.

After the split, every group is exactly one word, and the over-wide-group branch fires only for a genuinely unbreakable single word — its correct meaning.

## Risks this plan must actively check

1. **The one-sided estimator bound.** `estimated >= rendered`, asserted by `song_line_view_estimate_consistency_test.dart`, `song_reader_block_estimate_consistency_test.dart` and `song_reader_estimate_render_consistency_test.dart`. The split changes how many boxes a line contains, which changes both sides. Task 5 adds fixtures for the new shape; the existing suites must stay green throughout.
2. **Trailing spaces at a break.** A single `Text` collapses a trailing space at a line break; separate widgets in a `Wrap` do not, so a run may now carry a word's trailing space and wrap marginally earlier. Task 5's render-vs-estimate fixtures are what confirm the estimator still bounds this rather than assuming it does.
3. **More boxes per line.** One widget per word instead of per segment. `resolveFitFontScale` runs a ~24-iteration binary search over every line, so per-line cost matters. Task 6 measures it rather than hand-waving; the repository review already lists a missing fit-layout performance regression test, and this PR does not close that.

---

## File structure

**Modify**
- `apps/lyron_app/lib/src/presentation/song_reader/song_reader_word_groups.dart` — add the splitter next to the grouper that consumes it; both are pure functions over segments, shared by renderer and estimator.
- `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_line_view.dart:56-58`
- `apps/lyron_app/lib/src/presentation/song_reader/song_reader_fit.dart:695-701`
- `apps/lyron_app/test/presentation/song_reader/song_reader_word_groups_test.dart`
- `apps/lyron_app/test/presentation/song_reader/widgets/song_line_view_test.dart`
- `apps/lyron_app/test/presentation/song_reader/song_line_view_estimate_consistency_test.dart`
- `docs/deferred/2026-07-28-reader-fit-conservatism-margin.md` — append this round's measurements.

**Do not read end to end:** `docs/deferred/2026-07-28-reader-fit-conservatism-margin.md` is 576 lines. Grep it for the tables (`grep -n "^| " docs/deferred/2026-07-28-reader-fit-conservatism-margin.md`) and read the surrounding section only.

---

### Task 1: The splitter

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_word_groups.dart`
- Test: `apps/lyron_app/test/presentation/song_reader/song_reader_word_groups_test.dart`

- [ ] **Step 1: Write the failing test**

Append to `song_reader_word_groups_test.dart`:

```dart
  group('splitSegmentsAtWordBoundaries', () {
    test('splits a multi-word segment, keeping the space on the left piece', () {
      final result = splitSegmentsAtWordBoundaries(const [
        SongReaderSegmentProjection(displayChord: 'E', text: 'alpha beta gamma'),
      ]);

      expect(
        result.map((s) => s.text).toList(),
        ['alpha ', 'beta ', 'gamma'],
      );
      // The chord belongs to the segment's start, so only the first piece keeps it.
      expect(result.map((s) => s.displayChord).toList(), ['E', null, null]);
    });

    test('concatenating the pieces reproduces the original text exactly', () {
      const original = '  alpha   beta  ';
      final result = splitSegmentsAtWordBoundaries(const [
        SongReaderSegmentProjection(displayChord: null, text: original),
      ]);

      expect(result.map((s) => s.text).join(), original);
    });

    test('leaves a single-word segment alone', () {
      final result = splitSegmentsAtWordBoundaries(const [
        SongReaderSegmentProjection(displayChord: 'G', text: 'alpha'),
      ]);

      expect(result, hasLength(1));
      expect(result.single.text, 'alpha');
      expect(result.single.displayChord, 'G');
    });

    test('leaves a chord-only segment alone', () {
      final result = splitSegmentsAtWordBoundaries(const [
        SongReaderSegmentProjection(displayChord: 'Am', text: ''),
        SongReaderSegmentProjection(displayChord: 'F', text: ''),
      ]);

      expect(result, hasLength(2));
      expect(result.map((s) => s.displayChord).toList(), ['Am', 'F']);
    });

    test('splits on tabs and unicode spaces, not only the ASCII space', () {
      final result = splitSegmentsAtWordBoundaries(const [
        SongReaderSegmentProjection(displayChord: null, text: 'alpha\tbeta　gamma'),
      ]);

      expect(result.map((s) => s.text).toList(), ['alpha\t', 'beta　', 'gamma']);
    });
  });

  group('groupSegmentsIntoWords after splitting', () {
    test('a word split by a chord change stays in one group', () {
      // The reproduction: ChordPro splits "Igédben" at the chord.
      final groups = groupSegmentsIntoWords(
        splitSegmentsAtWordBoundaries(const [
          SongReaderSegmentProjection(displayChord: 'E', text: 'alpha beta Igé'),
          SongReaderSegmentProjection(displayChord: 'G#m', text: 'dben gamma'),
        ]),
      );

      expect(
        groups.map((g) => g.segments.map((s) => s.text).join()).toList(),
        ['alpha ', 'beta ', 'Igédben ', 'gamma'],
      );
      // The chorded half of the split word keeps its own chord inside the group.
      final splitWord = groups[2].segments;
      expect(splitWord.map((s) => s.displayChord).toList(), ['E', 'G#m']);
    });
  });
```

Add the `song_reader_projection.dart` import if the file does not already have it.

- [ ] **Step 2: Run the test and confirm it fails**

Run: `cd apps/lyron_app && flutter test test/presentation/song_reader/song_reader_word_groups_test.dart`
Expected: compile error — `splitSegmentsAtWordBoundaries` is not defined.

- [ ] **Step 3: Write the splitter**

Add to `song_reader_word_groups.dart`:

```dart
/// Whitespace that Flutter's line breaker treats as a break opportunity.
///
/// Deliberately the same character class `song_reader_fit.dart`'s
/// `_breakableWhitespace` uses, and for the same reason: the estimator and the
/// renderer must agree on where a break may happen. See
/// docs/deferred/2026-07-28-reader-fit-conservatism-margin.md for the
/// `TextPainter` measurements behind this set.
final _breakableWhitespace = RegExp(r'[ \t  -​  　 ]');

/// Splits each segment's text at internal whitespace so that every piece holds
/// at most one word.
///
/// ChordPro splits a lyric line at chord positions, which has nothing to do
/// with where words begin and end: one segment can hold a whole clause, and a
/// single word can span two segments. [groupSegmentsIntoWords] can only start a
/// group at a segment boundary, so without this pre-pass a multi-word segment
/// and its chord-split neighbour collapse into one indivisible group covering
/// most of a line — and when that group does not fit, the only break available
/// is the segment boundary, in the middle of a word.
///
/// The trailing whitespace stays on the LEFT piece: the concatenated text must
/// be byte-identical to the original (the rendered line's spacing comes from
/// the text itself, since the `Wrap` uses `spacing: 0`), and
/// [groupSegmentsIntoWords] reads exactly that trailing whitespace to decide
/// where a group ends.
///
/// [SongReaderSegmentProjection.displayChord] rides on the first piece only: a
/// chord is drawn at its segment's start, so the pieces after the first have no
/// chord of their own.
List<SongReaderSegmentProjection> splitSegmentsAtWordBoundaries(
  List<SongReaderSegmentProjection> segments,
) {
  final result = <SongReaderSegmentProjection>[];

  for (final segment in segments) {
    // A chord-only segment (an instrumental bar's slot) has no words to split
    // and must stay one box, or it loses its own chord slot.
    if (segment.text.isEmpty) {
      result.add(segment);
      continue;
    }

    final pieces = _splitKeepingTrailingWhitespace(segment.text);
    if (pieces.length == 1) {
      result.add(segment);
      continue;
    }

    for (var i = 0; i < pieces.length; i++) {
      result.add(
        SongReaderSegmentProjection(
          displayChord: i == 0 ? segment.displayChord : null,
          text: pieces[i],
        ),
      );
    }
  }

  return List.unmodifiable(result);
}

/// Cuts [text] after each run of breakable whitespace, so every piece except
/// the last ends with the whitespace that terminated it and the pieces
/// concatenate back to [text].
List<String> _splitKeepingTrailingWhitespace(String text) {
  final pieces = <String>[];
  var start = 0;
  var index = 0;

  while (index < text.length) {
    if (!_breakableWhitespace.hasMatch(text[index])) {
      index++;
      continue;
    }

    // Consume the whole whitespace run so "alpha   beta" yields "alpha   ".
    var end = index;
    while (end < text.length && _breakableWhitespace.hasMatch(text[end])) {
      end++;
    }
    pieces.add(text.substring(start, end));
    start = end;
    index = end;
  }

  if (start < text.length) {
    pieces.add(text.substring(start));
  }

  return pieces;
}
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `cd apps/lyron_app && flutter test test/presentation/song_reader/song_reader_word_groups_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/lyron_app/lib/src/presentation/song_reader/song_reader_word_groups.dart apps/lyron_app/test/presentation/song_reader/song_reader_word_groups_test.dart
git commit -m "feat(reader): split lyric segments at word boundaries"
```

---

### Task 2: The renderer breaks at words

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_line_view.dart:56-58`
- Test: `apps/lyron_app/test/presentation/song_reader/widgets/song_line_view_test.dart`

- [ ] **Step 1: Write the failing test**

Append to `song_line_view_test.dart`, following the existing pump helper in that file:

```dart
  testWidgets('never breaks inside a word split by a chord change', (
    tester,
  ) async {
    // Narrow enough that the line must wrap. The reproduction from the spec:
    // ChordPro cuts "Igédben" in half at the chord.
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SongLineView(
            line: SongReaderLyricLineProjection(
              segments: [
                SongReaderSegmentProjection(
                  displayChord: 'E',
                  text: 'Kegyelmed elég, több, mint elég, Igé',
                ),
                SongReaderSegmentProjection(
                  displayChord: 'G#m',
                  text: 'dben bízok én',
                ),
              ],
            ),
            viewMode: SongReaderViewMode.chordsAndLyrics,
            sharedFontScale: 1,
          ),
        ),
      ),
    );

    // Every rendered lyric box holds at most one word: no box may contain
    // whitespace with text on both sides of it.
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .where((t) => t.trim().isNotEmpty)
        .toList();

    for (final text in texts) {
      expect(
        text.trimRight().contains(RegExp(r'\s')),
        isFalse,
        reason: 'a rendered box holds more than one word: "$text"',
      );
    }

    // And the line still says what it said before.
    expect(
      texts.where((t) => t != 'E' && t != 'G#m').join().replaceAll(RegExp(r'\s+'), ' ').trim(),
      'Kegyelmed elég, több, mint elég, Igédben bízok én',
    );
  });
```

Note for the implementer: check the existing tests in this file for how they pump `SongLineView` — reuse their helper rather than the inline `MaterialApp` above if one exists.

- [ ] **Step 2: Run the test and confirm it fails**

Run: `cd apps/lyron_app && flutter test test/presentation/song_reader/widgets/song_line_view_test.dart`
Expected: FAIL — a box holds `Kegyelmed elég, több, mint elég, Igé`.

- [ ] **Step 3: Apply the splitter in the renderer**

In `song_line_view.dart`, change line 57 from

```dart
                for (final group in groupSegmentsIntoWords(line.segments))
```

to

```dart
                for (final group in groupSegmentsIntoWords(
                  splitSegmentsAtWordBoundaries(line.segments),
                ))
```

Leave the chord-only branch (the `else` list at lines 79-88) exactly as it is: those segments carry no words and must keep their own chord slots and `chordOnlySpacing`.

Update the comment above the branch: word grouping now runs over word-sized pieces rather than raw ChordPro segments, and that is what makes the "break only at source whitespace" claim true.

- [ ] **Step 4: Run the test and confirm it passes**

Run: `cd apps/lyron_app && flutter test test/presentation/song_reader/widgets/song_line_view_test.dart`
Expected: PASS.

- [ ] **Step 5: Confirm the estimator suites are now RED**

Run:
```bash
cd apps/lyron_app && flutter test \
  test/presentation/song_reader/song_line_view_estimate_consistency_test.dart \
  test/presentation/song_reader/song_reader_estimate_render_consistency_test.dart
```
Expected: **likely FAIL.** The renderer now lays out a different number of boxes than the estimator models. Do not fix the fixtures — Task 3 moves the estimator to match. Record which fixtures moved and by how much; Task 5 needs those numbers.

If they are green, that is a real result, not a licence to skip Task 3: the estimator still calls `groupSegmentsIntoWords` on unsplit segments, and Task 3 is what keeps the two definitions from drifting.

- [ ] **Step 6: Commit**

```bash
git add apps/lyron_app/lib/src/presentation/song_reader/widgets/song_line_view.dart apps/lyron_app/test/presentation/song_reader/widgets/song_line_view_test.dart
git commit -m "fix(reader): break lyric lines at word boundaries, not inside words"
```

---

### Task 3: The estimator models the same split

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_fit.dart:695-701`

- [ ] **Step 1: Apply the splitter in the estimator**

Change the `groups` expression at line 695 from

```dart
      final groups = hasLyrics
          ? groupSegmentsIntoWords(
              item.segments,
            ).map((group) => group.segments).toList(growable: false)
```

to

```dart
      final groups = hasLyrics
          ? groupSegmentsIntoWords(
              splitSegmentsAtWordBoundaries(item.segments),
            ).map((group) => group.segments).toList(growable: false)
```

Update the comment immediately above it: it currently says the grouping mirrors `song_line_view.dart`, which stays true — say that both now split at word boundaries first, and why (a ChordPro segment is not a word).

- [ ] **Step 2: Run the estimator suites**

Run:
```bash
cd apps/lyron_app && flutter test \
  test/presentation/song_reader/song_line_view_estimate_consistency_test.dart \
  test/presentation/song_reader/song_reader_block_estimate_consistency_test.dart \
  test/presentation/song_reader/song_reader_estimate_render_consistency_test.dart \
  test/presentation/song_reader/song_reader_fit_test.dart \
  test/presentation/song_reader/song_reader_fit_to_screen_test.dart
```
Expected: PASS.

If a fixture is red because the estimate now falls **below** the render, that is the failure this whole file exists to prevent — stop and use `superpowers:systematic-debugging`. Do not raise the fixture's expected value to make it pass. If a fixture is red because the estimate rose (a looser but still valid bound), record the new number; Task 5 documents it.

- [ ] **Step 3: Commit**

```bash
git add apps/lyron_app/lib/src/presentation/song_reader/song_reader_fit.dart
git commit -m "fix(reader): model word-boundary splitting in the fit estimator"
```

---

### Task 4: Prove the two definitions cannot drift apart

The renderer and the estimator now both call `splitSegmentsAtWordBoundaries` then `groupSegmentsIntoWords`. Nothing stops a future change from adding the split in one place only. This task pins the pairing.

**Files:**
- Test: `apps/lyron_app/test/presentation/song_reader/song_reader_word_groups_test.dart`

- [ ] **Step 1: Write the test**

```dart
  test(
    'the renderer and the estimator both split before grouping',
    () {
      // A guard, not a behaviour test: both call sites must apply the splitter,
      // or the estimate stops describing what is drawn. Checked by source
      // inspection because the two call sites are in different layers and
      // neither exposes its grouping.
      final renderer = File(
        'lib/src/presentation/song_reader/widgets/song_line_view.dart',
      ).readAsStringSync();
      final estimator = File(
        'lib/src/presentation/song_reader/song_reader_fit.dart',
      ).readAsStringSync();

      for (final source in [renderer, estimator]) {
        expect(
          source.contains('groupSegmentsIntoWords'),
          isTrue,
        );
        expect(
          source.contains(
            'groupSegmentsIntoWords(\n              splitSegmentsAtWordBoundaries(',
          ),
          isTrue,
          reason:
              'groupSegmentsIntoWords must be called on split segments; '
              'grouping raw ChordPro segments reintroduces the mid-word break',
        );
      }
    },
  );
```

Note for the implementer: this asserts on formatted source, so it breaks if `dart format` rewraps those lines. If that turns out to be brittle in practice, replace the exact-string match with a whitespace-insensitive regex over the two call sites (`RegExp(r'groupSegmentsIntoWords\(\s*splitSegmentsAtWordBoundaries\(')`) rather than deleting the guard. Add `import 'dart:io';`.

- [ ] **Step 2: Run and confirm it passes**

Run: `cd apps/lyron_app && flutter test test/presentation/song_reader/song_reader_word_groups_test.dart`
Expected: PASS. If it fails, the previous two tasks are incomplete.

- [ ] **Step 3: Commit**

```bash
git add apps/lyron_app/test/presentation/song_reader/song_reader_word_groups_test.dart
git commit -m "test(reader): pin that both layers split before grouping"
```

---

### Task 5: Consistency fixtures for the new shape, and the measurement record

**Files:**
- Modify: `apps/lyron_app/test/presentation/song_reader/song_line_view_estimate_consistency_test.dart`
- Modify: `docs/deferred/2026-07-28-reader-fit-conservatism-margin.md`

- [ ] **Step 1: Add render-vs-estimate fixtures**

Follow the existing fixture style in that file (it renders a real `SongLineView`, measures its height, and asserts `estimated >= rendered`). Add three:

1. **The reproduction**, at a 375px-wide column: the two segments from Task 2.
2. **A word split into three segments** — `al` / `ph` / `a beta`, chords on each — at a width where the line wraps, so the split word's pieces stay together across a break.
3. **A single word longer than the line** — one segment, no whitespace, ~40 characters, at a 130px column — which must still take the over-wide branch and wrap inside itself.

- [ ] **Step 2: Run them**

Run: `cd apps/lyron_app && flutter test test/presentation/song_reader/song_line_view_estimate_consistency_test.dart`
Expected: PASS, with `estimated >= rendered` for all three.

- [ ] **Step 3: Record the measurements**

Append a section to `docs/deferred/2026-07-28-reader-fit-conservatism-margin.md` titled `## Word-boundary splitting (2026-08-10)`, matching the existing sections' format: what changed, why, and a table of `Line shape | Rendered | Estimated | Ratio` for the three new fixtures plus any pre-existing fixture whose numbers moved.

State explicitly whether the overshoot ratios improved, worsened or held. This document records the estimator's conservatism; it is **not** resolved by this PR and must not be deleted.

- [ ] **Step 4: Commit**

```bash
git add apps/lyron_app/test/presentation/song_reader/song_line_view_estimate_consistency_test.dart docs/deferred/2026-07-28-reader-fit-conservatism-margin.md
git commit -m "test(reader): pin render-vs-estimate for word-split lines"
```

---

### Task 6: Cost check

The split produces one box per word instead of one per ChordPro segment. `resolveFitFontScale` binary-searches ~24 times over every line, so per-line box count is on a hot path.

- [ ] **Step 1: Measure**

Run the fit suites with timing and compare against `main`:

```bash
cd apps/lyron_app
git stash list  # ensure a clean tree first
time flutter test test/presentation/song_reader/song_reader_fit_test.dart test/presentation/song_reader/song_reader_fit_to_screen_test.dart
git stash push -u && git checkout main -- lib/src/presentation/song_reader/
time flutter test test/presentation/song_reader/song_reader_fit_test.dart test/presentation/song_reader/song_reader_fit_to_screen_test.dart
git checkout HEAD -- lib/src/presentation/song_reader/ && git stash pop
```

- [ ] **Step 2: Decide**

Test wall-clock is a weak proxy for reader interaction cost, so treat it as a smoke check, not a benchmark. If the run time is within noise, note the numbers in the PR body and move on. If it is materially worse (say, over 25%), stop and report before proceeding — a real fit-layout performance regression test is already listed as missing in the repository review, and this would be the trigger to write one rather than to absorb the cost silently.

- [ ] **Step 3: Commit** (only if anything changed; otherwise skip)

---

### Task 7: Verify and open the PR

- [ ] **Step 1: Full gate**

Run: `./scripts/verify.sh`
Expected: green.

- [ ] **Step 2: Visual proof**

Run: `FLUTTER_DEVICE=web-server ./scripts/run-authenticated-app.sh`

Wait for Flutter to report it is serving, then open the printed single-use magic link (it lands on `http://localhost:8080` already signed in). Open "A mi Istenünk (Leborulok előtted)".

Capture **375x812** before and after: the before shot shows `Igé` / `dben bízok én`, the after shot must show the break at a real word boundary. Capture **834x1194** too, to show nothing changed where lines already fit.

Note: the reader is CanvasKit, so there is no DOM to assert against and the browser tools' `read_page` returns nothing useful — screenshots are the evidence here.

- [ ] **Step 3: Open the PR**

Body must state: the root cause (segment-granularity grouping, not an over-wide-group gap), that renderer and estimator moved together, the new fixtures' ratios, the cost-check numbers, and that no typography or spacing changed. Include the before/after 375px pair.

---

## What PR3 will need from this PR

- `splitSegmentsAtWordBoundaries` is the shared pre-pass; PR3's type-scale change does not touch it, but every new fixture PR3 measures will be laid out through it.
- `_breakableWhitespace` now exists in two files (`song_reader_word_groups.dart` and `song_reader_fit.dart`). They must stay identical. If PR3 touches either, unify them into one shared definition at that point — doing it here would widen this PR past its one job.
