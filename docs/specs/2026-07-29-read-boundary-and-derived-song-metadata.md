# Read Boundary and Backend-Derived Song Metadata

> Status: Draft

## Goal

Close the two deferred items in
`docs/deferred/2026-05-16-auth-schema-lint-followups.md` and the one in
`docs/deferred/2026-05-09-song-write-derived-fields.md` (SEC-4). Three changes
that all concern what the backend treats as authoritative:

1. **Read boundary** — resolve, by decision rather than rewrite, whether the
   Flutter repositories may keep reading `songs`, `plans` and `sessions`
   directly under RLS.
2. **`unaccent` schema** — move the extension out of `public` and pin
   `public.slugify` to a schema-qualified call.
3. **SEC-4** — derive song shadow metadata from canonical ChordPro at the
   write-acceptance boundary instead of accepting it from the client.

## Problem

### Read boundary

`docs/deferred/2026-05-16-auth-schema-lint-followups.md` leaves open whether
`authenticated` should keep table-level `SELECT`, and offers two acceptable
resolutions: replace the reads with RPCs or views, **or** document why
RLS-protected table reads remain the chosen architecture.

Measured surface, verified rather than assumed:

| | count |
|---|---|
| direct table **reads** (`.from(...).select(...)`) | 8 |
| direct table **writes** | **0** |
| files containing them | 3, all under `lib/src/infrastructure/` |
| tables touched | `songs` (4), `plans` (3), `sessions` (1) |

Call sites: `supabase_song_repository.dart:19,26,34`,
`supabase_song_mutation_repository.dart:13`,
`supabase_planning_repository.dart:26,38,48,63`.

### `unaccent`

`unaccent` is the only extension still installed in `public`; every other
extension lives in `extensions`, `graphql`, `vault` or `pg_catalog`.
`public.slugify` calls `unaccent(...)` unqualified, relying on
`set search_path = public`.

`slugify` is on the planning write path — `plan_next_slug` and
`session_next_slug` build on it, and `202606290001_planning_slug_suffix_overflow_fix.sql`
already had to repair a real bug there — so its observable behaviour must be
pinned before the call is repointed.

### SEC-4, restated from evidence

The review records SEC-4 as: "`title`, `artist`, `key_signature`, `tempo_bpm`,
`tags`, `metadata_json` are derived client-side from canonical ChordPro and
written as shadow fields."

**That is accurate for one field of the six.** Verified against the code:

- `SongMutationRecord`
  (`application/song_library/song_mutation_sync_types.dart:69-78`) carries
  `id, organizationId, slug, title, chordproSource, version, baseVersion` and
  error state. It has **no** artist, key, tempo or tags field.
- The sync payload
  (`infrastructure/song_library/supabase_song_mutation_repository.dart:119-136`)
  sends only `p_organization_id`, `p_song_id`, `p_title`,
  `p_chordpro_source`, `p_requested_slug` and `p_base_version`.
- No code anywhere in `apps/lyron_app/lib` passes `p_artist`,
  `p_key_signature`, `p_tempo_bpm`, `p_tags` or `p_metadata_json`.
- `metadata_json` is not referenced anywhere in the client at all.

So the true situation is two problems, not one:

- **`title` is client-authoritative and can drift from its source.** This is the
  real SEC-4 defect.
- **`artist`, `key_signature`, `tempo_bpm` and `tags` are never written by the
  application at all.** For any song created through the app they stay null or
  empty forever, while the UI re-parses `chordpro_source` on read to display
  them. They are columns the schema promises and nothing fills.

`metadata_json` has no ChordPro origin to derive from — the parser ignores
`{meta}` entirely (`chordpro_parser.dart:129-130`) — and the client never
writes it, so there is nothing to enforce.

## Scope

- ADR closing the read-boundary question. No repository changes.
- `unaccent` moved to `extensions`; `public.slugify` schema-qualified; slug
  behaviour pinned by a contract test written first.
- `create_song` and `song_write_update_common` derive `title`, `artist`,
  `key_signature`, `tempo_bpm` and `tags` from canonical ChordPro. The
  client-supplied parameters for those four fields, plus `p_metadata_json`, are
  **removed** from the RPC signatures; `p_title` is retained as a fallback.
- Both deferred documents removed.
- SEC-4 corrected and marked fixed in the repository review.

## Non-Goals

