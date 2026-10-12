# Spec: ChordPro Base Directives

> Status: Accepted (2026-10-12, design gate approved). Partially supersedes
> the base-value reading rules of
> `docs/specs/2026-04-22-song-reader-capo-and-instrument-display.md` and the
> "Known divergence" section of ADR-027.

- Date: 2026-10-12
- Branch: `fix/chordpro-base-directives`
- Roadmap slice: S2 (`docs/plans/2026-10-01-delivery-roadmap.md`)
- Closes: item 1 of `docs/deferred/2026-04-22-song-reader-chordpro-modulation.md`
  (removed in this change). Item 2 (in-song modulation) stays for S8.
- Hard dependents: S3 (saved transpose and capo need one consistent base) and
  S8 (modulation builds on the same parser semantics).
- Amends: ADR-027 "Known divergence".

## Problem

The base `key`, `capo` and `transpose` of a song are read in three places, and
they disagree.

1. **Reader (parser).** `ChordproParser` honours the three directives only
   while `hasSeenSongContent` is false. A lyric line, a section-like
   `{comment:<Intro>}`, and any `{start_of_*}` or `{end_of_*}` set it.
2. **Editor read.** `currentPreLyricDirectiveInt`
   (`song_editor_directives.dart`) scans until the first lyric-kind line. It
   ignores comments and section markers, takes the **first** occurrence, and
   turns an invalid value into `0`.
3. **Editor write.** `_upsertDirective` (`song_editor_controller.dart`) finds
   every `{transpose:` or `{capo:` line in the **whole** source with a regex,
   keeps the first one before the first lyric line (found with a third,
   cruder rule: non-empty and not starting with `{`), and deletes all the
   others.

Effects:

- **B1, visible mismatch.** `{comment:<Intro>}` then `{transpose: 2}` then
  `{capo: 3}` then `[A] [C#m/G#]`: the editor shows Transpose +2 and Capo 3,
  the reader shows 0 and 0.
- **B2, duplicates and invalid values.** The parser takes the last valid
  occurrence and warns on invalid ones; the editor takes the first and maps
  invalid to 0.
- **B3, key.** `{key}` sits behind the same gate, so `{comment:<Intro>}`
  followed by `{key: G}` loses the key in the reader too.
- **B4, data loss.** Any Transpose or Capo tap in the editor deletes every
  in-song `{transpose:` / `{capo:` line (a key change, which is S8's
  modulation content). With no pre-lyric occurrence, it deletes all of them
  and inserts a new one.

ChordPro semantics (chordpro.org, via Context7): `transpose` applies "from
where it appears", so a `transpose` before any chord applies to the whole
song; `key` may appear several times and each applies from its position
onwards; `comment` is printed text that is "not part of the lyrics and
chords"; environments (`start_of_verse` etc.) group lines. The reference
implementation warns on several `capo` settings.

## Decisions

### BD1. One base-region predicate, on the scanner

`chordpro_line_scanner.dart` gains:

```dart
/// The base region of a ChordPro source (BD1, BD2): every line before the
/// first song-content line. Base `key`, `capo` and `transpose` are read only
/// from directives in this region; nothing else closes it.
class ChordproBaseRegion {
  factory ChordproBaseRegion.of(Iterable<ChordproLine> lines);

  /// 1-based line number of the first song-content line, or null when the
  /// source has no song content (the whole source is the base region).
  final int? boundaryLineNumber;

  bool contains(ChordproLine line);
}
```

It is the only definition of the boundary. Three callers share it:

- the parser's read of `key`, `capo` and `transpose` (replaces
  `hasSeenSongContent`);
- the editor's read, which goes through the parser (BD5);
- the editor's write, which builds the region from the same scanned line list
  it edits (BD6). No per-line re-scan without tab context remains.

### BD2. The boundary is the first song-content line

A line is song content when either holds:

- it is a `ChordproLineKind.lyric` line (a chord-only line such as
  `[A] [C#m/G#]` is lyric-kind);
- it is a non-empty line inside a tab environment (after `{start_of_tab}`),
  other than the `end_of_*` line that closes it. Directive-shaped lines
  inside a tab are tab text in the parser, so they count as content here
  too. This mirrors the parser's tab branch exactly: any `end_of_*` closes
  the tab.

Nothing else closes the region: not `{comment}` / `{c}` (section-like or
not), not `{start_of_*}` or `{end_of_*}`, not blank lines, not unknown
directives. A source without song content is all base region.

### BD3. One boundary for all three directives

`key`, `capo` and `transpose` use the same region. The roadmap row names only
transpose and capo, but splitting the boundary would keep
`{comment:<Intro>}{key: G}` broken.

### BD4. Last valid base occurrence wins; invalid values follow the parser

ChordPro directives are positional, so the last occurrence inside the base
region is the one in effect when the first content line starts. Invalid
values keep the parser's existing rules everywhere:

