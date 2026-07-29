# ADR-027: Backend-Derived Song Shadow Metadata

- Status: Accepted
- Date: 2026-07-29
- Spec: `docs/specs/2026-07-29-read-boundary-and-derived-song-metadata.md`
- Plan: `docs/plans/2026-07-29-read-boundary-and-derived-song-metadata.md`
- Findings: SEC-4
- Closes: `docs/deferred/2026-05-09-song-write-derived-fields.md`

## Context

SEC-4 in the 2026-06-22 repository review recorded `title`, `artist`,
`key_signature`, `tempo_bpm`, `tags`, and `metadata_json` as client-derived
shadow fields, written verbatim from the client and never re-derived at the
write boundary. Verified against the code, the finding overstated the
problem for five of the six fields:

- `SongMutationRecord` (`application/song_library/song_mutation_sync_types.dart:69-78`)
  carries only `id, organizationId, slug, title, chordproSource, version,
  baseVersion` and error state — no artist, key, tempo, or tags field.
- The sync payload (`infrastructure/song_library/supabase_song_mutation_repository.dart:119-136`)
  sends only `p_organization_id, p_song_id, p_title, p_chordpro_source,
  p_requested_slug, p_base_version`.
- No code anywhere in `apps/lyron_app/lib` passes `p_artist`,
  `p_key_signature`, `p_tempo_bpm`, `p_tags`, or `p_metadata_json`.
- `metadata_json` is not referenced anywhere in the client.

The true situation was two problems, not one: `title` is genuinely
client-authoritative and can drift from its source (the real SEC-4 defect),
while `artist`, `key_signature`, `tempo_bpm`, and `tags` are never written by
the application at all — for any song created through the app they stay null
or empty forever, while the UI re-parses `chordpro_source` on read to display
them. `metadata_json` has no ChordPro origin to derive from (the parser
ignores `{meta}` entirely) and the client never writes it, so there is
nothing to enforce for it.

## Decision

`create_song` and `song_write_update_common` derive `title`, `artist`,
`key_signature`, `tempo_bpm`, and `tags` from canonical ChordPro inside the
`security definer` body. Client-supplied values for those fields are not
consulted; the parameters are removed from both RPC signatures
(`p_metadata_json` is removed too, since there is nothing to derive it from).
`p_title` is retained, but only as a fallback for when the source has no
title directive.

The write RPCs already are the write-acceptance boundary the deferred
document named: writes are RPC-only, and RLS denies direct DML. Deriving
there needs no column-type migration, and a later change to the derivation
applies on the next write rather than requiring a table rewrite.

The grammar reproduced in SQL
(`supabase/migrations/202607290004_derive_song_metadata.sql`) mirrors
`chordpro_line_scanner.dart:66-84` and the extraction rules in
`chordpro_parser.dart` field by field, pinned by unit-level contract tests
per field (`scripts/tests/song-derived-metadata-contract-test.sh`) rather
than approximated.

## Rejected alternatives

**Stored generated columns.** Structurally the strongest option, since the
client could not write the columns at all. Rejected because a `stored`
generated column is not recomputed when its expression changes, so every
future adjustment to the extraction rules would require a full table
rewrite — a poor fit for logic that will keep evolving alongside the parser.

**Validate instead of derive.** Reject a write whose client-supplied shadow
fields disagree with a server-side re-parse. Needs the same SQL extraction
anyway, and would surface as a sync failure for an offline edit — which
conflicts with the non-destructive model in ADR-020.

## On maintaining a second ChordPro implementation

Deriving in SQL does mean a second ChordPro implementation, and the finding
is itself about parser drift. Two things make this acceptable. First, the
derivation is authoritative and the client's value is discarded on
acceptance, so there is exactly one derivation that counts — drift becomes a
cosmetic difference between a provisional local display and the accepted
state, not a divergence between a record and its source. Second, the grammar
being reproduced is small and fully specified: `chordpro_line_scanner.dart:66-84`
is a fifteen-line rule, only seven directive names matter (`title`, `t`,
`artist`, `key`, `tempo`, `tags`, `tag`), and the two structural gates
(tab-block inertness and the key window) that apply before any field rule
are each a boolean carried across an ordered line walk. This is parity that
can be pinned by tests, not approximated — with one named, tested exception,
recorded next.

## Known divergence

`chordpro_parser.dart:62` honours the `key` directive only while
`hasSeenSongContent` is false — a "key window" that closes on the first
lyric line, any `start_of_*` directive, any `end_of_*` directive, or a
`{comment}`/`{c}` directive that `_parseCommentSection` recognises as a
section start (`chordpro_parser.dart:138`). `public.chordpro_scan_directives`
(`supabase/migrations/202607290004_derive_song_metadata.sql`) reproduces the
first three triggers exactly, tracked as it walks lines in order, and
exposes the result per directive as `key_window_open`, which
`chordpro_derive_key_signature` filters on. It does **not** reproduce the
fourth: comment-as-section recognition (`_parseCommentSection`) is itself a
small parser — unwrapping `<...>`/`[...]` wrappers, then regex-matching a
bare word against `verse`/`chorus`/`bridge`/`intro`/anything else — that
would have to be duplicated in SQL to close the window on it. Reproducing it
would add more of exactly the parser surface this finding treats as risk, and
would put every future comment-section rule in two places to keep in sync.

Concretely: a source where a `{comment}`/`{c}` directive that Dart reads as a
section start (e.g. `{c: Verse}`) precedes a `{key:}` directive, with no
prior lyric line or `start_of_*`/`end_of_*` directive, derives a key
signature in SQL that the real Dart parser would have ignored (its key
window would already be closed by the comment). This is the one accepted
divergence: narrow, named, and pinned by a contract test
(`scripts/tests/song-derived-metadata-contract-test.sh`, testing-strategy
item 17) that asserts the SQL's actual behaviour, so a future change on
either side — SQL growing comment-section support, or the Dart parser's rule
changing — fails that assertion loudly instead of the two silently drifting
further apart. Tab-block inertness and the key window's other three triggers
are fully reproduced, not approximated; only this fourth trigger is the
accepted gap.

## Risks accepted

- **No backfill.** Existing rows keep whatever they hold until their next
  write. A backfill would rewrite `updated_at`, `version`, and
  `last_modified_by` across the catalogue and would collide with pending
  offline mutations. An update that carries no new source still re-derives
  from the stored source, making convergence automatic and incremental
  instead.
- **A user's local title can change after sync**, if the client's parse and
  the SQL parse disagree on the same source. This is the intended direction
  of authority; the accepted title wins.
- **Breaking signature change for out-of-tree callers.** The Flutter client
  never sent the removed parameters. `scripts/tests/song-crud-write-contract-test.sh`
  is updated in this same slice; any caller outside the repository would
  break.