- No read RPCs or views. See the decision below.
- No change to `metadata_json`, beyond documenting why it is out of scope.
- No change to the ChordPro parser in Dart, and no attempt to make the two
  implementations share code.
- No change to the exactly-once planning mutation sync (ADR-019) or the
  non-destructive session model (ADR-020).
- No backfill of existing rows. Derivation applies at the next write; see
  Risks.

## Decisions

### 1. The read boundary stays on RLS-protected table reads (ADR-026)

RLS is the enforcement layer today, and it would remain the enforcement layer
behind a view (`security_invoker`) or be **re-implemented** inside a read RPC.
Replacing the reads changes who spells the query, not who enforces access; a
hand-written tenant predicate in each read RPC is a second place to get it
wrong.

The half that genuinely needs a chokepoint is already closed: there are **zero**
direct table writes, and every mutation goes through a `security definer` RPC
with RLS denying direct DML.

The eight reads feed the local-first projection sync, which the review's own §6
identifies as the highest-risk subsystem in the repository. Rewriting them buys
no authorization guarantee and spends risk where there is least margin.

*Rejected — `security_invoker` views* (available on PostgreSQL 17.6): would
narrow the exposed surface without adding authorization logic, and is the
strongest of the alternatives. Rejected because the benefit is defence in depth
against a surface that RLS already governs, while the cost lands on three
repositories and the projection-sync tests, and every future column has to be
tracked in two places.

*Rejected — read RPCs*: tightest against table exposure, but duplicates the
tenant predicate per RPC, discards PostgREST column projection, and rewrites the
riskiest subsystem.

Consequence to state plainly in the ADR: `authenticated` keeps table `SELECT`,
so the PostgREST and `pg_graphql` surfaces stay reachable — RLS-scoped, but
reachable. That is the accepted trade.

### 2. Song shadow metadata is derived at write acceptance (ADR-027)

`create_song` and `song_write_update_common` derive the shadow fields from
canonical ChordPro inside the `security definer` body. Client-supplied values
are not consulted.

The write RPCs already **are** the write-acceptance boundary the deferred
document names: writes are RPC-only and RLS denies direct DML. Deriving there
needs no column-type migration, and a later change to the derivation applies on
the next write rather than requiring a table rewrite.

*Rejected — stored generated columns*: structurally the strongest, since the
client could not write the columns at all. Rejected because a `stored` generated
column is **not** recomputed when its expression changes, so every future
adjustment to the extraction rules would require a full table rewrite — a poor
fit for logic that will keep evolving alongside the parser.

*Rejected — validate instead of derive*: needs the same SQL extraction anyway,
and rejecting a write whose shadow fields disagree would surface as a sync
failure for an offline edit, which conflicts with the non-destructive model in
ADR-020.

**On the second-parser objection.** Deriving in SQL does mean a second ChordPro
implementation, and the finding is itself about parser drift. Two things make it
acceptable. First, the derivation is authoritative and the client's value is
discarded on acceptance, so there is exactly one derivation that counts — drift
becomes a cosmetic difference between a provisional local display and the
accepted state, not a divergence between a record and its source. Second, the
grammar being reproduced is small and fully specified: the directive rule in
`chordpro_line_scanner.dart:66-84` is fifteen lines, only seven directive names
matter, and the two structural gates described under Target Behaviour are a
boolean each. This is parity that can be pinned by tests, not approximated —
with one named, tested exception, also recorded there.

## Target Behaviour

### Directive grammar (must match `chordpro_line_scanner.dart:66-84` exactly)

For each line of the source, after `\r\n` → `\n` normalisation and trimming:

- a directive line starts with `{` and ends with `}`;
- the body is the text between the braces, trimmed; an empty body is not a
  directive;
- the first `:` splits name from value; the name is trimmed and lowercased, the
  value is trimmed;
- with no `:`, the whole body is the name and the value is null.

### Two structural gates (must match `chordpro_parser.dart`)

The scan is a small state machine, not a stateless directive sweep. Both gates
below apply before any field rule is evaluated.

**Tab-block inertness** (`chordpro_parser.dart:52-54`). While the current
section is a tab section, a directive whose name does not start with `end_of_`
is treated as tab content, not as a directive. A `{title: X}` between
`{start_of_tab}` and `{end_of_tab}` is therefore **not** a title. This gate
affects every field.

**The key window** (`chordpro_parser.dart:62`). The `key` directive is honoured
only while `hasSeenSongContent` is false. That flag is set by:
- the first lyric line (`:36`);
- any `start_of_*` directive (`:150`);
- any `end_of_*` directive (`:201`);
- a `{comment}` / `{c}` that the parser recognises as a section start (`:138`).

