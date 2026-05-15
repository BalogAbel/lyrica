# Song Create/Edit Consistency Spec

> Status: Approved

## Goal

Replace the `_SongEditorDialog` AlertDialog used for new song creation with the existing full-screen `SongEditorScreen`, unifying the create and edit experiences into a single coherent flow.

## Problem

Song creation and song editing currently use different surfaces:

- **Create**: `_SongEditorDialog` — an AlertDialog with title and source fields, invoked via `showDialog` from `SongListScreen`. Discards the full editor feature set (transpose, capo, preview, overview panel) and uses a separate save path.
- **Edit**: `SongEditorScreen` — a full-screen, responsive editor with ChordPro source editing, derived metadata overview, transpose/capo controls, and a live preview.

This inconsistency means a user creating a new song gets a degraded experience with fewer affordances, and the codebase maintains two separate save paths for the same domain operation.

## Decision

Extend `SongEditorScreen` to support a create mode using named constructors. Add a `/songs/new` route. Remove `_SongEditorDialog` and `_SongEditorDraft` entirely.

## Scope

- Add `SongEditorScreen.create()` named constructor alongside the existing `SongEditorScreen.edit(...)` constructor.
- Add `AppRoutes.songCreate('/songs/new')` route.
- Wire `SongEditorScreen.create()` into the router directly (no resolver needed — no async song load on create).
- Change `SongListScreen._createSong()` to push `/songs/new` instead of showing a dialog.
- Remove `_SongEditorDialog`, `_SongEditorDraft`, and the `_createSong` dialog orchestration.
- On save in create mode: call `createSong()`, invalidate providers, navigate to `/songs/:newSlug` (song reader).
- On cancel in create mode: `context.pop()` back to the song list. Dirty-state confirmation guard applies here too.
- Top bar title: `'New song'` in create mode, `'Edit song'` in edit mode — new `AppStrings.songCreateTitle` constant.

## Non-Goals

- No change to the `SongEditorScreen` visual layout, panels, or existing edit behavior.
- No change to `SongLibraryService.createSong()` or `updateSong()` signatures.
- No new backend authorization rules.
- No change to the song domain model.
- No redesign of the song list screen beyond removing the dialog.

## Architecture

### Named Constructors

```dart
class SongEditorScreen extends ConsumerStatefulWidget {
  // Edit mode — loads existing song data via SongEditorSlugRouteResolver
  const SongEditorScreen.edit({
    super.key,
    required String songId,
    required String songSlug,
    String? initialSource,
  });

  // Create mode — starts with default ChordPro sample source
  const SongEditorScreen.create({super.key});
}
```

The `_isCreating` boolean (private) differentiates behavior inside `_SongEditorScreenState` without exposing the flag in the public API. Edit-mode fields (`songId`, `songSlug`) are nullable and asserted non-null only in edit-mode call sites.

### Save Path

| Mode   | Service call          | Post-save navigation        |
|--------|-----------------------|-----------------------------|
| Edit   | `updateSong()`        | `context.replace(/songs/:slug)` (reader) |
| Create | `createSong()`        | `context.replace(/songs/:newSlug)` (reader) |

The new slug comes from the `SongMutationRecord` returned by `createSong()`.

### Cancel Path

| Mode   | Behavior                                    |
|--------|---------------------------------------------|
| Edit   | `context.replace(/songs/:slug)` (reader) — unchanged |
| Create | `context.pop()` — back to song list         |

Dirty-state confirmation guard (`_confirmDiscardChangesIfNeeded`) applies in both modes.

### Route

```
AppRoutes.songCreate('/songs/new')
  → GoRoute builder → SongEditorScreen.create()
```

No resolver widget needed: create mode requires no async song data load.

### SongListScreen

`_createSong()` is simplified:

```dart
Future<void> _createSong(BuildContext context, WidgetRef ref) async {
  final activeContext = ref.read(activeCatalogContextProvider);
  if (activeContext == null) return;
  context.push(AppRoutes.songCreate.path);
}
```

Provider invalidation (`songMutationEntriesProvider`, `songLibraryListProvider`) moves to `SongEditorScreen._saveAndReturn` in create mode. This removes the dialog orchestration and the dependency on `_SongEditorDraft`.

## Testing Strategy

TDD: write tests before implementing each behavioral change.

### Widget Tests — `song_list_screen_test.dart`

- **Updated**: "creates song" test — `songCreateAction` tap triggers navigation to `/songs/new`, no dialog widget rendered.

### Widget Tests — `song_editor_screen_test.dart`

- **New**: Create mode renders with default source (ChordPro sample).
- **New**: Create mode save calls `createSong()` (not `updateSong()`).
- **New**: Create mode save navigates to `/songs/:returnedSlug`.
- **New**: Create mode cancel with dirty state shows discard confirmation.
- **New**: Create mode cancel with clean state pops without confirmation.

### Integration Tests — `local_first_song_crud_flow_test.dart`

- **Updated**: Song creation flow — uses full-screen route instead of dialog fields.

## Acceptance Criteria

1. Tapping "Add song" on the song list screen navigates to `/songs/new`.
2. `/songs/new` renders `SongEditorScreen` with an empty/default ChordPro source, top bar title "New song".
3. Saving in create mode calls `createSong()`, invalidates providers, and navigates to the new song's reader screen.
4. Cancelling a clean create screen pops back to the song list without confirmation.
5. Cancelling a dirty create screen shows the discard confirmation dialog before navigating.
6. Edit mode behavior is unchanged — existing tests pass without modification.
7. `_SongEditorDialog` and `_SongEditorDraft` are fully removed.
8. No existing test is deleted; all passing tests remain green.

## Documentation Impact

- `docs/specs/2026-05-15-song-create-edit-consistency.md` — this file
- `docs/plans/` — implementation plan (next step)
- No domain model changes required
