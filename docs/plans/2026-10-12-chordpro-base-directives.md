# Plan: ChordPro Base Directives

> Status: Accepted (2026-10-12). Executing on `fix/chordpro-base-directives`.

- Spec: `docs/specs/2026-10-12-chordpro-base-directives.md` (BD1–BD10,
  S/P/E/R/C acceptance criteria)
- Branch: `fix/chordpro-base-directives` (from `main` at `0390d79`)
- Execution: subagent-driven. Implementer Sonnet 5.5 per task, task review
  Haiku 4.5. One adversarial Opus 5.5 whole-diff review before the PR.
- Every task: red test first, then `flutter test` (full suite) and
  `flutter analyze` from `apps/lyron_app`. A failing dependency audit is
  fixed in a separate `chore(deps)` commit with a targeted
  `flutter pub upgrade <pkg>`.

## STOP-and-report conditions

- A fit, estimate, layout or reader-surface test changes for any reason
  other than a new base value (BD9).
- Rewriting the contract test would need an SQL change (BD8).
- A design needs a backend change, a stored-data change, or a change to the
  reader-local deltas or the session carry-over.

## Tasks

### T1. `ChordproBaseRegion` (BD1, BD2)

Files: `lib/src/infrastructure/song_library/chordpro/chordpro_line_scanner.dart`,
new `test/infrastructure/song_library/chordpro/chordpro_line_scanner_test.dart`.

- Red: S1–S5.
- Implement `ChordproBaseRegion.of(lines)` with a single pass: track
  `inTab` (`start_of_tab` enters; any `end_of_*` leaves); the first line that
  is lyric-kind, or non-empty inside a tab and not `end_of_*`, is the
  boundary. `contains(line)` is `boundary == null || line.lineNumber <
  boundary`.

### T2. Parser reads base values through the region (BD2–BD4, BD7)

Files: `chordpro_parser.dart`, `chordpro_parser_test.dart`,
`test/presentation/song_reader/song_reader_projection_test.dart`.

- Red: P1–P5, R1 (parse a source, then project). P6, P7 are guards (green
  before and after).
- Scan once into a list, build the region, and replace every
  `hasSeenSongContent` gate with `region.contains(line)`. Remove the flag and
  its three setters. Diagnostics and value rules are unchanged.
- Dart side of C1: a `group('ADR-027 key-window parity fixture')` in the
  parser test that asserts the parser's actual `sourceKey` for exactly the
  sources the contract test pins (section comment before key: G, parity;
  `{start_of_verse}` / `{end_of_verse}` / empty tab before key: G, divergent
  from SQL's null; tab content before key: null, parity). Each case names the
  matching contract-test check.

### T3. Editor reads from the parser (BD5)

Files: `song_editor_state.dart`, delete `song_editor_directives.dart`,
`song_editor_controller_test.dart`, `song_editor_projection_test.dart`.

- Red: E1, E2, E9.
- `_parseSongEditorSource` takes `baseTranspose` and `baseCapo` from the
  parsed song. The controller reads `_state.parsedSong.baseTranspose` /
  `baseCapo` instead of `currentPreLyricDirectiveInt` (write logic unchanged
  in this task).

### T4. Editor write touches only the base region (BD6)

Files: `song_editor_controller.dart`, `song_editor_controller_test.dart`.

- Red: E3 (rewrite the existing deletion-asserting test), E4–E7, E8 parity
  table (LF, CRLF, mixed, lone-CR fixtures; all four actions; base values
  equal the parser's; suffix from the boundary byte-identical; terminators
  kept).
- Implementation shape:
  - split the source into line records `(text, terminator)` with the
    scanner's model (`\n` separates; a preceding `\r` makes the terminator
    `\r\n`; the last line may have none). Record N is scanner line N;
  - scan the same source once, build `ChordproBaseRegion`;
  - occurrences = scanned directive lines with the target name that the
    region contains;
  - non-empty: replace the text of the last record, drop the other
    occurrence records (with their terminators);
  - empty: compute the insertion record index from the scanned lines and the
    region (leading metadata block rule, stop at the first non-metadata
    directive or the boundary) and insert `directive + eol`
    (`eol` = `\r\n` if the source contains `\r\n`, else `\n`); at the end of
    a source whose last line has no terminator, give that line `eol` first;
    an empty source becomes the directive alone;
  - concatenate the records. Records at or after the boundary are never
    edited.
- Delete `_firstLyricLineIndex`, the regex, `_detectLineEnding`'s lone-CR
  branch, and the per-line `ChordproLineScanner().scan(trimmed)` call.

### T5. Contract-test divergence pin and docs (BD8, C1)

Files: `scripts/tests/song-derived-metadata-contract-test.sh`,
`docs/architecture/decisions/ADR-027-backend-derived-song-metadata.md`,
`docs/testing/testing-strategy.md`,
new `docs/deferred/2026-10-12-key-signature-window-server-alignment.md`,
`docs/deferred/2026-04-22-song-reader-chordpro-modulation.md`,
`docs/specs/2026-04-22-song-reader-capo-and-instrument-display.md` (status
note), `docs/architecture/architecture.md` if it describes the boundary,
roadmap S2 row.

- Contract test: re-label the `{c: Verse}` case as parity (both sides read
  G since S2); re-label the existing `start_of_*` / `end_of_*` key-window
  cases as the accepted divergence; add an empty-tab-before-key divergence
  case and a tab-content-before-key parity case. Assertions describe SQL's
  actual behaviour; no SQL change. Run `./scripts/backend-write-contracts.sh`
  locally (Docker Desktop).
- ADR-027: rewrite "Known divergence" (old one gone, new one with its
  rationale and the C1 pins on both sides).
- Modulation deferred doc: remove item 1; item 2 records that the editor
  preserves in-song directives (BD6).

## Final review

One Opus 5.5 adversarial whole-diff review. Claim to disprove: "for the same
source, the editor and the reader can show a different base transpose, capo
or key, or an editor action can delete or change a directive after the first
lyric line." Blocking: that claim, or a fit or golden change not explained by
a new base value. At most one fix round; everything else is deferred with a
doc.
