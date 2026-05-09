# Song Write Derived Fields Deferred Work

Originating slice:
- `docs/specs/2026-04-05-song-crud.md`
- `docs/specs/2026-05-02-song-editing-ui.md`
- `docs/plans/2026-05-02-song-editing-ui.md`

## Status

Deferred.

## Deferred Item

### Enforce derived song fields from canonical ChordPro during write acceptance

The current local-first song write contract persists both:

- canonical `chordproSource`
- client-derived shadow fields such as `title`

The domain rule already states that `title`, `artist`, `key_signature`,
`tempo_bpm`, `tags`, and `metadata_json` are derived shadow fields refreshed
from canonical ChordPro source after create, import, or save.

What is still missing is a repository-enforced write contract that makes this
rule impossible to violate even if client and server parsing drift:

- create/update acceptance should derive shadow metadata from canonical
  `chordproSource` at the backend or write-acceptance boundary
- client-provided shadow fields should not be authoritative during canonical
  write acceptance
- local-first mutation records and sync payloads may still carry provisional
  shadow fields for offline UX, but accepted canonical state must be refreshed
  from source-derived parsing

This is intentionally deferred because it changes the song CRUD write contract,
sync flow, and possibly backend responsibilities. It is not a narrow editor UI
change.

## Planning Note

Any future slice that changes song create/update contracts must decide whether
shadow metadata is:

- authoritative from client writes, or
- derived only from canonical ChordPro during write acceptance

Do not leave this implicit across UI, sync, and backend layers.
