# UX-3 Non-Copyrighted Default Song Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the copyrighted worship-song `defaultSource` in the song editor with an original, non-copyrighted ChordPro sample.

**Architecture:** Single-const change in `SongEditorController`. A characterization test pins the default to non-copyrighted content first (TDD). `song_editor_screen.dart` reads the const symbol and inherits the new value with no edit.

**Tech Stack:** Dart / Flutter, `flutter_test`, ChordPro parsing (`ChordProLineScanner`).

**Spec:** `docs/specs/2026-07-08-ux3-noncopyrighted-default-song.md`

---

## File Structure

- Modify: `apps/lyron_app/lib/src/presentation/song_editor/song_editor_controller.dart` — the `defaultSource` const (lines 15-29).
- Test: `apps/lyron_app/test/presentation/song_editor/song_editor_controller_test.dart` — add default-source characterization test.
- Docs: `docs/architecture/repository-review-2026-06-22.md` — mark UX-3 fixed.

No other files change. `song_editor_screen.dart:50` references `SongEditorController.defaultSource` by symbol; it updates automatically.

---

## Task 1: Characterize the non-copyrighted default source

**Files:**
- Test: `apps/lyron_app/test/presentation/song_editor/song_editor_controller_test.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_editor/song_editor_controller.dart:15-29`

- [ ] **Step 1: Write the failing test**

Add this test to the existing `main()` group in
`song_editor_controller_test.dart` (import for the controller already present):

```dart
  test('default source is non-copyrighted and parses as valid ChordPro', () {
    final controller = SongEditorController();
    final source = controller.state.source;

    // No copyrighted markers from the previous hardcoded worship song.
    expect(source, isNot(contains('Heart of Worship')));
    expect(source, isNot(contains('Matt Redman')));
    expect(source, isNot(contains('When the music fades')));

    // Still a valid, parseable ChordPro sample with the placeholder title.
    expect(controller.state.parsedSong.title, 'My New Song');
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/lyron_app && flutter test test/presentation/song_editor/song_editor_controller_test.dart --plain-name 'default source is non-copyrighted'`
Expected: FAIL — current default contains `Heart of Worship` / `Matt Redman` and title is `Heart of Worship`.

- [ ] **Step 3: Replace the default source const**

In `song_editor_controller.dart`, replace the `defaultSource` const body
(currently lines 15-29) with:

```dart
  static const defaultSource = '''
{title: My New Song}
{artist: }
{key: C}
{tempo: 120}
{tags: }
{transpose: 0}
{capo: 0}

{comment: Replace this sample with your own lyrics}
[C]Type a line of lyrics and put [G]chords in brackets
[Am]Delete these lines when you [F]start your song
''';
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/lyron_app && flutter test test/presentation/song_editor/song_editor_controller_test.dart --plain-name 'default source is non-copyrighted'`
Expected: PASS.

- [ ] **Step 5: Run the full song-editor suite for regression**

Run: `cd apps/lyron_app && flutter test test/presentation/song_editor/ test/router/song_editor_route_test.dart`
Expected: PASS — fixture-based tests pass explicit `source:` values and are unaffected.

- [ ] **Step 6: Commit**

```bash
git add apps/lyron_app/test/presentation/song_editor/song_editor_controller_test.dart apps/lyron_app/lib/src/presentation/song_editor/song_editor_controller.dart
git commit -m "fix(song-editor): replace copyrighted default with original ChordPro sample"
```

---

## Task 2: Mark UX-3 fixed in the repository review

**Files:**
- Modify: `docs/architecture/repository-review-2026-06-22.md`

- [ ] **Step 1: Update the UX-3 status**

Follow the exact convention used for SEC-5 (PR #57). The summary tables (lines
68/77-style and 329) are left untouched, matching the SEC-5 precedent. Two edits:

**a) Add a bullet to the `**Fixed**` digest** (around line 108, after the SEC-5
bullet), matching the existing bullet style:

```markdown
- **UX-3** (arch-spine-phase0-1 slice) — the copyrighted worship-song
  `defaultSource` in the song editor is replaced with an original,
  non-copyrighted ChordPro sample that doubles as a syntax hint
  (`apps/lyron_app/lib/src/presentation/song_editor/song_editor_controller.dart`).
  Pinned by a failing-then-passing characterization test.
```

**b) Strike through the remediation-list item** (line 443), matching the
SEC-5/LF-T1 style:

```markdown
- ~~UX-3: replace the copyrighted default song body with a non-copyrighted placeholder/hint.~~ **Done (arch-spine-phase0-1).**
```

Verify the exact current wording of line 443 with a read before editing, since
line numbers may drift.

- [ ] **Step 2: Commit**

```bash
git add docs/architecture/repository-review-2026-06-22.md
git commit -m "docs(review): mark UX-3 fixed (non-copyrighted default song)"
```

---

## Self-Review

- **Spec coverage:** default replacement (Task 1), UX-3 doc status (Task 2), TDD failing-test-first (Task 1 steps 1-2), regression guard (Task 1 step 5). All spec sections covered.
- **Placeholders:** none — full test and const code inline.
- **Type consistency:** `SongEditorController()` no-arg default, `.state.source`, `.state.parsedSong.title` all match existing controller API used elsewhere in the same test file.

---

## Done when

- New test written and failing first, then green.
- `defaultSource` contains no copyrighted lyrics; title is `My New Song`.
- Song-editor + router suites green.
- UX-3 marked fixed in the review doc.
