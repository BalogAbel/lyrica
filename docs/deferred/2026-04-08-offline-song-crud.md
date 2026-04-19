# Offline-First Song CRUD Deferred Work

Originating slice:
- `docs/specs/2026-04-05-song-crud.md`
- `docs/plans/2026-04-08-offline-first-song-crud.md`

## Status

Resolved by `docs/specs/2026-04-19-song-sync-convergence-hardening.md` and its implementation slice.

## Deferred Item

### Handle songs that disappear on the server while a local mutation still exists

Closed.

The repository now defines and verifies:

- durable remote-deletion classification for update-sourced sync failures
- same-id backend recreation for update-sourced `keep mine`
- accepted convergence for delete-sourced remote deletion
- no-fetch `discard mine` when the canonical row is already gone
- preserved planning-title tombstones for session-scoped reader flows after canonical song removal

## Follow-up Note

Future song-sync slices must preserve these convergence guarantees. If remote deletion gains richer UX later, build on the current persisted metadata and tombstone contract instead of reintroducing generic not-found behavior.

### Extract a shared song editor dialog if create/edit surfaces keep growing

The current create-song dialog in the song list and edit-song dialog in the song reader now share the same core form shape:

- title field
- ChordPro source field
- cancel/save actions

They intentionally remain separate in this slice because they live in different feature surfaces and the branch has already gone through heavy review-driven churn. A late cross-screen refactor would add coordination risk without changing correctness.

If future work adds more song create/edit entry points or starts changing these dialogs in parallel, extract a shared song editor dialog instead of continuing to duplicate the same form behavior.

Expected follow-up scope:

- define one shared draft/result contract for create and edit flows
- keep screen-specific orchestration outside the shared widget
- preserve current source-editing behavior, including untrimmed ChordPro payloads
- add widget coverage for both create and edit consumers after extraction

## Planning Note

Any future slice that changes song mutation sync, conflict handling, overwrite/discard flows, or delete semantics must treat the convergence-hardening rules as established repository behavior.
