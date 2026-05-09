# Song Editing UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan step-by-step. Keep the ChordPro-first model canonical and update docs with any durable decision.

**Goal:** Implement the ChordPro-first song editing surface that matches the approved prototype: derived summary on the left, canonical source on the right, Source / Preview toggle inside the canonical block, and tablet tabs for `Overview`, `Source`, and `Preview`.

Status: Implemented

**Assumptions:** The repository already treats ChordPro source as canonical, with derived song fields refreshed from that source. No backend authorization changes are part of this slice. The mock in `docs/prototypes/song-editing-mockup.*` is the visual and interaction reference.

**Architecture:** Add a dedicated song editor presentation slice that reuses the existing song/domain parsing rules instead of inventing a second write model. The editor should parse ChordPro locally, show derived summary output, and keep capo / transpose adjustments inside the canonical source workflow. Keep reader runtime behavior separate from song-owned settings.

**Tech Stack:** Flutter, Riverpod, go_router, flutter_test, ChordPro parser already used by the reader slice, static HTML/CSS/JS prototype

---

### Task 1: Add the editor route and screen shell

**Files:**
- Modify: `apps/lyron_app/lib/src/router/app_routes.dart`
- Modify: `apps/lyron_app/lib/src/router/app_router.dart`
- Modify: `apps/lyron_app/lib/src/router/slug_route_resolvers.dart`
- Add: `apps/lyron_app/lib/src/presentation/song_editor/song_editor_screen.dart`
- Add: `apps/lyron_app/test/router/song_editor_route_test.dart`
- Add: `apps/lyron_app/test/presentation/song_editor/song_editor_screen_test.dart`

- [x] **Step 1: Write route tests for the new editor entry point**

Cover:

- direct navigation to a song editor route resolves to an editor screen
- missing song slug still falls back to the not-found scaffold
- auth redirects remain unchanged

Run:

```bash
flutter test apps/lyron_app/test/router/song_editor_route_test.dart
```

Expected: FAIL because the route and screen do not exist yet.

- [x] **Step 2: Add a song editor route and resolver**

Add a dedicated route for the editor using the same slug-resolution pattern as the reader.

Keep the route surface limited to the editor shell; do not reuse reader widgets directly.

- [x] **Step 3: Build the editor screen shell**

Add the first-pass screen structure:

- derived summary card
- canonical source card with Source / Preview toggle
- save / cancel actions
- state switcher surfaces for the mock states already documented in the spec

- [x] **Step 4: Re-run the route and screen tests**

Run:

```bash
flutter test apps/lyron_app/test/router/song_editor_route_test.dart apps/lyron_app/test/presentation/song_editor/song_editor_screen_test.dart
```

Expected: PASS once the route and shell are wired.

### Task 2: Implement ChordPro-first editing state and derived summary

**Files:**
- Add: `apps/lyron_app/lib/src/presentation/song_editor/song_editor_state.dart`
- Add: `apps/lyron_app/lib/src/presentation/song_editor/song_editor_controller.dart`
- Add: `apps/lyron_app/lib/src/presentation/song_editor/song_editor_projection.dart`
- Add: `apps/lyron_app/test/presentation/song_editor/song_editor_controller_test.dart`
- Add: `apps/lyron_app/test/presentation/song_editor/song_editor_projection_test.dart`
- Modify: `apps/lyron_app/lib/src/domain/song/parsed_song.dart` if the editor needs additional parsed fields already implied by the spec
- Modify: `apps/lyron_app/lib/src/infrastructure/song_library/chordpro/chordpro_parser.dart` only if the editor needs parser support that the reader slice does not already expose

- [x] **Step 1: Write failing tests for ChordPro-first editing behavior**

Cover:

- the editor loads from ChordPro source
- title / artist / key / tempo / tags are derived from source
- capo and transpose controls update the source directives, not separate title/metadata fields
- preview projection reflects the effective reader result

Run:

```bash
flutter test apps/lyron_app/test/presentation/song_editor/song_editor_controller_test.dart apps/lyron_app/test/presentation/song_editor/song_editor_projection_test.dart
```

Expected: FAIL until the editor controller and projection exist.

- [x] **Step 2: Add editor state and controller**

Model the editor around:

- canonical ChordPro source text
- derived summary fields
- song-level capo / transpose controls
- validation and parse warning state

Keep the user-facing write path limited to the source text and its source directives.

- [x] **Step 3: Add projection logic for the summary and preview views**

Projection should map the parsed song into:

- derived summary display
- source mode display
- preview mode display
- current capo / transpose control values

Avoid duplicating the reader runtime state machine in the editor.

- [x] **Step 4: Re-run the editor state tests**