`title`, `artist`, `tempo` and `tags` are **not** gated this way — they are
honoured anywhere outside a tab block.

**One accepted divergence, deliberately scoped.** The SQL implements the key
window from lyric lines and from `start_of_*` / `end_of_*` directives, but does
**not** reproduce the comment-as-section branch. Reproducing
`_parseCommentSection` would duplicate materially more parser logic — more of
exactly what this finding calls a risk — and would put every future comment rule
in two places. The divergence can only be observed when a comment the Dart
parser reads as a section start precedes a `{key:}` directive and no lyric line
or section directive has appeared yet. It affects `key_signature` only, is
recorded in ADR-027, and is pinned by a test so it stays a known boundary rather
than a surprise.

### Field rules (must match `chordpro_parser.dart`)

| field | directives | rule |
|---|---|---|
| `title` | `title`, `t` | last occurrence wins; value or `''` |
| `artist` | `artist` | last occurrence wins; trimmed |
| `key_signature` | `key` | inside the key window only; a null or empty trimmed value is skipped **without clearing** an earlier valid one; last valid occurrence wins |
| `tempo_bpm` | `tempo` | last occurrence wins; integer parse, non-integer ignored; a value outside `int4` must not abort the write |
| `tags` | `tags`, `tag` | last occurrence wins; split on `,`, trim each, drop empties |

Last-occurrence-wins is not a choice: the Dart parser assigns on every matching
directive as it scans, so the final one survives. The SQL must do the same.

Note that Dart's `String.trim()` strips Unicode whitespace while SQL's `trim()`
defaults to ASCII space only; the SQL must trim the same character set
explicitly or the two will disagree on padded values.

### `create_song`

Signature loses `p_artist`, `p_key_signature`, `p_tempo_bpm`, `p_tags` and
`p_metadata_json`. `p_title` is retained as a **fallback**, not as the
authority.

- Derived values come from `coalesce(p_chordpro_source, '')`.
- `title` is the derived title when it is non-empty after trimming; otherwise
  `p_title`; otherwise the existing `gen_random_uuid()::text` slug fallback.
  `songs.title` is `not null`, so a fallback chain is required, and this one
  matches the client's own import behaviour (`chordpro_import_service.dart:57-60`).
- The slug continues to be derived from the resulting title, so slug and title
  stay consistent.
- `metadata_json` is inserted as `'{}'::jsonb`.

### `song_write_update_common` (and therefore `update_song` and `overwrite_song_update`)

Signatures lose the same four parameters plus `p_metadata_json`. `p_title` is
retained as a fallback.

- The effective source is `coalesce(p_chordpro_source, song.chordpro_source)` —
  the existing "null means unchanged" semantics.
- All five shadow fields are derived from that effective source on **every**
  update, including updates that do not carry a source. An update therefore
  converges a legacy row onto its source without a backfill.
- `title` falls back to `coalesce(p_title, song.title)` when the source declares
  none.
- `metadata_json` is left untouched.

Version checking, conflict reporting, `sync_status`, `last_modified_by` and the
slug behaviour are unchanged. This slice changes what is written, not when a
write is accepted.

### Grants

Dropping parameters changes the function signatures, so the old ones must be
dropped and the new ones created — which discards the grants set in
`202605160007_auth_boundary_hardening.sql`. The migration reapplies
`revoke all ... from public, anon, authenticated` and
`grant execute ... to authenticated` for each new signature, and a contract test
pins both the absence of the old signatures and the grants on the new ones. This
is the same failure mode already seen in the SEC-1 slice, so it is tested rather
than trusted.

### `unaccent`

`alter extension unaccent set schema extensions`, then redefine `public.slugify`
to call `extensions.unaccent(...)`. `slugify` keeps `set search_path = public`
and stays `immutable`.

## Testing Strategy

All backend work lands in the write-contract suite, failing first.

**Slug parity (before the `unaccent` move).** Extend
`scripts/tests/planning-write-contract-test.sh`, or add a dedicated script, to
pin `public.slugify` output for a table of inputs covering accented characters,
punctuation runs, leading and trailing separators, and the empty result. The
same table must pass unchanged after the extension move — that is the entire
point of writing it first.

**Song derivation** (new `scripts/tests/song-derived-metadata-contract-test.sh`,
chained from `./scripts/backend-write-contracts.sh`):

