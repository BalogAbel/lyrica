# Song Reader ChordPro Modulation Deferred Work

Originating slice:
- `docs/specs/2026-04-22-song-reader-capo-and-instrument-display.md`
- `docs/plans/2026-04-22-song-reader-capo-and-instrument-display.md`

## Status

Deferred.

## Deferred Item

### Support in-song `{transpose: ...}` modulation after song start

This deferred item only covers in-song ChordPro `transpose` modulation after song start.

Later transpose changes inside the song body are still unsupported. When that work is resumed, it must cover:

- parser support for modulation directives in song flow
- projection behavior that changes sounding chords from the modulation point onward
- UI behavior that makes the active transpose state understandable while reading

Do not silently infer modulation support from the current global-only reader slice. Keep this gap visible until a dedicated slice closes it.

Since S2 (`docs/specs/2026-10-12-chordpro-base-directives.md`) the editor
preserves in-song `{transpose}` and `{capo}` lines byte-for-byte (BD6): a
Transpose or Capo tap only touches directives in the base region. In-song
transpose, capo and key are still not rendered and produce no diagnostic (BD7).
S8 therefore starts from intact source.

## Planning Note

Any future slice that changes ChordPro transpose semantics must update this note in the same change set. The current reader contract is global-only transpose plus reader-local delta controls, not full modulation-aware parsing.

## Roadmap (2026-10-01)

`docs/plans/2026-10-01-delivery-roadmap.md` schedules the remaining item:

- **Base transpose/capo alignment (former item 1) was slice S2**
  (`fix/chordpro-base-directives`) and is resolved by
  `docs/specs/2026-10-12-chordpro-base-directives.md`: one base-region
  predicate now serves the parser, the editor read and the editor write. S3
  depends on it: S3 saves per-user transpose and capo and needs one
  consistent base for them.
- **In-song modulation is slice S8** (`feat/chordpro-modulation`).
  - It follows S2.
  - It must not run in parallel with S3 or S4, because both also change
    `SongReaderProjection`.
  - Personal transpose from S3 applies as a global offset on top of any
    in-song modulation.
