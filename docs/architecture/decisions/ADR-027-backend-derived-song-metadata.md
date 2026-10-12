# ADR-027: Backend-Derived Song Shadow Metadata

- Status: Accepted
- Date: 2026-07-29
- Spec: `docs/specs/2026-07-29-read-boundary-and-derived-song-metadata.md`
- Plan: `docs/plans/2026-07-29-read-boundary-and-derived-song-metadata.md`
- Findings: SEC-4
- Closes: `docs/deferred/2026-05-09-song-write-derived-fields.md`
- Amended: 2026-10-12 — the Dart parser's key window moved (S2, BD2/BD8 of
  `docs/specs/2026-10-12-chordpro-base-directives.md`): it no longer closes on
  a section comment, `start_of_*` or `end_of_*`, so the old "Known divergence"
  is gone and a new one (below) replaces it. SQL is unchanged.

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

## The shared whitespace rule

Both implementations trim the **same** character set, and it is not SQL's
default. Dart's `String.trim()` strips every character carrying the Unicode
`White_Space` property plus `U+FEFF`; PostgreSQL's bare `trim()` strips only the
ASCII space. `public.chordpro_trim` therefore spells the set out explicitly:

`U+0009`–`U+000D`, `U+0020`, `U+0085`, `U+00A0`, `U+1680`, `U+2000`–`U+200A`,
`U+2028`, `U+2029`, `U+202F`, `U+205F`, `U+3000`, `U+FEFF`.

It is written with `chr()` calls rather than literal characters so the set stays
visible and greppable in the migration source — most of these are invisible, and
several are indistinguishable from a plain space in an editor.

The rule applies at every point the Dart scanner trims, not only the outer line:
the line itself, the directive body inside the braces, and the directive name and
value on either side of the colon. Trimming fewer of them would reintroduce the
divergence at a different position.

This matters beyond tidiness. An ASCII-only trim reads `{title: X}` padded with a
non-breaking space as a **lyric line** rather than a directive, so the backend
would derive a different title from the same source than the offline client
displays — precisely the drift SEC-4 exists to remove — and, because a lyric line
sets `has_seen_song_content`, it would also close the key window early. Pinned by
the Unicode parity cases in
`scripts/tests/song-derived-metadata-contract-test.sh`, covering `U+00A0`,
`U+2003` and `U+FEFF` around the directive, around the name and around the value,
plus a whitespace-only line and an ordinary lyric line.

## Known divergence

*Rewritten 2026-10-12 (S2). The previous divergence, a section-like
`{comment}`/`{c}` before `{key}`, no longer exists.*

`public.chordpro_scan_directives`
(`supabase/migrations/202607290004_derive_song_metadata.sql`) tracks a "key
window" as it walks lines in order and exposes it per directive as
`key_window_open`, which `chordpro_derive_key_signature` filters on. In SQL
the window closes on the first lyric line, on any `start_of_*` directive
(including `start_of_tab`) and on any `end_of_*` directive. A comment never
closes it.

The Dart parser reads the base `key` from the base region defined in
`chordpro_line_scanner.dart` (`ChordproBaseRegion`, BD1/BD2 of the S2 spec).
That region ends at the first lyric line or at the first non-empty content
line inside a tab environment. Comments, `start_of_*`, `end_of_*`, blank lines
and an empty tab environment do not end it. Since S2 the section-comment
trigger is gone on the Dart side, so the two implementations agree on
`{c: Verse}` followed by `{key: G}` (both read `G`).

The accepted divergence: when a `{start_of_*}`, an `{end_of_*}` or an empty
tab environment stands before `{key}` with no lyric line before it, SQL's
window is already closed (it derives no key, or an earlier one), while the
Dart window is still open and the parser reads the key. Examples:
`{start_of_verse}\n{key: G}` and `{start_of_tab}\n{end_of_tab}\n{key: G}`
give SQL `null` and Dart `G`. A tab with content before the key
(`{start_of_tab}\ne|---\n{end_of_tab}\n{key: G}`) is parity: both give `null`.

The header comments of `202607290004_derive_song_metadata.sql` and of
`chordpro_derive_key_signature` still name the pre-S2 section-comment
divergence. The migration is applied and is not edited; this section is the
authoritative description.

Why it is accepted:

- Nobody reads `songs.key_signature` today. The catalog pull selects
  `id, slug, title, version, chordpro_source`, and only the write RPCs write
  the column. The reader and the editor take the key from the source through
  the Dart parser.
- Aligning the server would need a tab-content rule in SQL as well (the
  window would close on the first non-empty tab line rather than on
  `start_of_tab`), which is more duplicated parser surface, the cost this ADR
  weighs against.

Pinned on both sides, so either side changing fails loudly instead of the two
silently drifting further apart:

- SQL: the key-window checks in
  `scripts/tests/song-derived-metadata-contract-test.sh` (Section D) assert SQL's actual result for each source
  above, labelled `ACCEPTED DIVERGENCE` or `PARITY`.
- Dart: the group `ADR-027 key-window parity fixture` in
  `apps/lyron_app/test/infrastructure/song_library/chordpro/chordpro_parser_test.dart`
  asserts the parser's actual result for the same sources, and names the
  matching contract-test check in each test name.

A change to the key window on either side must update both pins and this
section. Aligning the server (a migration of `chordpro_scan_directives`, pins
flipped to parity) is deferred:
`docs/deferred/2026-10-12-key-signature-window-server-alignment.md`.

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

## Correction (2026-10-01)

The statement that writes are RPC-only and RLS denies direct DML held only for clients that wrote through the RPCs: `authenticated`
kept table DML under permissive `for all` policies until migration
`202610010001_direct_table_dml_lockdown.sql`. Since that migration it holds
for every writer. See
[ADR-039](ADR-039-rpc-only-writes-and-explicit-grants.md).