1. `create_song` with `{title: X}` in the source and a *different* `p_title`
   stores the derived title, not the supplied one.
2. `create_song` with no `{title}` falls back to `p_title`.
3. `{t: X}` is honoured identically to `{title: X}`.
4. Later occurrences of a directive win over earlier ones.
5. `artist`, `key_signature`, `tempo_bpm` and `tags` are populated from the
   source on create.
6. `tags` splitting: `{tags: a, b ,, c}` yields exactly `{a,b,c}`.
7. A non-integer `{tempo}` leaves `tempo_bpm` null rather than failing the write.
8. An update carrying a new source re-derives every shadow field.
9. An update carrying **no** source re-derives from the stored source — a row
   with a stale null `artist` gains it on the next unrelated update.
10. The slug follows the derived title on create.
11. The removed parameters no longer exist: calling `create_song` with
    `p_artist` fails as an unknown function signature.
12. `redeem`-style grant check: the new signatures are executable by
    `authenticated` and not by `anon`; the old signatures are gone.
13. Version-conflict behaviour on `update_song` is unchanged (regression guard).
14. Tab-block inertness: a `{title: X}` between `{start_of_tab}` and
    `{end_of_tab}` does not become the title, while one after `{end_of_tab}`
    does.
15. Key window: `{key: G}` before any lyric line is honoured; `{key: G}` after a
    lyric line, after a `{start_of_verse}`, and after an `{end_of_verse}` is
    ignored in each case.
16. An empty `{key:}` inside the window does not clear a valid key set earlier.
17. The accepted divergence is pinned explicitly: a `{comment}` that the Dart
    parser treats as a section start does **not** close the key window in SQL.
    The test asserts the SQL behaviour and names the divergence, so a future
    change to either side fails loudly instead of drifting.
18. Unicode whitespace padding around a directive value is trimmed identically
    to Dart's `String.trim()`.

**Parity with the Dart parser.** The extraction rules above are asserted against
the same fixtures the Dart parser tests use, so a divergence shows up as a
failing contract test rather than as drifted data. Reuse the existing ChordPro
fixtures where they exist.

**Flutter.** `apps/lyron_app` needs no production change: it never sent the
removed parameters. Existing song CRUD and sync tests must pass untouched — if
one fails, that is a real regression, not a fixture to adjust.

## Documentation

- `docs/architecture/decisions/ADR-026-rls-protected-read-boundary.md`
- `docs/architecture/decisions/ADR-027-backend-derived-song-metadata.md`
- `docs/architecture/repository-review-2026-06-22.md` — mark SEC-4 fixed, and
  **correct its description**: the finding overstated the problem for five of the
  six fields.
- `docs/architecture/architecture.md` — the read boundary and the song write
  contract.
- `docs/domain/domain-model.md` — shadow metadata is source-derived at write
  acceptance.
- `docs/testing/testing-strategy.md` — the new contract test.
- **Remove** `docs/deferred/2026-05-16-auth-schema-lint-followups.md` and
  `docs/deferred/2026-05-09-song-write-derived-fields.md`, each in the commit
  that resolves it.

## Risks

- **No backfill.** Existing rows keep whatever they hold until their next write.
  Accepted deliberately: a backfill would rewrite `updated_at`, `version` and
  `last_modified_by` across the catalogue and would collide with pending offline
  mutations. Rule 9 in the update path makes convergence automatic and
  incremental instead.
- **A user's local title can change after sync.** If the client's parse and the
  SQL parse disagree, the accepted title wins and the display updates. This is
  the intended direction of authority, and the parity tests bound how often it
  can happen.
- **Signature changes are breaking for out-of-tree callers.** The Flutter client
  does not pass the removed parameters, but `scripts/tests/song-crud-write-contract-test.sh`
  and anything under `scripts/manual-validation/` may. They are updated in the
  same slice; a caller outside the repository would break.
- **`unaccent` behaviour must not shift.** The extension move is a schema
  change, not a version change, so output should be identical — the parity test
  written first is what makes that a fact rather than an expectation.
- **`slugify` is declared `immutable` while `unaccent(text)` is `stable`.** This
  predates the slice and is not introduced by it. Noted here because the move
  touches the call site; if it proves to matter, the fix is the
  `unaccent('unaccent'::regdictionary, ...)` form, which is immutable. Out of
  scope unless the parity test surfaces it.