- non-integer or missing `capo` / `transpose`: warning diagnostic, value
  ignored (an earlier valid one stays);
- negative `capo`: warning diagnostic, ignored;
- empty `key`: warning diagnostic, ignored.

**Accepted side effect.** A malformed base directive placed after a comment
or a section marker used to be dropped silently (the gate was already
closed). It now produces its warning: the editor banner and the reader's
warning indicator count it. This is correct behaviour, not a regression.

### BD5. The editor reads its base values from the parser

`SongEditorParsedSong` takes `baseTranspose`, `baseCapo` and `sourceKey` from
`ChordproParser.parse`. `currentPreLyricDirectiveInt` and
`song_editor_directives.dart` are deleted. Editor and reader can no longer
disagree for the same source, because there is one computation. The editor
parses the normalized source (`ChordproNormalizer`), the string the save path
stores and the reader parses, so aliases such as `{sot}`/`{eot}` open and close
tabs for the editor exactly as they do for the reader.

### BD6. The editor write touches only base-region directives (B4 fix)

The region, the occurrences and the insertion index come from the scan of the
normalized source, while the bytes are edited on the raw line records.
Normalization maps every line to exactly one line, so raw record `i` is
normalized scanner line `i + 1`.

`transposeUp/Down` and `capoUp/Down`:

- compute the new value from the parser's base value (±1; capo is clamped at
  0, as today);
- if the base region holds one or more occurrences of that directive:
  rewrite the **last** one in place to `{name: value}` and remove the other
  base-region occurrences of the same name;
- otherwise insert `{name: value}` at the existing insertion point (after the
  leading metadata block, before the first other directive or content line).
  That point is always inside the base region; it is computed from the same
  scanned lines and region, not by re-scanning each line on its own;
- never remove, rewrite or move a line at or after the boundary;
- never rewrite or remove a malformed line whose directive value holds a
  brace (for example `{transpose: 1} [C]la {x}`, or a lyric joined to a
  directive by a lone `\r`): other text shares that line, and the parser
  already ignores its invalid value. Such a line is not an occurrence; a new
  directive is inserted instead (found by the T4 review).

**Splice, never re-join.** The write edits the original string in place by
line: a rewritten line keeps its own line terminator, a removed line takes
its terminator with it, and every untouched line keeps its exact bytes. The
line model is the scanner's (`\n` separates lines; a `\r` immediately before
it belongs to a CRLF terminator; a lone `\r` is ordinary line text). An
inserted line uses `\r\n` when the source contains any `\r\n`, otherwise
`\n`. Consequences:

- everything from the boundary onwards is byte-identical before and after
  the write, including mixed line endings;
- a lone-CR source (which the scanner, the parser and the reader already
  treat as one line) gets a new directive on its own `\n`-terminated line,
  so the parser sees it and a repeated tap does not keep inserting lines.

### BD7. In-song directives stay unrendered, with no new diagnostic

Post-boundary `transpose`, `capo` and `key` stay ignored for rendering; S8
owns modulation. No info diagnostic is added: the editor banner counts
diagnostics of every severity and the reader logs every diagnostic, so a
valid song with a key change would start to look broken. They are preserved
by the editor (BD6).

### BD8. Backend `key_signature` keeps its window; the divergence moves

`public.chordpro_scan_directives` (ADR-027) reproduces the parser's old key
window: a lyric line, any `start_of_*` and any `end_of_*` close it; a
directive line inside a tab is swallowed without effect, but `start_of_tab`
itself closes it. It never reproduced the section-comment trigger.

Decision (user, 2026-10-12): the client follows BD2; the server does not
change (no backend change in this slice).

- The old divergence disappears: a section-like comment before `{key}` now
  closes neither side's window.
- The new, accepted divergence: when `{start_of_*}`, `{end_of_*}` or an empty
  tab environment stands before `{key}` (with no lyric line before it), SQL
  derives no key (or an earlier one) while Dart reads the key.
- Why it is accepted: no reader consumes `songs.key_signature` today (the
  catalog pull selects `id, slug, title, version, chordpro_source`; only the
  write RPCs write the column), and a server-side alignment would need a
  tab-content rule in SQL as well.
- Pinned on both sides (C1): the contract test asserts SQL's actual
  behaviour for the divergent sources, and a Dart parity fixture asserts the
  parser's actual behaviour for the same sources. A change on either side
  fails loudly.
- The alignment (migration of the key window with a tab-content rule;
  optional backfill, since ADR-027 rows converge on their next write) is
  deferred: `docs/deferred/2026-10-12-key-signature-window-server-alignment.md`.

### BD9. Unchanged

- No backend or migration change; no stored-data change. Parsing happens at
  read time.
- Reader-local transpose and capo deltas and the session carry-over are
  unchanged (S3 changes them).
