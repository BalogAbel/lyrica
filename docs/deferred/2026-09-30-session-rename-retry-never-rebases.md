# Retrying a Conflicted Session Rename Never Rebases

**Slice:** feat/plan-delete-session-cascade (found by review gate 3 on
2026-09-30; the bug predates that slice)
**Related:** `docs/specs/2026-09-29-plan-delete-and-session-cascade.md` (D9)
**Files:**
`apps/lyron_app/lib/src/application/planning/drift_planning_mutation_store.dart`
(`_currentBaseVersionFor`, `retryMutation`)

## Problem

`retryMutation` rebases a row's `baseVersion` through
`_currentBaseVersionFor`. That function looks up the session by
`record.sessionId`. A session-aggregate row does not set `sessionId`; the
session id is the row's `aggregateId`. So for a `sessionRename`:

- The lookup finds nothing.
- The row keeps its stale base.
- Every retry of a conflicted rename conflicts again. "Keep mine" never
  works for a session rename.

The only way out is to discard the rename and rename the session again.

The originating slice fixed the same lookup for `sessionDelete` (gate 3
F3), and only there. That fix rebases only after a visible conflict. Rename
was deliberately left unchanged, because it is not part of the cascade.

## Why it was deferred

The bug has nothing to do with the cascade delete. The conflict is visible,
and discard-and-redo works. Fixing it changes keep-mine semantics for
session renames: the retry would overwrite a foreign rename, as keep-mine
already does for a plan edit. That change deserves its own test coverage and
review.

## Requirements for the slice that picks this up

- Resolve the session id from `aggregateId` for `sessionRename` in
  `_currentBaseVersionFor`, like `sessionDelete`.
- Decide whether a rename retry rebases in every status (edit semantics,
  like `planEdit`) or only after a conflict, and document the choice.
- Red test first: a conflicted rename retried after a refresh showing a
  newer session version is sent with that version.
