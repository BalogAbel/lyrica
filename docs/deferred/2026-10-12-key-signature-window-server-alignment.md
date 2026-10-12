# Server-Side Key Window Is Not Aligned With The Client

**Found:** 2026-10-12, by S2 (`fix/chordpro-base-directives`).
**Related:** ADR-027 ("Known divergence", amended 2026-10-12),
`docs/specs/2026-10-12-chordpro-base-directives.md` (BD2, BD8),
`supabase/migrations/202607290004_derive_song_metadata.sql`.

**Status:** accepted divergence, pinned on both sides. Not implemented.

## Problem

`public.chordpro_scan_directives` closes its key window on the first lyric
line and on every `start_of_*` (including `start_of_tab`) and `end_of_*`
directive. Since S2 the Dart parser's base region closes only on the first
lyric line or the first non-empty tab content line. For a source with a
`{start_of_*}`, `{end_of_*}` or an empty tab environment before `{key}` (and
no lyric line before it), `songs.key_signature` is `null` (or an earlier key)
while the reader and editor show the key.

Nothing reads `songs.key_signature` today (the catalog pull selects
`id, slug, title, version, chordpro_source`), so the divergence has no visible
effect yet.

## What is needed

1. A migration that redefines `public.chordpro_scan_directives` so the key
   window closes only on a lyric line or on the first non-empty tab content
   line. `start_of_tab`, other `start_of_*` and `end_of_*` no longer close it.
   Everything else in the scanner (tab-block inertness, trimming, emitted
   rows) stays as is.
2. Flip the pins to parity in the same change:
   - `scripts/tests/song-derived-metadata-contract-test.sh`: the checks
     labelled `ACCEPTED DIVERGENCE` (and the two scanner-level
     `key_window_open` start_of/end_of checks) now expect the key.
   - the Dart group `ADR-027 key-window parity fixture` in
     `apps/lyron_app/test/infrastructure/song_library/chordpro/chordpro_parser_test.dart`
     keeps its expectations; its test names change from `ACCEPTED DIVERGENCE`
     to `PARITY`.
   - ADR-027 "Known divergence" is rewritten to say there is none.
3. Optional backfill. Not required: ADR-027 rows converge on their next write
   (an update with no new source re-derives from the stored source). A
   backfill would rewrite `updated_at`, `version` and `last_modified_by`
   across the catalog and collide with pending offline mutations, which is why
   ADR-027 rejected it.
4. Hosted deploy by hand in the SQL editor, per
   `docs/workflows/development-workflow.md` (never `db push`).

## Trigger

The first reader of `songs.key_signature` (search, sort or filter by key,
export, FreeShow), or the next migration that touches the derive-metadata
functions, whichever comes first.
