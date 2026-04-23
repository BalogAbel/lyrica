# Song Reader Capo And Instrument Display Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add ChordPro-driven capo and transpose defaults plus guitar/piano reader display modes, starting with prototype validation and then implementing the Flutter reader slice without writing back to ChordPro.

**Architecture:** Keep the parsed song canonical and add ChordPro base metadata for `sourceKey`, `capo`, and global `transpose`. Compute effective display values in reader projection from base values plus reader-local runtime deltas, then let presentation choose guitar or piano chord rendering and show or hide capo-specific controls. Prototype changes land first in `docs/prototypes/`, then parser/state/projection/UI changes follow under `apps/lyron_app/`.

**Tech Stack:** Flutter, Material 3, Riverpod, flutter_test, static HTML/CSS/JS prototype

---

### Task 1: Update Prototype First

**Files:**
- Modify: `docs/prototypes/song-reader-reader-mockup.html`
- Modify: `docs/prototypes/song-reader-reader-mockup.css`
- Modify: `docs/prototypes/song-reader-reader-mockup.js`

- [ ] **Step 1: Add mockup structure for instrument mode and capo surfaces**

Update the prototype markup so it can express:

- overflow-style instrument selection in the top-right actions area
- guitar-only capo directive line inside the song flow
- guitar-only capo control beside transpose in overlay and expanded tools
- effective value labels for `Transpose` and `Capo`

Keep the current compact/expanded split intact.

- [ ] **Step 2: Add mockup interaction state in JavaScript**

Teach the prototype to track:

- `instrumentMode` with `guitar` and `piano`
- `baseTranspose`
- `baseCapo`
- `runtimeTransposeDelta`
- `runtimeCapoDelta`

Compute and render:

- effective transpose
- effective capo
- guitar visible chords
- piano visible chords

The UI must show effective values, not deltas.

- [ ] **Step 3: Add mockup styling for hidden and visible capo surfaces**

Style:

- instrument switch affordance in the existing top-right action cluster
- capo directive line so it reads like a ChordPro-native line, not a badge
- guitar-only control visibility in overlay and expanded tools panel

- [ ] **Step 4: Manually verify prototype states**

Check in browser:

- compact guitar mode shows capo directive + capo control
- compact piano mode hides both
- expanded guitar mode shows capo control in tools panel
- expanded piano mode hides capo control
- transpose and capo labels show effective values when changed

Expected: prototype matches approved design before Flutter edits begin.

### Task 2: Extend Parsed Song Metadata From ChordPro

**Files:**
- Modify: `apps/lyron_app/lib/src/domain/song/parsed_song.dart`
- Modify: `apps/lyron_app/lib/src/infrastructure/song_library/chordpro/chordpro_parser.dart`
- Test: `apps/lyron_app/test/domain/song/parsed_song_model_test.dart`
- Test: `apps/lyron_app/test/infrastructure/song_library/chordpro/chordpro_parser_test.dart`
- Test: `apps/lyron_app/test/infrastructure/song_library/chordpro/chordpro_reference_songs_test.dart`

- [ ] **Step 1: Write failing parser tests for global capo and global transpose**

Add focused tests that prove:

- `{capo: 2}` is parsed into parsed-song metadata
- `{transpose: -2}` at song start is parsed into parsed-song metadata
- absent directives default to `0`
- later in-song `{transpose: ...}` does not change parsed-song global metadata in this slice

Run:

```bash
flutter test \
  apps/lyron_app/test/infrastructure/song_library/chordpro/chordpro_parser_test.dart \
  apps/lyron_app/test/domain/song/parsed_song_model_test.dart \
  apps/lyron_app/test/infrastructure/song_library/chordpro/chordpro_reference_songs_test.dart
```

Expected: FAIL because `ParsedSong` and parser only carry `sourceKey`.

- [ ] **Step 2: Extend `ParsedSong` with ChordPro base metadata**

Add reader-facing parsed metadata fields:

- `sourceKey`
- `baseTranspose`
- `baseCapo`

Preserve equality and hash behavior.

- [ ] **Step 3: Implement parser support for global `capo` and global `transpose`**

Parse:

- `key`
- `capo`
- `transpose`

Rules:

- treat missing `capo` and `transpose` as `0`
- only persist the song-start/global transpose value in this slice
- keep unsupported later modulation visible as future work, not silent feature creep

- [ ] **Step 4: Re-run parser tests**

Run:

```bash
flutter test \
  apps/lyron_app/test/infrastructure/song_library/chordpro/chordpro_parser_test.dart \
  apps/lyron_app/test/domain/song/parsed_song_model_test.dart \
  apps/lyron_app/test/infrastructure/song_library/chordpro/chordpro_reference_songs_test.dart
```

Expected: PASS.

### Task 3: Add Reader Instrument State And Effective Projection Rules

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_state.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_controller.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/session_scoped_reader_runtime_state.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/session_scoped_reader_runtime_controller.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_projection.dart`
- Test: `apps/lyron_app/test/presentation/song_reader/song_reader_controller_test.dart`
- Test: `apps/lyron_app/test/presentation/song_reader/session_scoped_reader_runtime_controller_test.dart`
- Test: `apps/lyron_app/test/presentation/song_reader/song_reader_projection_test.dart`

- [ ] **Step 1: Add failing tests for instrument mode and effective values**

Cover:

- default instrument mode is guitar
- controller initializes effective transpose from parsed `baseTranspose`
- controller initializes effective capo from parsed `baseCapo`
- guitar projection subtracts effective capo from sounding chord
- piano projection does not subtract capo
- UI-facing projection exposes effective capo/directive visibility for guitar only

Run:

```bash
flutter test \
  apps/lyron_app/test/presentation/song_reader/song_reader_controller_test.dart \
  apps/lyron_app/test/presentation/song_reader/session_scoped_reader_runtime_controller_test.dart \
  apps/lyron_app/test/presentation/song_reader/song_reader_projection_test.dart
```

Expected: FAIL because reader state has no instrument mode or capo runtime state.

- [ ] **Step 2: Extend reader state with instrument and capo runtime fields**

Add:

- instrument display mode enum
- runtime transpose delta
- runtime capo delta

Keep UI-facing helpers or projection inputs sufficient to compute:

- effective transpose
- effective capo

- [ ] **Step 3: Extend controllers with initialization and adjustment actions**

Add minimal actions for:

- switching guitar/piano mode
- initializing runtime state from parsed-song base metadata
- increasing and decreasing effective transpose through delta updates
- increasing and decreasing effective capo through delta updates

Keep scoped and unscoped parity.

- [ ] **Step 4: Update projection to compute effective display**

Projection must compute:

- `effectiveTranspose = baseTranspose + runtimeTransposeDelta`
- `effectiveCapo = max(0, baseCapo + runtimeCapoDelta)`
- `concertChord = originalChord + effectiveTranspose`
- guitar visible chord = `concertChord - effectiveCapo`
- piano visible chord = `concertChord`

Also expose:

- current instrument mode
- effective transpose label value
- effective capo label value
- guitar-only capo directive visibility

- [ ] **Step 5: Re-run reader state and projection tests**

Run:

```bash
flutter test \
  apps/lyron_app/test/presentation/song_reader/song_reader_controller_test.dart \
  apps/lyron_app/test/presentation/song_reader/session_scoped_reader_runtime_controller_test.dart \
  apps/lyron_app/test/presentation/song_reader/song_reader_projection_test.dart
```

Expected: PASS.

### Task 4: Implement Guitar And Piano UI In Flutter Reader

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_screen.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_header.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_compact_overlay.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_expanded_tools_panel.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_section_view.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_line_view.dart`
- Test: `apps/lyron_app/test/presentation/song_reader/song_reader_screen_test.dart`
- Test: `apps/lyron_app/test/presentation/song_reader/widgets/song_reader_compact_overlay_test.dart`
- Test: `apps/lyron_app/test/presentation/song_reader/widgets/song_line_view_test.dart`
- Test: `apps/lyron_app/test/presentation/song_reader/widgets/song_section_view_test.dart`

- [ ] **Step 1: Add failing widget tests for guitar and piano reader surfaces**

Cover:

- overflow menu contains `Guitar view` and `Piano view`
- switching to piano hides capo directive and capo controls
  - switching to guitar shows capo directive when effective capo > 0
  - transpose remains visible in both modes
  - capo control label shows effective capo value
  - capo row stays visible in guitar mode when effective capo is 0, but the down button is disabled
  - transpose control label shows effective transpose value
  - rendered chord text changes between guitar and piano views as expected

Run:

```bash
flutter test \
  apps/lyron_app/test/presentation/song_reader/song_reader_screen_test.dart \
  apps/lyron_app/test/presentation/song_reader/widgets/song_reader_compact_overlay_test.dart \
  apps/lyron_app/test/presentation/song_reader/widgets/song_line_view_test.dart \
  apps/lyron_app/test/presentation/song_reader/widgets/song_section_view_test.dart
```

Expected: FAIL because current UI has no instrument mode and no capo UI.

- [ ] **Step 2: Move instrument selection into the overflow menu**

Update screen overflow actions so the top-right `...` menu can switch between:

- `Guitar view`
- `Piano view`

Do not add a persistent on-screen toggle outside the menu.

- [ ] **Step 3: Update header and tool surfaces to show effective values**

Adjust overlay and expanded tools so they show:

- effective transpose in both modes
- effective capo only in guitar mode
- current mode-appropriate actions without exposing raw delta values

- [ ] **Step 4: Render capo directive line in song content for guitar mode**

Render a directive-style line near the start of the song content when:

- current mode is guitar
- effective capo > 0

Hide it fully in piano mode.

- [ ] **Step 5: Re-run focused reader widget tests**

Run:

```bash
flutter test \
  apps/lyron_app/test/presentation/song_reader/song_reader_screen_test.dart \
  apps/lyron_app/test/presentation/song_reader/widgets/song_reader_compact_overlay_test.dart \
  apps/lyron_app/test/presentation/song_reader/widgets/song_line_view_test.dart \
  apps/lyron_app/test/presentation/song_reader/widgets/song_section_view_test.dart
```

Expected: PASS.

### Task 5: Update Deferred Docs And Verify Slice

**Files:**
- Create: `docs/deferred/2026-04-22-song-reader-chordpro-modulation.md`
- Modify: `docs/testing/testing-strategy.md`
- Modify: `docs/specs/2026-04-22-song-reader-capo-and-instrument-display.md`
- Modify: `docs/plans/2026-04-22-song-reader-capo-and-instrument-display.md`

- [ ] **Step 1: Record deferred in-song transpose modulation**

Add a deferred note that states:

- this slice only supports global ChordPro transpose
- later `{transpose: ...}` modulation inside the song body is still unsupported
- future work must reconcile parser, projection, and section rendering for modulation-aware display

- [ ] **Step 2: Update testing guidance if new reader-state expectations matter**

If the slice adds a durable testing rule, document it in `docs/testing/testing-strategy.md`, especially around:

- parser tests for ChordPro directive semantics
- projection tests for instrument-specific chord display

If no durable rule changes, keep doc edits minimal and consistent with actual shipped behavior.

- [ ] **Step 3: Run focused verification**

Run:

```bash
flutter test \
  apps/lyron_app/test/infrastructure/song_library/chordpro/chordpro_parser_test.dart \
  apps/lyron_app/test/domain/song/parsed_song_model_test.dart \
  apps/lyron_app/test/presentation/song_reader/song_reader_controller_test.dart \
  apps/lyron_app/test/presentation/song_reader/session_scoped_reader_runtime_controller_test.dart \
  apps/lyron_app/test/presentation/song_reader/song_reader_projection_test.dart \
  apps/lyron_app/test/presentation/song_reader/song_reader_screen_test.dart \
  apps/lyron_app/test/presentation/song_reader/widgets/song_reader_compact_overlay_test.dart \
  apps/lyron_app/test/presentation/song_reader/widgets/song_line_view_test.dart \
  apps/lyron_app/test/presentation/song_reader/widgets/song_section_view_test.dart
```

Expected: PASS.

- [ ] **Step 4: Run repository verification script**

Run:

```bash
./scripts/verify.sh
```

Expected: PASS, or document any unrelated pre-existing failure before merge.

- [ ] **Step 5: Mark docs with final status**

After implementation and verification:

- update spec status from proposed to implemented
- update this plan with completion marks
- keep deferred note active until modulation support ships