- Fit contract: no golden image files exist in the repository. All 27
  reference songs in `docs/examples/chordpro/` were scanned: none changes its
  base values under BD2, so fit and estimate tests must stay green unchanged.
  A fit or layout test that changes for any reason other than a new base
  value is a STOP condition.

### BD10. Optional impact estimate (not a merge gate)

Read-only, for the hosted SQL editor. It over-counts slightly: it treats any
comment as a former closer (only section-like ones were) and ignores tab
nuances.

```sql
with lines as (
  select s.id, l.n, btrim(l.line, E' \t\r') as t
  from public.songs s,
       regexp_split_to_table(replace(s.chordpro_source, E'\r\n', E'\n'), E'\n')
         with ordinality as l(line, n)
),
classified as (
  select id, n,
    case
      when t = '' then 'empty'
      when t ~ '^\{.*\}$' and btrim(substr(t, 2, length(t) - 2)) <> '' then 'directive'
      else 'lyric'
    end as kind,
    lower(btrim(split_part(substr(t, 2, length(t) - 2), ':', 1))) as name
  from lines
),
first_lyric as (
  select id, min(n) as boundary from classified where kind = 'lyric' group by id
)
select count(distinct c.id) as songs_with_newly_read_base_directives
from classified c
left join first_lyric f using (id)
where c.kind = 'directive'
  and c.name in ('key', 'capo', 'transpose')
  and (f.boundary is null or c.n < f.boundary)
  and exists (
    select 1 from classified m
    where m.id = c.id and m.n < c.n and m.kind = 'directive'
      and (m.name in ('comment', 'c')
           or m.name like 'start\_of\_%' or m.name like 'end\_of\_%')
  );
```

## Visible effect

Songs whose base directives come after a section-like comment, a
`{start_of_*}` or an `{end_of_*}` start rendering in the transposed key, with
the capo and with the key, in the reader, the editor preview and the editor
summary alike. In-song `{transpose}` / `{capo}` lines survive every editor
Transpose and Capo tap.

## Acceptance criteria (red tests first)

Scanner (`test/infrastructure/song_library/chordpro/chordpro_line_scanner_test.dart`, new):

- **S1** a lyric line and a chord-only line close the region.
- **S2** `{comment:<Intro>}`, `{c: Verse}`, `{start_of_verse}`,
  `{end_of_verse}`, unknown directives and blank lines do not.
- **S3** inside a tab, the first non-empty line other than `end_of_*` closes
  it, including a directive-shaped line; blank tab lines do not.
- **S4** no content: `boundaryLineNumber` is null and every line is contained.
- **S5** CRLF sources give the same line numbers as LF sources.

Parser (`chordpro_parser_test.dart`):

- **P1** the test that encodes the `{comment:<Verse>}` boundary is rewritten:
  key G, capo 2, transpose 4.
- **P2** base directives after `{start_of_verse}` are read.
- **P3** base directives after `{start_of_chorus}{end_of_chorus}` are read.
- **P4** `{transpose:1}{comment:<Intro>}{transpose:3}` gives 3.
- **P5** an invalid base value after a section comment warns and is ignored.
- **P6** (guard) a `{capo}` after tab content is not base.
- **P7** (guard) in-song transpose, capo and key stay ignored, with no
  diagnostics.

Editor controller (`song_editor_controller_test.dart`):

- **E1** duplicate base directives: the editor shows the last one.
- **E2** `{transpose: x}` then `{transpose: 2}`: the editor shows 2.
- **E3** (B4) the existing "keep pre-lyric directives canonical" test is
  rewritten: in-song `{transpose: 4}` and `{capo: 4}` survive Transpose and
  Capo taps.
- **E4** base plus in-song directive: only the base one changes.
- **E5** a base directive after a section comment is updated in place.
- **E6** base duplicates: the last is rewritten, the others removed.
- **E7** a directive-shaped line inside a tab before the first lyric is
  untouched.
- **E8** parity table: for every fixture source (including one CRLF source
  and one lone-CR source) and after each of the four actions, the editor's
  base transpose, capo and key equal `ChordproParser().parse(source)`'s, the
  text from the boundary onwards is byte-identical, and existing line
  terminators are preserved.

Projections:

- **E9** editor projection: `{comment:<Intro>}{key: G}` gives summary key G.
- **R1** reader projection: `{comment:<Intro>}{transpose: 2}[C]` renders D.

Backend divergence pin:

- **C1** `scripts/tests/song-derived-metadata-contract-test.sh` re-labels the
  section-comment case as parity and asserts the new divergence (SQL's
  actual result for `{start_of_verse}{key: G}`, `{end_of_verse}{key: G}` and
  an empty tab before `{key: G}`); a Dart parity fixture asserts the parser's
  actual result for the same sources. No SQL change.

## Out of scope

- In-song modulation (S8).
- Saved personal transpose and capo (S3).
- The server-side key window (deferred, BD8).
