# Song Key Layers, PR 3 (Reader) Implementation Plan

> Status: Implemented on `feat/song-key-reader` (2026-10-21; PR #96).
> Was ready for execution on 2026-10-20. Covers PR 3 of
> `docs/specs/2026-10-13-personal-song-settings.md` only (PS1–PS9, PS22,
> PS24 PR 3 items, PS25–PS26; tests U1–U14). PR 1 (#94) and PR 2 (#95) are
> merged. The UI design gate was approved on 2026-10-20.

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** The reader resolves transpose and capo per field from an ordered
layer list (temporary over plan over song), shows each field's source, keeps
`±` temporary and bounded, offers Reset, Save to plan and Clear plan value
to the right members, clears the temporary layer on every song change, and
the plan detail shows each item's plan key.

**Architecture:** A pure domain resolver (`resolveSongKey`) and the PS9 step
rules sit in `lib/src/domain/song/song_key_layers.dart`. The reader builds the
layer list in one presentation class (`SongReaderKeyLayers`) from the
temporary layer in `SongReaderState` (owner-scoped), the live merged plan
item, and the song base. `SongReaderProjection` takes the resolved key. Save
and Clear go through PR 2's `PlanningWriteService.setSessionItemKey`.

**Tech Stack:** Flutter/Dart, Riverpod 3, the existing reader widgets and
planning providers; flutter_test goldens.

**Spec:** `docs/specs/2026-10-13-personal-song-settings.md` (PS1–PS9, PS22,
PS25, PS26). Also ADR-042, the 2026-04-01 spec's "Reader-Local State
Preservation" amendment, ADR-033 (reader chrome reads `ColorScheme`),
ADR-034 (chrome model).

## Global Constraints

- Branch: `feat/song-key-reader` (exists, from `main` `4cbdacb`). Never commit
  to `main`.
- No backend, migration, planning store, outbox or sync change. PR 2's API is
  used as is: `PlanningWriteService.setSessionItemKey({required
  PlanningWriteContext context, required SessionItemKeyDraft draft})`,
  `SessionItemKeyDraft(planId:, sessionId:, sessionItemId:, edit:)`,
  `SessionItemKeyEdit(transposeMode:, transpose:, capoMode:, capo:)` with
  `SessionItemKeyFieldMode.keep|set|clear`, and
  `SessionItemSummary.version/planTranspose/planCapo`. One additive change
  only: an optional `void Function()? onRecorded` on `setSessionItemKey`,
  called after the record and before `_scheduleSync` (Task 4), because the
  call otherwise returns only after a network sync attempt.
- Library-mode reader code paths must not watch planning or capability
  providers (`activePlanningContextProvider`, `planningPlanDetailProvider`,
  `readerCanEditSessionsProvider`): the library test harnesses do not
  override them. Watch them only when `_isScopedMode`.
- Bounds (PS9): transpose −11..+11, capo 0..11. One definition:
  `SongKeyRange` (Task 1); `SessionItemKeyEdit.minTranspose` etc. delegate to
  it.
- UI copy, English, verbatim: `Song`, `Plan`, `Temporary`, `Reset`,
  `Save to plan`, `Clear plan value`, `Transpose +2` / `Transpose -3` /
  `Transpose 0`, `Capo 2`. Signs as the reader's existing `_signed`: `+n`,
  `-n` (ASCII hyphen), `0`.
- New widget keys: `song-reader-transpose-source`, `song-reader-capo-source`
  (the source label `Text`, both layouts), `song-reader-key-reset`,
  `song-reader-key-save-to-plan` (both layouts),
  `plan-session-item-transpose-<itemId>`, `plan-session-item-capo-<itemId>`.
  Existing keys (`song-reader-transpose-down|value|up`,
  `song-reader-capo-down|value|up`) keep their names and roles.
- Source colors (PS25), from `Theme.of(context).colorScheme`, never literals:
  song → `surfaceContainerHighest`/`onSurface`, plan →
  `primaryContainer`/`onPrimaryContainer`, temporary →
  `tertiaryContainer`/`onTertiaryContainer`.
- No dialog, no snackbar anywhere in this PR (PS7, PS25).
- Existing tests must pass unmodified, except the ones that pin the removed
  offset API or the ended carry-over, which are rewritten in Task 2:
  `song_reader_state_test.dart`, `song_reader_controller_test.dart`,
  `session_scoped_reader_runtime_controller_test.dart`, the offset cases in
  `song_reader_projection_test.dart`, `song_editor_projection_test.dart:52-53`,
  and the screen test `scoped navigation preserves view mode, transpose, and
  shared font scale`. New constructor parameters are optional with defaults
  so no other test needs to change.
- Every task's verification: `cd apps/lyron_app && flutter analyze && flutter
  test` (the full suite, never a subdirectory).
- Code, comments, commits and docs in English. Subagent reports in caveman
  ultra (terse; identifiers, file:line and code exact).

## Review Focus

Inputs a naive implementation gets wrong; each has a pinning test below.

1. The frame between a previous/next tap, or a reopen of the same item, and
   the post-frame `startSession` must not render the old temporary transpose
   (owner + visit check; U6, Task 2).
2. After Save the field must read `Plan` as soon as the edit is recorded
   (not after the sync attempt), a `±` tap during the save must stay
   `Temporary`, and a temporary value equal to the plan value must leave the
   state so a later plan change cannot revive it (`onRecorded`, prune; U10,
   Task 4).
3. After Save, then next and back, the reader must show the saved plan value,
   although the route keeps passing the old warm plan detail (live read; U8,
   Task 3).
4. A song base outside the range (`{transpose: 14}`, `{capo: 13}`,
   `{capo: -2}`) must display as specified, enable only the step toward the
   range, and never enable Save while a temporary field is outside it (U3,
   Task 1; U11, Task 4).
5. An item that the live plan detail no longer contains (removed on another
   device) must give no plan layer, no Save and no Clear, even while the warm
   detail still lists it (U8, Task 3).

## STOP-and-report conditions

- Any fit, estimate or layout test changes (`song_reader_fit*`,
  `*_estimate_*`, `song_reader_chrome_*`, `song_reader_layout_test`).
- A test outside the list in Global Constraints needs a change.
- The plan value cannot be read from `planningPlanDetailProvider` without
  changing a planning provider or the merged read.
- Making a test pass seems to need a planning store, sync or backend change.
- The goldens generated locally fail on CI (Linux) beyond the 0.5% tolerance
  of Task 7. Do not raise the tolerance above 1%; report instead.
- `flutter analyze` reports a new warning you cannot fix locally.

## Test IDs

| ID | what | task |
|---|---|---|
| U1 | per-field resolution, first non-null wins, order honored | 1 |
| U2 | transient elision (PS5), stored layer equal to below keeps its source | 1 |
| U3 | PS9 step rules, in and out of range, capo floor | 1 |
| U4 | temporary layer owner check; step and prune results | 2, 4 |
| U5 | `startSession` clears the temporary layer, keeps the rest | 2 |
| U6 | session navigation reset (widget), no stale frame on next or reopen; library song change | 2 |
| U7 | editor preview renders the song base only | 2 |
| U8 | plan value from the live detail; warm fallback; missing item | 3 |
| U9 | source labels in compact and expanded | 3 |
| U10 | Save to plan: payload, `Plan` at record time, prune, `±` during save, in-flight guard | 4 |
| U11 | gating: library, read-only, unknown capability, out of range, first frame | 4 |
| U12 | Clear plan value: visibility (incl. unknown capability) and payload | 5 |
| U13 | plan detail key chips | 6 |
| U14 | goldens for both layouts | 7 |

## File Structure

- Create `apps/lyron_app/lib/src/domain/song/song_key_layers.dart`: field and
  layer ids, `SongKeyRange`, `SongKeyLayer`, `ResolvedSongKey`,
  `resolveSongKey`, `canStepSongKey`, `nextTransientValue`. Pure Dart.
- Modify `application/planning/session_item_key_edit.dart`: bounds delegate
  to `SongKeyRange`.
- Modify `presentation/song_reader/song_reader_state.dart`:
  `SongReaderTemporaryLayer`, `temporaryLayer` replaces the offsets.
- Create `presentation/song_reader/song_reader_key_layers.dart`:
  `SongReaderKeyLayers` (the one place the layer list is built).
- Modify `song_reader_controller.dart`,
  `session_scoped_reader_runtime_controller.dart`,
  `song_reader_commands.dart`: `setTemporaryLayer` replaces the four step
  methods; `startSession` clears the layer.
- Modify `song_reader_projection.dart`: optional `key`, resolved values.
- Modify `song_reader_screen.dart`, `widgets/song_reader_shell.dart`,
  `widgets/song_reader_compact_surface.dart`,
  `widgets/song_reader_expanded_surface.dart`,
  `widgets/song_reader_expanded_tools_panel.dart`,
  `widgets/song_reader_header.dart`, `widgets/song_reader_control_rail.dart`:
  layer wiring, nullable step callbacks, source labels, key actions.
- Create `presentation/song_reader/widgets/song_key_source_style.dart`: label
  and colors per `SongKeyLayerId`.
- Create `presentation/song_reader/song_reader_key_actions.dart`:
  `SongReaderKeyActions` (UI value), `planKeyEditFor`,
  `SongReaderPlanKeyWriter`.
- Modify `presentation/song_reader/session_scoped_reader_context_resolver.dart`:
  `findSessionItem` (the item lookup the reader's plan layer uses).
- Modify `presentation/song_reader/song_reader_providers.dart`:
  `readerCanEditSessionsProvider`.
- Modify `application/planning/planning_write_service.dart`: the optional
  `onRecorded` callback (Task 4).
- Modify `widgets/song_reader_overflow_menu.dart`, `song_reader_app_bar.dart`,
  `song_reader_top_bar.dart`: `clearPlanValue`.
- Modify `presentation/planning/widgets/plan_song_item_row.dart`: key chips.
- Modify `shared/app_strings.dart`: the copy above.
- Create `test/support/tolerant_golden_comparator.dart` and the golden test.
- Docs: `docs/testing/testing-strategy.md` (goldens), ADR-042 status, the
  2026-04-01 spec, this spec's status, the roadmap S3 row.

---

### Task 1: The domain resolver and the step rules

**Files:**
- Create: `apps/lyron_app/lib/src/domain/song/song_key_layers.dart`
- Modify: `apps/lyron_app/lib/src/application/planning/session_item_key_edit.dart`
- Test: `apps/lyron_app/test/domain/song/song_key_layers_test.dart`,
  `apps/lyron_app/test/application/planning/session_item_key_edit_test.dart`
  (add one case; create the file only if it does not exist)

**Interfaces:**
- Produces:
  - `enum SongKeyField { transpose, capo }`
  - `enum SongKeyLayerId { temporary, plan, song }` — PS22: a future layer is
    a new value here plus its label in `song_key_source_style.dart`.
  - `abstract final class SongKeyRange` with `static const minTranspose = -11,
    maxTranspose = 11, minCapo = 0, maxCapo = 11`, `static int min(SongKeyField)`,
    `static int max(SongKeyField)`, `static bool contains(SongKeyField, int)`.
  - `class SongKeyLayer { const SongKeyLayer({required SongKeyLayerId id,
    int? transpose, int? capo, bool isTransient = false}); int?
    valueOf(SongKeyField field); }`
  - `class ResolvedSongKeyField { const ResolvedSongKeyField({required int
    value, required SongKeyLayerId source}); }` with `==`/`hashCode`.
  - `class ResolvedSongKey { const ResolvedSongKey({required
    ResolvedSongKeyField transpose, required ResolvedSongKeyField capo});
    ResolvedSongKeyField field(SongKeyField f); bool
    hasSource(SongKeyLayerId id); }` with `==`/`hashCode`.
  - `ResolvedSongKey resolveSongKey(List<SongKeyLayer> layers)`
  - `bool canStepSongKey(SongKeyField field, int current, int delta)`
  - `int? nextTransientValue(List<SongKeyLayer> layers, {required
    SongKeyLayerId transientLayer, required SongKeyField field, required int
    delta})`

- [ ] **Step 1: Red tests (`song_key_layers_test.dart`)**

  Helpers: `temp({int? t, int? c}) => SongKeyLayer(id: temporary,
  transpose: t, capo: c, isTransient: true)`, `plan({int? t, int? c})`,
  `song({int t = 0, int c = 0})`.

  - **U1** `resolves each field independently, first non-null wins`:
    `[temp(t: 3), plan(c: 2), song(t: 1, c: 0)]` →
    `transpose == (3, temporary)`, `capo == (2, plan)`.
    `[temp(), plan(), song(t: 1, c: 4)]` → `(1, song)`, `(4, song)`.
    `[plan(t: 2), song()]` (no temporary layer) → `(2, plan)`, `(0, song)`.
    `[temp(t: 5), song()]` (library, no plan layer) → `(5, temporary)`.
  - **U1** `throws when the last layer does not give both fields`:
    `resolveSongKey([])`, `resolveSongKey([plan(t: 1)])` →
    `throwsArgumentError`.
  - **U2** `a transient value equal to the layers below does not claim the
    field`: `[temp(t: 2), plan(t: 2), song()]` → transpose `(2, plan)`;
    `[temp(c: 0), plan(), song(c: 0)]` → capo `(0, song)`;
    `hasSource(temporary)` false in both.
  - **U2** `a stored layer equal to the song base keeps its source`:
    `[temp(), plan(t: 0), song(t: 0)]` → transpose `(0, plan)`.
  - **U3** `canStepSongKey` table — `(field, current, delta) → expected`:
    `(transpose, 0, +1) true`, `(transpose, 11, +1) false`,
    `(transpose, -11, -1) false`, `(transpose, 14, +1) false`,
    `(transpose, 14, -1) true`, `(transpose, -13, -1) false`,
    `(transpose, -13, +1) true`, `(capo, 0, -1) false`, `(capo, 0, +1) true`,
    `(capo, 11, +1) false`, `(capo, 13, -1) true`, `(capo, 13, +1) false`.
    Any `delta` other than `1`/`-1` → `throwsArgumentError`.
  - **U3** `nextTransientValue`:
    - `[temp(), song(t: 0)]`, transpose `+1` → `1`.
    - `[temp(t: 1), song(t: 0)]`, transpose `-1` → `null` (back to the
      value below).
    - `[temp(), plan(t: 2), song()]`, transpose `-1` → `1`.
    - `[temp(t: 3), plan(t: 2), song()]`, transpose `-1` → `null`.
    - `[temp(), song(t: 14)]`, transpose `-1` → `13`.
    - a step `canStepSongKey` refuses → `throwsStateError`; a list without
      the named transient layer → `throwsArgumentError`.

- [ ] **Step 2: Run** `cd apps/lyron_app && flutter test
  test/domain/song/song_key_layers_test.dart` — fails to compile (red).

- [ ] **Step 3: Implement `song_key_layers.dart`**

  `resolveSongKey` walks the list top-down per field; a layer gives a value
  when `valueOf(field) != null` and, if `isTransient`, that value differs
  from `resolveSongKey(layers.sublist(i + 1))` for that field (resolve the
  rest once per field, not per layer pair). `canStepSongKey`: `delta == 1 ?
  current < SongKeyRange.max(field) : current > SongKeyRange.min(field)`.
  `nextTransientValue`: current = resolved value of the whole list; target =
  current + delta; below = resolved value of the sublist after the transient
  layer; return `target == below ? null : target`. Doc comments cite PS1,
  PS5, PS9, PS22.

- [ ] **Step 4: `SessionItemKeyEdit` bounds delegate**

  In `session_item_key_edit.dart`: `static const minTranspose =
  SongKeyRange.minTranspose;` (and the other three). Add one test: the four
  constants equal `SongKeyRange`'s. No behavior change; PR 2's key-edit
  tests stay green unmodified.

- [ ] **Step 5: Run the full suite** (Global Constraints). Expected: green.

- [ ] **Step 6: Commit** `feat(reader): song key layer resolver and step
  rules (S3 PR 3)`

---

### Task 2: Temporary layer state, projection, and the end of the carry-over

**Files:**
- Modify: `lib/src/presentation/song_reader/song_reader_state.dart`,
  `song_reader_controller.dart`,
  `session_scoped_reader_runtime_controller.dart`,
  `song_reader_commands.dart`, `song_reader_projection.dart`,
  `song_reader_screen.dart`, `widgets/song_reader_shell.dart`,
  `widgets/song_reader_compact_surface.dart`,
  `widgets/song_reader_expanded_surface.dart`,
  `widgets/song_reader_expanded_tools_panel.dart`,
  `widgets/song_reader_header.dart`, `widgets/song_reader_control_rail.dart`
- Create: `lib/src/presentation/song_reader/song_reader_key_layers.dart`
- Test: `test/presentation/song_reader/song_reader_state_test.dart`,
  `song_reader_controller_test.dart`,
  `session_scoped_reader_runtime_controller_test.dart`,
  `song_reader_key_layers_test.dart` (new), `song_reader_projection_test.dart`,
  `song_reader_screen_test.dart`,
  `test/presentation/song_editor/song_editor_projection_test.dart`

**Interfaces:**
- Consumes: Task 1.
- Produces:
  - `class SongReaderTemporaryLayer { const SongReaderTemporaryLayer({required
    String ownerId, int? transpose, int? capo}); int? valueOf(SongKeyField);
    SongReaderTemporaryLayer? withValue(SongKeyField field, int? value); }`
    — `withValue` returns `null` when both fields end up null; `==`/`hashCode`.
    Lives in `song_reader_state.dart`.
  - `SongReaderState.temporaryLayer` (`SongReaderTemporaryLayer?`, default
    null); `SongReaderTemporaryLayer? temporaryLayerFor(String ownerId)`
    (the layer only when its `ownerId` matches); `SongReaderState
    withTemporaryLayer(SongReaderTemporaryLayer? layer)`. `copyWith` keeps
    the layer. `transposeOffset`/`capoOffset` are removed.
  - `SongReaderController.setTemporaryLayer(SongReaderTemporaryLayer?)` and
    `SessionScopedReaderRuntimeController.setTemporaryLayer(...)` replace
    `transposeUp/Down`, `capoUp/Down`. `SongReaderCommands.setTemporaryLayer(
    SongReaderTemporaryLayer? layer, {required WidgetRef ref, required bool
    isScopedMode, required String sessionKey})` replaces its four step
    methods.
  - `class SongReaderKeyLayers { const SongReaderKeyLayers({
    SongReaderTemporaryLayer? temporary, bool isPlanScoped = false, int?
    planTranspose, int? planCapo}); static const baseOnly =
    SongReaderKeyLayers(); List<SongKeyLayer> layersFor(ParsedSong song);
    ResolvedSongKey resolveFor(ParsedSong song); bool canStep(ParsedSong
    song, SongKeyField field, int delta); SongReaderTemporaryLayer?
    temporaryAfterStep(ParsedSong song, SongKeyField field, int delta,
    {required String ownerId}); SongReaderTemporaryLayer?
    prunedTemporary(ParsedSong song); }` — `temporary` is already
    owner-matched by the caller. `prunedTemporary` returns `temporary` with
    every field removed whose resolved source is not `temporary` (the PS5
    elision made permanent), `null` when nothing is left; Task 4 wires it.
  - `SongReaderProjection({required ParsedSong song, required SongReaderState
    state, ResolvedSongKey? key, SongChordTransposer transposeChord})` —
    `key == null` means `SongReaderKeyLayers.baseOnly.resolveFor(song)`. New
    field `final ResolvedSongKey key`; `effectiveTranspose` and
    `effectiveCapo` come from it; `transposeOffset`, `capoOffset` and the
    static `effectiveCapoValue` are removed.
  - Step callbacks become nullable (`VoidCallback?`, null = disabled) on
    `SongReaderBodyShell`, both surfaces, the tools panel, the header and
    the rail: `onTransposeDown`, `onTransposeUp`, `onCapoDown`, `onCapoUp`.
  - `SongReaderBodyShell` gains `SongReaderKeyLayers keyLayers =
    SongReaderKeyLayers.baseOnly` and builds its projection with
    `key: keyLayers.resolveFor(result.song)`. Its own `effectiveCapo > 0 ?
    onCapoDown : null` rule is removed (the screen decides, PS9).

- [ ] **Step 1: Red unit tests**
  - `song_reader_state_test.dart` (rewrite the offset cases): default
    `temporaryLayer == null`; `withTemporaryLayer` sets and clears; `copyWith`
    of an unrelated field keeps the layer; equality includes it.
  - **U4** `temporaryLayerFor returns null for another owner`:
    `SongReaderState().withTemporaryLayer(SongReaderTemporaryLayer(ownerId:
    'item-1', transpose: 2))` → `temporaryLayerFor('item-1')?.transpose == 2`,
    `temporaryLayerFor('item-2') == null`.
  - **U4** `song_reader_key_layers_test.dart`:
    - `layersFor` order is `[temporary (transient), plan, song]` inside a
      plan and `[temporary, song]` outside; the temporary layer is present
      with null values when `temporary` is null.
    - The song layer floors capo at 0: base `{capo: -2}` →
      `resolveFor(song).capo == (0, song)`; base `{capo: 13}` → `(13, song)`;
      base `{transpose: 14}` → `(14, song)`.
    - `temporaryAfterStep(song(base t 0), transpose, +1, ownerId: 'x')` →
      `SongReaderTemporaryLayer(ownerId: 'x', transpose: 1)`; from that,
      `-1` → `null`; with `temporary: (capo: 3)` a transpose step keeps capo
      3.
    - `prunedTemporary`: temporary `(t 3)` over plan `t 3` → `null`;
      `(t 3, c 1)` over plan `t 3`, song `c 0` → `(t: null, c 1)`; `(t 4)`
      over plan `t 3` → unchanged (`identical` not required, `==` is).
  - **U5** `session_scoped_reader_runtime_controller_test.dart`: in one
    session set view mode lyrics-only, piano, font scale 1.4, controls
    visible, auto-fit off and a temporary layer; `startSession` for another
    song in the SAME session → `temporaryLayer == null`, every other field
    unchanged. `startSession` for the same song again (re-entry) → layer
    null. A different session → a fresh `SongReaderState()` (unchanged
    behavior).
  - `song_reader_controller_test.dart`: replace the transpose/capo cases with
    `setTemporaryLayer` set and clear.
  - `song_reader_projection_test.dart`: replace the offset cases. A song with
    base transpose 1, chord `C`, and `key: ResolvedSongKey(transpose: (3,
    temporary), capo: (2, plan))` renders `D#` → with guitar capo 2 the
    displayed chord is `C#`; `effectiveKey` and `capoDirectiveText`
    (`Capo 2`) follow the key; with `key` omitted the projection equals the
    base-only resolution.
  - **U7** `song_editor_projection_test.dart` (replace lines 52–53): for a
    source with `{transpose: 1}` and `{capo: 2}`,
    `projection.preview.key == ResolvedSongKey(transpose: (1, song), capo:
    (2, song))`; for `{capo: -2}`, `capo == (0, song)`. No production change
    is needed in `song_editor_projection.dart` (it passes no key); the test
    pins that the preview never shows a temporary or plan layer.

- [ ] **Step 2: Run** these files; red (compile errors).

- [ ] **Step 3: Implement state, controllers, commands, key layers,
  projection.** `startSession` always builds the new state with
  `readerState: (isSameSession ? _state.readerState : SongReaderState())
  .withTemporaryLayer(null)`.

- [ ] **Step 4: Wire the screen and the widgets**
  - Screen: a reader visit id, `static int _nextReaderVisit = 0;` and `late
    final int _readerVisit = _nextReaderVisit++;` (assigned once per `State`,
    so a reopened reader is a new visit while previous/next inside one
    screen keeps it); `String get _keyOwnerId =>
    '${_isScopedMode ? widget.sessionItemId! : widget.songId}@$_readerVisit';`.
    Build `SongReaderKeyLayers(temporary:
    readerState.temporaryLayerFor(_keyOwnerId), isPlanScoped: _isScopedMode)`
    (plan values arrive in Task 3), pass `key:` to the screen's own
    projection and `keyLayers:` to the shell.
  - Step callbacks: for each `(field, delta)`, `null` when the song is not
    loaded or `!keyLayers.canStep(song, field, delta)`; otherwise
    `() => _commands.setTemporaryLayer(keyLayers.temporaryAfterStep(song,
    field, delta, ownerId: _keyOwnerId), ...)`.
  - Rail, header, panel, surfaces: accept the nullable callbacks; a null
    callback is a disabled button (the rail and header already render
    `onPressed: null` that way).
  - Remove the four step methods from `song_reader_screen.dart` that call
    the removed command methods.
  - `didUpdateWidget`: when `songId` changes outside a plan, clear the local
    controller's temporary layer (PS5 "any route to another song"; the owner
    check already hides it, this keeps a return to the first song from
    reviving it).

- [ ] **Step 5: Red widget tests (`song_reader_screen_test.dart`)**
  - **U6** Rewrite `scoped navigation preserves view mode, transpose, and
    shared font scale` as `scoped navigation preserves view mode and font
    scale and clears the temporary key`: in chords mode (do not switch to
    lyrics-only for this assertion), tap transpose-up on song one, tap `A+`,
    go next; assert song two renders its base chords and
    `song-reader-transpose-value` shows its base, while the font size is
    preserved. In a second test, switch to lyrics-only before navigating and
    assert the view mode is preserved.
  - **U6** `the first frame after previous/next shows no stale temporary
    key`: transpose-up on song one, tap next, then `await tester.pump()` one
    frame at a time (at most 10, no `pumpAndSettle`) until song two's title
    and `song-reader-transpose-value` are both on screen; assert that very
    first frame already shows song two's base value.
  - **U6** `reopening the same plan item shows no old temporary key`: open
    item one from the plan detail, tap transpose-up, go back to the plan
    detail, open item one again; pump frame by frame as above and assert the
    first frame with the value chip shows the base (the runtime controller
    family is not auto-disposed, so only the visit id protects this frame).
  - **U6** `a library reader reused for another song drops the temporary
    key`: pump `SongReaderScreen(songId: 'song-1')`, tap transpose-up,
    re-pump the same tree with `songId: 'song-2'` (same `State`), assert
    song two's base value.
  - **U3/PS9** `out-of-range song base enables only the step toward the
    range`: base `{transpose: 14}` → transpose-up `onPressed == null`,
    transpose-down enabled; after one down the value shows `+13`.
  - Run: red before Step 4 if written first; green after.

- [ ] **Step 6: Run the full suite.** Expected: green; fit and estimate
  tests unchanged (STOP otherwise).

- [ ] **Step 7: Commit** `feat(reader): temporary key layer replaces the
  session carry-over (S3 PR 3)`

---

### Task 3: The plan layer and the source labels

**Files:**
- Modify: `lib/src/presentation/song_reader/session_scoped_reader_context_resolver.dart`,
  `song_reader_screen.dart`, `widgets/song_reader_control_rail.dart`,
  `widgets/song_reader_header.dart`, `lib/src/shared/app_strings.dart`
- Create: `lib/src/presentation/song_reader/widgets/song_key_source_style.dart`
- Test: `test/presentation/song_reader/song_reader_screen_test.dart`,
  `widgets/song_reader_control_rail_test.dart`,
  `widgets/song_reader_expanded_tools_panel_test.dart`,
  `session_scoped_reader_context_resolver_test.dart`

**Interfaces:**
- Consumes: Tasks 1–2.
- Produces:
  - `SessionItemSummary? findSessionItem(PlanDetail detail, {required String
    sessionId, required String sessionItemId})` in
    `session_scoped_reader_context_resolver.dart`. No derived provider: the
    screen watches `planningPlanDetailProvider(planId)` itself, so the plan
    layer changes in the same frame as the detail (a derived async provider
    lags one hop, PS26).
  - `String songKeySourceLabel(SongKeyLayerId id)` and
    `({Color background, Color foreground}) songKeySourceColors(ColorScheme
    scheme, SongKeyLayerId id)` — exhaustive switches, values from Global
    Constraints.
  - `AppStrings.songReaderKeySourceSong = 'Song'`,
    `songReaderKeySourcePlan = 'Plan'`,
    `songReaderKeySourceTemporary = 'Temporary'`.

- [ ] **Step 1: Red tests**
  - `session_scoped_reader_context_resolver_test.dart`: `findSessionItem`
    returns the item (with its `planTranspose`/`planCapo`), `null` for an
    unknown item id, and `null` for an item id that exists in another
    session.
  - U8 and U9 screen tests run in the expanded layout (1600×1200) unless they
    say otherwise: the expanded value chips read `+2` and `3` (the compact
    rail's capo chip reads `Capo 3`).
  - **U8** `the reader shows the plan value from the live plan detail`: the
    scoped harness (`buildScopedReaderApp`; let it take the live detail
    separately from the warm one) with a warm detail whose item has no key
    and a live `planningPlanDetailProvider` whose item has `planTranspose: 2,
    planCapo: 3` → transpose value `+2`, capo `3`, both sources `Plan`.
  - **U8** `next song shows its own plan value`: items one (`planTranspose:
    2`) and two (`planTranspose: -1`); open one, go next → `-1`, `Plan`.
  - **U8** `an item missing from the live detail has no plan layer`: warm
    detail item has `planTranspose: 2`, live detail lacks the item (the
    scoped context still resolves from the warm detail) → value equals the
    song base, source `Song`.
  - **U8** `while the live detail loads, the warm item applies`: live
    provider overridden with a never-completing future; warm item
    `planTranspose: 2` → `+2`, `Plan`.
  - **U9** compact (phone viewport) and expanded (1600×1200), library entry:
    `song-reader-transpose-source` and `song-reader-capo-source` read `Song`;
    after transpose-up the transpose source reads `Temporary` and the capo
    source still `Song`; after transpose-down back to base it reads `Song`
    again (PS5).
  - Rail test: the source caption sits below the value chip (center y
    greater); the rail's size is the same for sources `Song` and
    `Temporary` (`tester.getSize` of `song-reader-control-rail-surface`
    equal).
  - Tools panel test: the badge is in the same row as the section label
    (equal center y, greater x).

- [ ] **Step 2: Run them**; red.

- [ ] **Step 3: Implement**
  - Screen (scoped only): `final detailAsync =
    ref.watch(planningPlanDetailProvider(widget.planId!));` `planItem =
    detailAsync.hasValue ? findSessionItem(detailAsync.requireValue, ...) :
    warmItem`, where `warmItem` is the same lookup in `widget.warmPlanDetail`
    (Riverpod 3 keeps the previous value while the provider reloads, so a
    refresh never falls back to the warm item). Pass `planTranspose:
    planItem?.planTranspose, planCapo: planItem?.planCapo` to
    `SongReaderKeyLayers`.
  - Rail: the `_ValueChip` takes the source colors; a caption `Text` (key
    above, `labelSmall`, `onSurfaceVariant`: the `on…Container` colors are
    made for the chip, not the rail background) in a `SizedBox(width: 56)`
    with `FittedBox(fit: BoxFit.scaleDown)`, one line. The capo caption hides
    with the capo group (piano).
  - Header: `_ControlSection` gains an optional trailing badge (rounded
    `DecoratedBox`, source colors, `labelSmall`) at the end of the label row;
    the value chip takes the source colors.

- [ ] **Step 4: Run the full suite.** Green.

- [ ] **Step 5: Commit** `feat(reader): plan key layer and source labels (S3
  PR 3)`

---

### Task 4: Reset, Save to plan, pruning and the capability gate

**Files:**
- Create: `lib/src/presentation/song_reader/song_reader_key_actions.dart`
- Modify: `lib/src/application/planning/planning_write_service.dart`
  (`onRecorded`), `song_reader_providers.dart`, `song_reader_screen.dart`,
  `widgets/song_reader_shell.dart`, both surfaces,
  `widgets/song_reader_expanded_tools_panel.dart`,
  `widgets/song_reader_header.dart`, `widgets/song_reader_control_rail.dart`,
  `lib/src/shared/app_strings.dart`
- Test: `test/presentation/song_reader/song_reader_key_actions_test.dart`
  (new), the existing `PlanningWriteService` key-edit test file (one case),
  `song_reader_screen_test.dart`, the rail and tools panel tests

**Interfaces:**
- Consumes: Tasks 1–3 (incl. `SongReaderKeyLayers.prunedTemporary`); PR 2's
  write API (Global Constraints); `activePlanningContextProvider`,
  `planningWriteServiceProvider`, `planningMutationEntriesProvider`,
  `planningPlanDetailProvider`, `capabilityResolverProvider`,
  `Capability.editSessions`.
- Produces:
  - `PlanningWriteService.setSessionItemKey({required PlanningWriteContext
    context, required SessionItemKeyDraft draft, void Function()?
    onRecorded})` — `onRecorded` runs right after
    `recordSessionItemKeyEdit` returns and before `_scheduleSync`; nothing
    else changes.
  - `class SongReaderKeyActions { const SongReaderKeyActions({required bool
    isSaveToPlanAvailable, VoidCallback? onReset, VoidCallback?
    onSaveToPlan}); static const none = SongReaderKeyActions(
    isSaveToPlanAvailable: false); }` — a null callback is a disabled
    button; `isSaveToPlanAvailable` decides whether the Save button exists.
  - `SessionItemKeyEdit? planKeyEditFor(ResolvedSongKey key)` — `null` when no
    field has source `temporary` or a temporary field is outside
    `SongKeyRange`; otherwise `set` with the value for each temporary field,
    `keep` for the other. The instrument view does not matter (PS26).
  - `class SongReaderPlanKeyWriter { const SongReaderPlanKeyWriter();
    Future<bool> saveToPlan(ProviderContainer container, {required String
    planId, required String sessionId, required String sessionItemId,
    required SessionItemKeyEdit edit}); Future<bool>
    clearPlanValue(ProviderContainer container, {required String planId,
    required String sessionId, required String sessionItemId}); }` — the
    caller captures the container with `ProviderScope.containerOf(context,
    listen: false)` before calling (the `plan_detail_screen.dart` delete
    pattern), so a reader closed during the write still refreshes. Both
    return `false` without writing when `activePlanningContextProvider` is
    null; otherwise call `setSessionItemKey` with `onRecorded: () {
    container.invalidate(planningPlanDetailProvider(planId));
    container.invalidate(planningMutationEntriesProvider); }` and return
    `true` when it completes. A throw propagates. `clearPlanValue` sends
    `clear`/`clear`.
  - `final readerCanEditSessionsProvider =
    FutureProvider.autoDispose.family<bool, String>` (organization id) —
    `await ref.watch(capabilityResolverProvider).hasCapability(orgId,
    Capability.editSessions)`, any error → `false`;
    `retry: noAutomaticProviderRetry`. Only the fallback for an uncached
    result (Step 3).
  - `SongReaderKeyActions keyActions = SongReaderKeyActions.none` on the
    shell, both surfaces, the tools panel, the header and the rail.
  - `AppStrings.songReaderResetKeyAction = 'Reset'`,
    `songReaderSaveToPlanAction = 'Save to plan'`.

- [ ] **Step 1: Red unit tests**
  - `PlanningWriteService`: `setSessionItemKey(onRecorded: ...)` calls it
    once, after the mutation store holds the row and before the injected
    `syncScheduler` runs (record the call order); without `onRecorded` the
    existing behavior is unchanged.
  - `planKeyEditFor` (`song_reader_key_actions_test.dart`): `(transpose: (3,
    temporary), capo: (2, plan))` → `set 3 / keep`; `(transpose: (0, plan),
    capo: (4, temporary))` → `keep / set 4`; both temporary → `set / set`;
    none temporary → `null`; `(transpose: (13, temporary), capo: (0, song))`
    → `null`.
  - `SongReaderPlanKeyWriter` with a `ProviderContainer` overriding
    `activePlanningContextProvider` and `planningWriteServiceProvider` (a real
    `PlanningWriteService` over fakes, the pattern of
    `plan_song_item_row_test.dart`): `saveToPlan` records the draft ids and
    the edit unchanged and returns `true`; `planningPlanDetailProvider(planId)`
    is invalidated before the scheduler completes (a scheduler that never
    completes still sees the invalidation); with no active context it returns
    `false` and records nothing; `clearPlanValue` records `clear`/`clear`.

- [ ] **Step 2: Red widget tests**
  - Rail: with `SongReaderKeyActions.none` the Reset button exists and is
    disabled, no Save button; with `isSaveToPlanAvailable: true` both exist,
    Reset above Save, both between the capo group and the font group;
    enabling the callbacks does not change the rail size. In an 800×360
    viewport (landscape phone) Reset and Save are reachable with
    `tester.ensureVisible` inside the rail's scroll view and tappable.
  - Tools panel: the button row is under the capo section and above Scale;
    same existence and enablement rules.
  - Screen setup for U10/U11 (scoped, expanded): override
    `activePlanningContextProvider` with a context,
    `readerCanEditSessionsProvider` with `true`, `planningWriteServiceProvider`
    with a real service over fakes whose record also updates the overridden
    live plan detail, and whose `syncScheduler` is a `Completer` the test
    completes.
  - **U10** `Save shows Plan once recorded`: item `planTranspose: 2`; tap
    transpose-up (→ `+3`, `Temporary`), tap Save → one recorded edit
    `set 3 / keep` for that item; with the scheduler NOT completed, after
    `pumpAndSettle` the transpose source reads `Plan`, value `+3`, Reset
    disabled, Save disabled; the runtime controller's `temporaryLayer` is
    `null` (pruned, not only hidden).
  - **U10** `no frame shows the old plan value after Save`: same setup; pump
    frame by frame from the Save tap until the source reads `Plan`; no frame
    shows `+2`.
  - **U10** `a ± tap during the save stays temporary`: tap Save, then
    transpose-up before the record completes (the fake record awaits a
    `Completer`) → after completion the value is `+4`, source `Temporary`.
  - **U10** `a temporary value equal to a synced plan value is pruned`: tap
    transpose-up to `+3`; replace the live detail with `planTranspose: 3`
    (as a sync would) → source `Plan`, `temporaryLayer == null`; then change
    the live detail to `planTranspose: 5` → `+5`, `Plan` (the old `+3` does
    not return).
  - **U10** `Save and Clear are disabled while a write is in flight`: tap Save
    with the record blocked → Save is disabled (and stays so after another
    `±`) until the call completes; only one edit is recorded for a double
    tap.
  - **U10** `piano view saves the hidden temporary capo`: guitar view, capo-up
    (temporary), switch to piano, transpose-up, Save → recorded edit
    `set / set`.
  - **U10** Reset after a transpose and a capo tap returns both fields to the
    layer below and disables Reset.
  - **U11** gating, each asserting no `song-reader-key-save-to-plan` and an
    existing Reset: library entry; scoped with `readerCanEditSessionsProvider`
    `false`; scoped with the capability future never completing and no cached
    result; scoped with no active planning context.
  - **U11** `Save is present on the first frame when the capability is
    cached`: a fake `CapabilityResolver` whose `hasCapabilitySync` returns
    `true` and whose `hasCapability` never completes → the first frame with
    the rail already has the Save button.
  - **U11** out of range: song base `{transpose: 14}`, member can edit;
    transpose-down once → `+13`, `Temporary`, Save disabled, Reset enabled.

- [ ] **Step 3: Implement**
  - `planning_write_service.dart`: the `onRecorded` parameter.
  - Screen, scoped only (Global Constraints): `orgId =
    ref.watch(activePlanningContextProvider)?.organizationId`;
    `canEditSessions = orgId != null && (cachedSync ??
    ref.watch(readerCanEditSessionsProvider(orgId)).value ?? false)` where
    `cachedSync` is `ref.watch(capabilityResolverProvider)
    .hasCapabilitySync(orgId, Capability.editSessions)` inside the same
    `try`/`catch` the screen already uses for `editSongs` (a throw means
    `null`). `canWritePlanKey = planItem != null && canEditSessions`.
  - `bool _isPlanKeyWriteInFlight` on the screen state: set before the writer
    call, cleared in `finally` (if `mounted`, with `setState`). While it is
    true, `onSaveToPlan` and the Clear action (Task 5) are disabled, and the
    handlers also return early on it (a second tap before the rebuild).
  - `onReset` when `key.hasSource(SongKeyLayerId.temporary)` →
    `setTemporaryLayer(null)`. `onSaveToPlan` when `canWritePlanKey`, not in
    flight, and `planKeyEditFor(key)` is non-null → capture the container,
    call `saveToPlan`. No explicit clear after it: pruning does it.
  - Pruning: in `build`, scoped only, `ref.listen` on
    `planningPlanDetailProvider(widget.planId!)` and on
    `songLibraryReaderProvider(widget.songId)`; the callback (outside build)
    reads the current runtime `readerState`, the loaded song and the current
    plan item, computes `SongReaderKeyLayers(...).prunedTemporary(song)`, and
    calls `setTemporaryLayer` only when the result differs from the current
    owner-matched layer. Library mode listens only to the song provider.
  - Rail: the new group (`_Divider` before it) holds Reset
    (`Icons.restart_alt`) and, when available, Save
    (`Icons.playlist_add_check`), each an `IconButton` with the copy as
    tooltip.
  - Header: a `Wrap` row: `TextButton` Reset, `FilledButton.tonal` Save to
    plan when available.

- [ ] **Step 4: Run the full suite.** Green; the library-mode screen tests
  pass unmodified (STOP if one needs a planning or capability override).

- [ ] **Step 5: Commit** `feat(reader): reset and save the key to the plan
  (S3 PR 3)`

---

### Task 5: Clear plan value

**Files:**
- Modify: `widgets/song_reader_overflow_menu.dart`,
  `widgets/song_reader_app_bar.dart`, `widgets/song_reader_top_bar.dart`,
  `song_reader_screen.dart`, `lib/src/shared/app_strings.dart`
- Test: `widgets/song_reader_overflow_menu_test.dart`,
  `song_reader_screen_test.dart`

**Interfaces:**
- Consumes: Task 4 (`SongReaderPlanKeyWriter.clearPlanValue`,
  `canWritePlanKey`).
- Produces: `SongReaderOverflowAction.clearPlanValue`; `bool
  canClearPlanValue = false` on `SongReaderOverflowMenu`, `SongReaderAppBar`
  and `SongReaderTopBar` (passed through); `AppStrings
  .songReaderClearPlanValueAction = 'Clear plan value'`.

- [ ] **Step 1: Red tests**
  - Menu: with `canClearPlanValue: true` the item `Clear plan value` appears
    after `Piano View` and before the theme item, with a divider on each
    side; with `false` (default) it is absent and the existing item order is
    unchanged.
  - **U12** screen, scoped, member who can edit, item `planTranspose: 2`:
    the item is in the overflow menu in the compact AND the expanded layout;
    tapping it records `clear`/`clear` for the item; after the detail
    refresh (fake clears the values) the source reads `Song`. Item with no
    plan value → item absent. Read-only member, library, no active planning
    context, and a capability that is uncached with a never-completing
    future → absent. While a Save or Clear of this reader is in flight →
    absent.

- [ ] **Step 2: Run**; red.

- [ ] **Step 3: Implement.** Screen: `canClearPlanValue = canWritePlanKey &&
  !_isPlanKeyWriteInFlight && (planItem!.planTranspose != null ||
  planItem.planCapo != null)`; the action captures the container and calls
  `clearPlanValue` under the same in-flight flag as Save (unawaited from the
  menu handler, like the existing actions).

- [ ] **Step 4: Run the full suite.** Green.

- [ ] **Step 5: Commit** `feat(reader): clear the plan key from the reader
  menu (S3 PR 3)`

---

### Task 6: Plan detail key chips (PS8)

**Files:**
- Modify: `lib/src/presentation/planning/widgets/plan_song_item_row.dart`,
  `lib/src/shared/app_strings.dart`
- Test: `test/presentation/planning/widgets/plan_song_item_row_test.dart`

**Interfaces:**
- Produces: `static String AppStrings.planItemTransposeLabel(int value)`
  (`Transpose +2`, `Transpose -3`, `Transpose 0`) and `static String
  AppStrings.planItemCapoLabel(int value)` (`Capo 2`).

- [ ] **Step 1: Red tests (U13)**
  - Item `planTranspose: 2, planCapo: 3` → `plan-session-item-transpose-item-1`
    with text `Transpose +2` and `plan-session-item-capo-item-1` with
    `Capo 3`, both below the title (greater center y).
  - `planTranspose: -3` only → `Transpose -3`, no capo chip.
  - `planCapo: 0` only → `Capo 0`, no transpose chip.
  - No plan values → neither key found; the row's title widget and its tap
    target are unchanged (existing tests stay green).

- [ ] **Step 2: Run**; red.

- [ ] **Step 3: Implement.** The title becomes a `Column` (start-aligned):
  the existing title `Text`, then, only when a value exists, a `Wrap`
  (spacing 6, run spacing 4) of small chips (rounded `DecoratedBox`,
  `primaryContainer`/`onPrimaryContainer`, `labelSmall`). The chevron stays
  centered on the row.

- [ ] **Step 4: Run the full suite.** Green.

- [ ] **Step 5: Commit** `feat(planning): show the plan key on session song
  rows (S3 PR 3)`

---

### Task 7: Goldens for both layouts (U14)

**Files:**
- Create: `apps/lyron_app/test/support/tolerant_golden_comparator.dart`,
  `apps/lyron_app/test/presentation/song_reader/widgets/song_reader_key_controls_golden_test.dart`,
  golden PNGs under
  `apps/lyron_app/test/presentation/song_reader/widgets/goldens/song_key_controls/`
- Modify: `docs/testing/testing-strategy.md` ("Widget Tests": a golden rule)

**Interfaces:**
- Produces: `class TolerantGoldenComparator extends LocalFileComparator {
  TolerantGoldenComparator(Uri testFile, {required double maxDiffPercent}); }`
  — `compare` passes when `ComparisonResult.passed` or `diffPercent <=
  maxDiffPercent`; set per test file in `setUpAll` (`goldenFileComparator =
  TolerantGoldenComparator(...)`, `maxDiffPercent: 0.005`), never globally.

- [ ] **Step 1: Write the golden tests**, each pumping the widget alone in a
  fixed-size `MaterialApp` with `buildLightTheme()` (and one with
  `buildDarkTheme()`), default test font:
  - Compact rail: `compact_library_song.png` (Song/Song, Reset disabled, no
    Save); `compact_plan_editor.png` (Plan/Plan, Reset and Save disabled);
    `compact_temporary.png` (Temporary/Plan, Reset and Save enabled);
    `compact_temporary_dark.png`; `compact_out_of_range.png` (Song `+14`,
    up disabled).
  - Expanded tools panel: `expanded_library_song.png`,
    `expanded_temporary.png`, `expanded_temporary_dark.png`.

- [ ] **Step 2: Generate** `cd apps/lyron_app && flutter test --update-goldens
  test/presentation/song_reader/widgets/song_reader_key_controls_golden_test.dart`,
  then inspect each PNG (labels legible, nothing clipped, no overflow
  stripes).

- [ ] **Step 3: Run the full suite without `--update-goldens`.** Green. Push
  and check the CI run; a golden mismatch on Linux beyond tolerance is a STOP
  condition.

- [ ] **Step 4: Testing doc.** Add to "Widget Tests": goldens pin reader
  chrome only, use the default test font and a per-file
  `TolerantGoldenComparator` (0.5%), are regenerated with
  `--update-goldens` and reviewed as images in the PR.

- [ ] **Step 5: Commit** `test(reader): goldens for the key controls in both
  layouts (S3 PR 3)`

---

### Task 8: Documentation and final verification

**Files:**
- Modify: `docs/architecture/decisions/ADR-042-song-key-layers.md` (status:
  implemented by S3 PRs 1–3), `docs/specs/2026-04-01-session-scoped-plan-reader-navigation.md`
  (the amendment gets "Implemented in S3 PR 3 (#<n>)"),
  `docs/specs/2026-10-13-personal-song-settings.md` (status note: PR 3
  implemented), `docs/plans/2026-10-01-delivery-roadmap.md` (S3 row: PR 3
  status)
- Check: `docs/product/vision.md` mentions no reader transpose or capo
  (verified 2026-10-20), so PS24's condition is not met: no change unless
  this PR adds a product summary line. `grep -rn "transposeOffset\|capoOffset"
  apps/lyron_app/lib apps/lyron_app/test` returns nothing (the specs keep
  their historical mentions).
- Re-count: `SongReaderState` importers after the change (`grep -rl
  "song_reader_state.dart" apps/lyron_app/lib | wc -l`, same for `test`);
  write both numbers next to the 2026-10-20 count in the spec's P8 row.
- If `docs/architecture/architecture.md` describes `PlanningWriteService`
  write calls, add one sentence on `setSessionItemKey`'s `onRecorded`.

- [ ] **Step 1: Update the docs above.**
- [ ] **Step 2: Full verification** `cd apps/lyron_app && flutter analyze &&
  flutter test`, then `./scripts/verify.sh --skip-backend-write-contracts`
  from the repository root. Expected: green.
- [ ] **Step 3: Manual check** on a phone-size and a tablet-size window (or
  simulator): library reader (Song/Temporary, Reset), plan reader as an
  editor (Save, label to Plan, plan detail chip appears, Clear), next/prev
  clears the temporary key, offline Save shows in the sync popup as `song key
  changed`.
- [ ] **Step 4: Commit** `docs: S3 PR 3 reader implemented`; open the PR
  from `feat/song-key-reader` (PR body ends with the repository's
  attribution line).
