# Tablet-First ChordPro Song Reader Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first real Lyrica product slice as an asset-backed, tablet-first ChordPro song list and reader flow with parser diagnostics, view mode switching, semitone transposition, and shared font scaling.

**Architecture:** Keep the slice vertical but bounded. Introduce a small song domain and repository contract, parse an explicit ChordPro subset into durable song structures with diagnostics, and project that model into a tablet-first reader UI through Riverpod and go_router. Do not add persistence, auth, backend adapters, or speculative import/editing abstractions.

**Tech Stack:** Flutter, Riverpod, go_router, Flutter widget tests, Dart unit tests, asset bundles

---

### Task 1: Register Mock Song Assets And Stable App Copy

**Files:**
- Modify: `apps/lyrica_app/pubspec.yaml`
- Modify: `apps/lyrica_app/lib/src/shared/app_strings.dart`
- Test: `apps/lyrica_app/test/app/lyrica_app_test.dart`

- [ ] **Step 1: Write the failing app-shell test updates**

Update `apps/lyrica_app/test/app/lyrica_app_test.dart` to expect the song-library shell instead of the current repository-foundation placeholder copy.

- [ ] **Step 2: Run the app-shell widget test to verify it fails**

Run: `cd apps/lyrica_app && flutter test test/app/lyrica_app_test.dart`
Expected: FAIL because the old home screen copy still renders.

- [ ] **Step 3: Add mock song asset declarations**

Modify `apps/lyrica_app/pubspec.yaml` to include:

```yaml
flutter:
  uses-material-design: true
  assets:
    - assets/songs/
```

- [ ] **Step 4: Replace placeholder app strings with slice-specific copy**

Modify `apps/lyrica_app/lib/src/shared/app_strings.dart` so the app shell names the song library and reader flow instead of the bootstrap foundation status text.

- [ ] **Step 5: Re-run the app-shell widget test to verify it passes**

Run: `cd apps/lyrica_app && flutter test test/app/lyrica_app_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add apps/lyrica_app/pubspec.yaml apps/lyrica_app/lib/src/shared/app_strings.dart apps/lyrica_app/test/app/lyrica_app_test.dart
git commit -m "feat(app): register song assets and reader shell copy"
```

### Task 2: Add Mock Song Assets And Repository Contract

Implementation note: this slice now uses the three bundled `.pro` assets in `apps/lyrica_app/assets/songs/` as the first mock catalog, keeps `SongLibraryService` thin, exposes minimal summaries plus raw ChordPro source at the repository boundary, and routes missing song IDs through a domain-level `SongNotFoundException`.

**Files:**
- Create: `apps/lyrica_app/assets/songs/a_forrasnal.pro`
- Create: `apps/lyrica_app/assets/songs/a_mi_istenunk.pro`
- Create: `apps/lyrica_app/assets/songs/egy_ut.pro`
- Create: `apps/lyrica_app/lib/src/domain/song/song_summary.dart`
- Create: `apps/lyrica_app/lib/src/domain/song/song_source.dart`
- Create: `apps/lyrica_app/lib/src/domain/song/song_repository.dart`
- Create: `apps/lyrica_app/lib/src/application/song_library/song_library_service.dart`
- Create: `apps/lyrica_app/lib/src/infrastructure/song_library/asset_song_repository.dart`
- Test: `apps/lyrica_app/test/application/song_library/song_library_service_test.dart`
- Test: `apps/lyrica_app/test/infrastructure/song_library/asset_song_repository_test.dart`

- [ ] **Step 1: Copy the three reference songs into app assets**

Create the three files under `apps/lyrica_app/assets/songs/` using the current `docs/examples/chordpro/*.pro` sources as the initial mock catalog.

- [ ] **Step 2: Write the failing repository and service tests**

Add tests that define the minimum repository contract:

```dart
expect(await repository.listSongs(), hasLength(3));
expect((await repository.listSongs()).map((song) => song.title), contains('Egy út'));
expect((await repository.getSongSource('egy_ut')).source, contains('{title:Egy út}'));
```