Run:

```bash
flutter test apps/lyron_app/test/presentation/song_editor/song_editor_controller_test.dart apps/lyron_app/test/presentation/song_editor/song_editor_projection_test.dart
```

Expected: PASS.

### Task 3: Match the approved responsive UI behavior

**Files:**
- Add or modify: `apps/lyron_app/lib/src/presentation/song_editor/widgets/*.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_editor/song_editor_screen.dart`
- Add: `apps/lyron_app/test/presentation/song_editor/widgets/song_editor_*_test.dart`

- [x] **Step 1: Add tests for wide and tablet behavior**

Cover:

- wide layout shows only `Derived summary` and `Canonical source`
- canonical block toggles between Source and Preview
- tablet layout shows only one active tab at a time
- tablet defaults to `Source`

Run:

```bash
flutter test apps/lyron_app/test/presentation/song_editor/song_editor_screen_test.dart
```

Expected: FAIL until responsive shell behavior is implemented.

- [x] **Step 2: Build the responsive panels**

Implement the layout so it matches the prototype:

- wide: two-block workspace
- tablet: `Overview`, `Source`, `Preview` tabs
- no compact mode in this slice

- [x] **Step 3: Align preview styling with the reader**

Make the preview panel feel like the current song reader rather than a generic text preview.

Use the existing reader visuals as the reference point, not a fresh style system.

- [x] **Step 4: Re-run the responsive UI tests**

Run:

```bash
flutter test apps/lyron_app/test/presentation/song_editor/song_editor_screen_test.dart apps/lyron_app/test/presentation/song_editor/widgets
```

Expected: PASS.

### Task 4: Validate and document the slice

**Files:**
- Modify: `docs/specs/2026-05-02-song-editing-ui.md`
- Modify: `docs/domain/domain-model.md` only if implementation forces a durable semantic change
- Add or modify: any new editor docs required by the implementation

- [x] **Step 1: Verify the prototype and Flutter implementation against each other**

Check that the implemented editor still matches the prototype decisions:

- ChordPro-first source editing
- derived summary on the left
- canonical source with Source / Preview toggle
- tablet tabs only, no compact mode

- [x] **Step 2: Run the relevant test slice**

Use the smallest meaningful test set that covers the editor route, controller, projection, and screen behavior before merging.

- [x] **Step 3: Mirror any durable product decision into docs**

If implementation work changes any durable rule, update the repository docs in the same change instead of leaving the decision in chat.

### Risks & mitigations

- Risk: the editor accidentally reintroduces a second source of truth for title and metadata.
  - Mitigation: keep write paths centered on ChordPro source and regenerate derived values after save.
- Risk: the editor starts copying too much of the reader runtime state.
  - Mitigation: keep preview projection separate from reader runtime controls.
- Risk: route churn breaks existing song navigation.
  - Mitigation: add route tests before changing the router.

### Rollback plan

If the slice goes sideways, revert the editor route and editor presentation files first, then keep the prototype and docs as the stable reference point for a smaller follow-up slice.

### Task 5: Add unsaved change protection

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_editor/song_editor_screen.dart`
- Add: `apps/lyron_app/lib/src/presentation/song_editor/browser_unsaved_changes_guard.dart`
- Add: `apps/lyron_app/lib/src/presentation/song_editor/browser_unsaved_changes_guard_stub.dart`
- Add: `apps/lyron_app/lib/src/presentation/song_editor/browser_unsaved_changes_guard_web.dart`
- Modify: `apps/lyron_app/lib/src/shared/app_strings.dart`
- Modify: `apps/lyron_app/test/presentation/song_editor/song_editor_screen_test.dart`
- Modify: `apps/lyron_app/test/router/song_editor_route_test.dart` if route-level back/cancel coverage needs the router

- [x] **Step 1: Write failing tests for dirty leave behavior**

Cover:

- dirty back shows a discard confirmation before leaving
- dirty cancel shows a discard confirmation before leaving
- clean back/cancel still leave without confirmation
- save still persists and returns without discard confirmation

Run:

```bash
flutter test apps/lyron_app/test/presentation/song_editor/song_editor_screen_test.dart apps/lyron_app/test/router/song_editor_route_test.dart
```

Expected: FAIL until the guard is implemented.

- [x] **Step 2: Implement the dirty leave guard**

Use one confirmation path for Back, Cancel, and route pop/browser back.

Do not add a confirmation before Save.

- [x] **Step 3: Add Flutter Web reload/tab-close protection**

Use a conditional web hook so non-web builds keep using a no-op implementation.

- [x] **Step 4: Re-run verification**

Run the editor screen and route tests plus formatting.