The implemented coverage now also verifies the full catalog-to-asset mapping and the per-song asset-content invariants for each listed ID.

- [ ] **Step 3: Run the focused tests to verify they fail**

Run: `cd apps/lyrica_app && flutter test test/application/song_library/song_library_service_test.dart test/infrastructure/song_library/asset_song_repository_test.dart`
Expected: FAIL because the domain types and repository implementation do not exist yet.

- [ ] **Step 4: Add the minimal song repository contract and DTOs**

Create focused domain types for:

```dart
abstract interface class SongRepository {
  Future<List<SongSummary>> listSongs();
  Future<SongSource> getSongSource(String id);
}
```

Keep `SongSummary` minimal for this slice: `id`, `title`.

- [ ] **Step 5: Implement the asset-backed repository and simple service**

Use `rootBundle` in `asset_song_repository.dart` and keep asset-to-song metadata mapping explicit and local to the infrastructure layer. `song_library_service.dart` should orchestrate list/detail access without leaking asset paths to the UI.

- [ ] **Step 6: Re-run the focused tests to verify they pass**

Run: `cd apps/lyrica_app && flutter test test/application/song_library/song_library_service_test.dart test/infrastructure/song_library/asset_song_repository_test.dart`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add apps/lyrica_app/assets/songs apps/lyrica_app/lib/src/domain/song apps/lyrica_app/lib/src/application/song_library apps/lyrica_app/lib/src/infrastructure/song_library apps/lyrica_app/test/application/song_library apps/lyrica_app/test/infrastructure/song_library
git commit -m "feat(song-library): add mock song repository"
```

### Task 3: Define Parsed Song Model And Diagnostics

**Files:**
- Create: `apps/lyrica_app/lib/src/domain/song/parsed_song.dart`
- Create: `apps/lyrica_app/lib/src/domain/song/song_section.dart`
- Create: `apps/lyrica_app/lib/src/domain/song/song_line.dart`
- Create: `apps/lyrica_app/lib/src/domain/song/lyric_segment.dart`
- Create: `apps/lyrica_app/lib/src/domain/song/parse_diagnostic.dart`
- Test: `apps/lyrica_app/test/domain/song/parsed_song_model_test.dart`

- [ ] **Step 1: Write the failing parsed-song model tests**

Define the expected durable structure for a parsed song:

```dart
expect(song.title, 'A forrásnál');
expect(song.subtitle, 'Ha szólsz megdobban a szív');
expect(song.sections.first.label, 'Verse');
expect(song.sections.first.number, isNull);
expect(song.diagnostics, isEmpty);
```

- [ ] **Step 2: Run the domain test to verify it fails**

Run: `cd apps/lyrica_app && flutter test test/domain/song/parsed_song_model_test.dart`
Expected: FAIL because the parsed-song domain types do not exist.

- [ ] **Step 3: Add focused domain types for parsed song structure**

Model:
- song metadata
- ordered sections
- section kind and optional number
- ordered lines
- lyric segments with optional leading chord
- parse diagnostics with severity and line metadata

Do not put parser logic in these files.

- [ ] **Step 4: Re-run the domain test to verify it passes**

Run: `cd apps/lyrica_app && flutter test test/domain/song/parsed_song_model_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/lyrica_app/lib/src/domain/song apps/lyrica_app/test/domain/song/parsed_song_model_test.dart
git commit -m "feat(song-domain): add parsed song model"
```

### Task 4: Implement Chord Symbol Parsing And Transposition

**Files:**
- Create: `apps/lyrica_app/lib/src/domain/song/chord_symbol.dart`
- Create: `apps/lyrica_app/lib/src/infrastructure/song_library/chord_transposer.dart`
- Test: `apps/lyrica_app/test/domain/song/chord_symbol_test.dart`
- Test: `apps/lyrica_app/test/infrastructure/song_library/chord_transposer_test.dart`

- [ ] **Step 1: Write the failing chord-model and transposition tests**

Cover:
- major and minor chords
- slash chords
- parenthesized chords
- repeated semitone movement

Example expectations:

```dart
expect(ChordSymbol.parse('E/G#').bassNoteName, 'G#');
expect(ChordSymbol.parse('(B)').isParenthesized, isTrue);
expect(transposer.transpose('F#m', 1), 'Gm');
expect(transposer.transpose('E/G#', -1), 'D#/G');
```

- [ ] **Step 2: Run the focused tests to verify they fail**

Run: `cd apps/lyrica_app && flutter test test/domain/song/chord_symbol_test.dart test/infrastructure/song_library/chord_transposer_test.dart`
Expected: FAIL because chord parsing and transposition are not implemented.

- [ ] **Step 3: Add the minimal musical chord model**

Implement parsing into structured parts:
- root pitch class
- suffix quality text
- optional bass pitch class
- optional parenthesized wrapper flag

Keep displayed note names in international notation and centralize pitch-class logic in one place.

- [ ] **Step 4: Implement semitone transposition on the model**

`chord_transposer.dart` should transpose root and bass notes through the model, then render a display string. Do not use chained string replacement.

- [ ] **Step 5: Re-run the focused tests to verify they pass**

Run: `cd apps/lyrica_app && flutter test test/domain/song/chord_symbol_test.dart test/infrastructure/song_library/chord_transposer_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add apps/lyrica_app/lib/src/domain/song/chord_symbol.dart apps/lyrica_app/lib/src/infrastructure/song_library/chord_transposer.dart apps/lyrica_app/test/domain/song/chord_symbol_test.dart apps/lyrica_app/test/infrastructure/song_library/chord_transposer_test.dart
git commit -m "feat(chords): add chord model and semitone transposition"
```

### Task 5: Parse Supported ChordPro Metadata, Sections, And Lines

**Files:**
- Create: `apps/lyrica_app/lib/src/infrastructure/song_library/chordpro/chordpro_line_scanner.dart`
- Create: `apps/lyrica_app/lib/src/infrastructure/song_library/chordpro/chordpro_parser.dart`
- Test: `apps/lyrica_app/test/infrastructure/song_library/chordpro/chordpro_parser_test.dart`
- Test: `apps/lyrica_app/test/infrastructure/song_library/chordpro/chordpro_reference_songs_test.dart`

- [ ] **Step 1: Write the failing parser tests for the supported subset**

Use the three reference songs as the primary acceptance corpus. Cover:
- `title`, `subtitle`, `key`
- `comment:<Verse>`, `comment:<Verse 1>`, `comment:<Chorus>`, `comment:<Bridge>`
- `start_of_chorus`, `end_of_chorus`
- empty lines
- inline chord/lyric segmentation

Example expectation:

```dart
final song = parser.parse(source);
expect(song.title, 'A mi Istenünk (Leborulok előtted)');
expect(song.sections.where((s) => s.label == 'Chorus'), isNotEmpty);
expect(song.sections.first.lines.first.segments.first.chord?.displayName, 'E');
```

- [ ] **Step 2: Run the parser tests to verify they fail**

Run: `cd apps/lyrica_app && flutter test test/infrastructure/song_library/chordpro/chordpro_parser_test.dart test/infrastructure/song_library/chordpro/chordpro_reference_songs_test.dart`
Expected: FAIL because the parser files do not exist.

- [ ] **Step 3: Implement a small line-scanner and parser**

Responsibilities:
- classify each source line
- parse supported directives
- normalize supported section labels and optional numbering
- build ordered sections
- tokenize chord-bearing lyric lines into chord-aware segments

Unknown directives should generate diagnostics and continue.

- [ ] **Step 4: Re-run the parser tests to verify they pass**

Run: `cd apps/lyrica_app && flutter test test/infrastructure/song_library/chordpro/chordpro_parser_test.dart test/infrastructure/song_library/chordpro/chordpro_reference_songs_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/lyrica_app/lib/src/infrastructure/song_library/chordpro apps/lyrica_app/test/infrastructure/song_library/chordpro
git commit -m "feat(chordpro): parse supported song reader subset"
```

### Task 6: Add Recoverable Parse Diagnostics And Warning Policy

**Files:**
- Modify: `apps/lyrica_app/lib/src/infrastructure/song_library/chordpro/chordpro_parser.dart`
- Create: `apps/lyrica_app/lib/src/application/song_library/song_reader_result.dart`
- Test: `apps/lyrica_app/test/infrastructure/song_library/chordpro/chordpro_diagnostics_test.dart`
- Test: `apps/lyrica_app/test/application/song_library/song_reader_result_test.dart`

- [ ] **Step 1: Write failing tests for unknown directives and partial success**

Cover cases where the parser sees an unknown directive but still returns a usable song:

```dart
expect(result.song.sections, isNotEmpty);
expect(result.diagnostics.single.severity.name, 'warning');
expect(result.hasRecoverableWarnings, isTrue);
```

- [ ] **Step 2: Run the focused tests to verify they fail**

Run: `cd apps/lyrica_app && flutter test test/infrastructure/song_library/chordpro/chordpro_diagnostics_test.dart test/application/song_library/song_reader_result_test.dart`
Expected: FAIL because recoverable warning flow is incomplete.

- [ ] **Step 3: Add the minimal result type and warning policy**

`song_reader_result.dart` should pair the parsed song with derived UI-facing warning state. Keep detailed diagnostics in the result so they can be logged and surfaced selectively.

- [ ] **Step 4: Extend the parser to emit actionable diagnostics**

Include:
- severity
- line number
- directive/token context
- human-readable message

- [ ] **Step 5: Re-run the focused tests to verify they pass**

Run: `cd apps/lyrica_app && flutter test test/infrastructure/song_library/chordpro/chordpro_diagnostics_test.dart test/application/song_library/song_reader_result_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add apps/lyrica_app/lib/src/infrastructure/song_library/chordpro/chordpro_parser.dart apps/lyrica_app/lib/src/application/song_library/song_reader_result.dart apps/lyrica_app/test/infrastructure/song_library/chordpro/chordpro_diagnostics_test.dart apps/lyrica_app/test/application/song_library/song_reader_result_test.dart
git commit -m "feat(chordpro): add recoverable diagnostics"
```

### Task 7: Wire Providers And Routing For Song List And Reader

**Files:**
- Modify: `apps/lyrica_app/lib/src/application/providers.dart`
- Modify: `apps/lyrica_app/lib/src/router/app_routes.dart`
- Modify: `apps/lyrica_app/lib/src/router/app_router.dart`
- Create: `apps/lyrica_app/lib/src/presentation/song_library/song_library_providers.dart`
- Test: `apps/lyrica_app/test/router/app_router_test.dart`
- Test: `apps/lyrica_app/test/presentation/song_library/song_library_providers_test.dart`

- [ ] **Step 1: Write failing route and provider tests**

Cover:
- stable list route at `/`
- stable reader route such as `/songs/:songId`
- provider wiring that resolves repository and service dependencies

- [ ] **Step 2: Run the focused tests to verify they fail**

Run: `cd apps/lyrica_app && flutter test test/router/app_router_test.dart test/presentation/song_library/song_library_providers_test.dart`
Expected: FAIL because the new route and provider graph do not exist.

- [ ] **Step 3: Add providers for repository, parser, transposer, list loading, and reader loading**

Keep constructors narrow and avoid service locators hidden outside Riverpod providers.

- [ ] **Step 4: Update the route table**

Add:
- song list route at `/`
- song reader route at `/songs/:songId`

Keep path names explicit and stable.

- [ ] **Step 5: Re-run the focused tests to verify they pass**

Run: `cd apps/lyrica_app && flutter test test/router/app_router_test.dart test/presentation/song_library/song_library_providers_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add apps/lyrica_app/lib/src/application/providers.dart apps/lyrica_app/lib/src/router/app_routes.dart apps/lyrica_app/lib/src/router/app_router.dart apps/lyrica_app/lib/src/presentation/song_library/song_library_providers.dart apps/lyrica_app/test/router/app_router_test.dart apps/lyrica_app/test/presentation/song_library/song_library_providers_test.dart
git commit -m "feat(router): wire song list and reader providers"
```

### Task 8: Build And Test The Song List Screen

**Files:**
- Create: `apps/lyrica_app/lib/src/presentation/song_library/song_list_screen.dart`
- Modify: `apps/lyrica_app/lib/src/app/lyrica_app.dart`
- Test: `apps/lyrica_app/test/presentation/song_library/song_list_screen_test.dart`

- [ ] **Step 1: Write the failing song-list widget tests**

Cover:
- list shows song titles only
- tapping a title navigates to the reader route
- empty/loading states are reasonable and explicit

- [ ] **Step 2: Run the widget test to verify it fails**

Run: `cd apps/lyrica_app && flutter test test/presentation/song_library/song_list_screen_test.dart`
Expected: FAIL because the screen does not exist.

- [ ] **Step 3: Implement the minimal list screen**

Use a tablet-friendly scaffold with a simple title list. Do not show backend, auth, or song metadata beyond the title in this slice.

- [ ] **Step 4: Re-run the widget test to verify it passes**

Run: `cd apps/lyrica_app && flutter test test/presentation/song_library/song_list_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/lyrica_app/lib/src/presentation/song_library/song_list_screen.dart apps/lyrica_app/lib/src/app/lyrica_app.dart apps/lyrica_app/test/presentation/song_library/song_list_screen_test.dart
git commit -m "feat(song-library): add mock song list screen"
```

### Task 9: Build Reader Projection And Controls State

**Files:**
- Create: `apps/lyrica_app/lib/src/presentation/song_reader/song_reader_state.dart`
- Create: `apps/lyrica_app/lib/src/presentation/song_reader/song_reader_controller.dart`
- Create: `apps/lyrica_app/lib/src/presentation/song_reader/song_reader_projection.dart`
- Test: `apps/lyrica_app/test/presentation/song_reader/song_reader_controller_test.dart`
- Test: `apps/lyrica_app/test/presentation/song_reader/song_reader_projection_test.dart`

- [ ] **Step 1: Write the failing controller and projection tests**

Cover:
- default `chords + lyrics` mode
- toggling to `lyrics only`
- transpose up/down
- shared font scale changes
- transformed chord display without mutating the canonical parsed song

- [ ] **Step 2: Run the focused tests to verify they fail**

Run: `cd apps/lyrica_app && flutter test test/presentation/song_reader/song_reader_controller_test.dart test/presentation/song_reader/song_reader_projection_test.dart`
Expected: FAIL because the controller and projection types do not exist.

- [ ] **Step 3: Implement focused reader state and projection**

Keep:
- canonical parsed song immutable
- reader controls in local view state
- transposed chord display derived at projection time

- [ ] **Step 4: Re-run the focused tests to verify they pass**

Run: `cd apps/lyrica_app && flutter test test/presentation/song_reader/song_reader_controller_test.dart test/presentation/song_reader/song_reader_projection_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/lyrica_app/lib/src/presentation/song_reader apps/lyrica_app/test/presentation/song_reader/song_reader_controller_test.dart apps/lyrica_app/test/presentation/song_reader/song_reader_projection_test.dart
git commit -m "feat(song-reader): add reader state and projection"
```

### Task 10: Build And Test The Tablet-First Song Reader Screen

**Files:**
- Create: `apps/lyrica_app/lib/src/presentation/song_reader/song_reader_screen.dart`
- Create: `apps/lyrica_app/lib/src/presentation/song_reader/widgets/song_reader_header.dart`
- Create: `apps/lyrica_app/lib/src/presentation/song_reader/widgets/song_section_view.dart`
- Create: `apps/lyrica_app/lib/src/presentation/song_reader/widgets/song_line_view.dart`
- Test: `apps/lyrica_app/test/presentation/song_reader/song_reader_screen_test.dart`

- [ ] **Step 1: Write the failing reader widget tests**

Cover:
- metadata header
- visible section labels
- chords visible by default
- `lyrics only` mode hides chords
- transpose controls update rendered chords
- font scaling changes rendered text size
- non-blocking warning surface appears for recoverable diagnostics

- [ ] **Step 2: Run the widget test to verify it fails**

Run: `cd apps/lyrica_app && flutter test test/presentation/song_reader/song_reader_screen_test.dart`
Expected: FAIL because the reader screen does not exist.

- [ ] **Step 3: Implement the reader screen and focused widgets**

Use a vertically scrolling layout. Keep section rendering and line rendering separated so wrap behavior and future layout iterations stay local to smaller widgets.

- [ ] **Step 4: Re-run the widget test to verify it passes**

Run: `cd apps/lyrica_app && flutter test test/presentation/song_reader/song_reader_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/lyrica_app/lib/src/presentation/song_reader apps/lyrica_app/test/presentation/song_reader/song_reader_screen_test.dart
git commit -m "feat(song-reader): add tablet-first reader screen"
```

### Task 11: Add End-To-End Route Flow Coverage

**Files:**
- Modify: `apps/lyrica_app/test/app/lyrica_app_test.dart`
- Create: `apps/lyrica_app/test/integration/song_reader_flow_test.dart`

- [ ] **Step 1: Write the failing route-flow test**

Cover the vertical slice:
- app boots into song list
- song title tap opens reader
- reader shows parsed content from the selected mock asset

- [ ] **Step 2: Run the focused tests to verify they fail**

Run: `cd apps/lyrica_app && flutter test test/app/lyrica_app_test.dart test/integration/song_reader_flow_test.dart`
Expected: FAIL until the full flow is wired.

- [ ] **Step 3: Make any minimal integration fixes required**

Fix only the missing wiring or state issues exposed by the route-flow test. Do not use this task for unrelated refactors.

- [ ] **Step 4: Re-run the focused tests to verify they pass**

Run: `cd apps/lyrica_app && flutter test test/app/lyrica_app_test.dart test/integration/song_reader_flow_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/lyrica_app/test/app/lyrica_app_test.dart apps/lyrica_app/test/integration/song_reader_flow_test.dart
git commit -m "test(app): cover song list to reader flow"
```

### Task 12: Update Repository Documentation And Final Verification

**Files:**
- Modify: `README.md`
- Modify: `apps/lyrica_app/README.md`
- Modify: `docs/architecture/architecture.md`
- Modify: `docs/testing/testing-strategy.md`
- Modify: `docs/domain/domain-model.md`
- Modify: `docs/workflows/development-workflow.md`
- Modify: `docs/specs/2026-03-22-tablet-first-chordpro-song-reader.md`
- Modify: `docs/plans/2026-03-22-tablet-first-chordpro-song-reader.md`

- [ ] **Step 1: Update docs to reflect the new first product slice**

Document:
- song repository boundary
- asset-backed mock catalog in the current slice
- supported ChordPro subset
- parser diagnostics policy
- reader controls and current non-goals

- [ ] **Step 2: Run formatting, analysis, and tests**

Run: `./scripts/verify.sh --skip-migrations`
Expected:
- `dart format --set-exit-if-changed` passes
- `flutter analyze` passes
- `flutter test` passes

- [ ] **Step 3: Reconcile any documentation drift exposed by verification**

If tests or implementation differ from the spec or plan in meaningful ways, update the repository docs in the same change.

- [ ] **Step 4: Commit**

```bash
git add README.md apps/lyrica_app/README.md docs/architecture/architecture.md docs/testing/testing-strategy.md docs/domain/domain-model.md docs/workflows/development-workflow.md docs/specs/2026-03-22-tablet-first-chordpro-song-reader.md docs/plans/2026-03-22-tablet-first-chordpro-song-reader.md
git commit -m "docs(song-reader): align repository docs with first product slice"
```
