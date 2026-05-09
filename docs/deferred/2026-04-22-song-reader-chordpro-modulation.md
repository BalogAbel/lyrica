# Song Reader ChordPro Modulation Deferred Work

Originating slice:
- `docs/specs/2026-04-22-song-reader-capo-and-instrument-display.md`
- `docs/plans/2026-04-22-song-reader-capo-and-instrument-display.md`

## Status

Deferred.

## Deferred Item

### Align base transpose/capo parsing with ChordPro semantics

The song editor currently reads base `{transpose: ...}` and `{capo: ...}` values
from the canonical source until the first lyric line. The song reader uses the
shared ChordPro parser, which currently treats section-like `{comment:<Intro>}`
directives as song content and therefore ignores later base transpose/capo
directives.

This creates a visible mismatch:

```chordpro
{comment:<Intro>}
{transpose: 2}
{capo: 3}
[A] [C#m/G#]
```

The editor derives `Transpose +2` and `Capo 3`, while the reader can start from
`Transpose 0` and `Capo 0`.

Future work should align parser, editor, and reader behavior with ChordPro
semantics:

- `comment` is printed comment/instruction content, not lyric/chord content.
- ChordPro environments such as `{start_of_verse}` group song lines, but the
  base settings boundary should not be closed by a label-like marker alone.
- Base `{transpose: ...}` and `{capo: ...}` should be read consistently before
  the first actual lyric/chord line.
- The editor should use the same parser-derived base values as the reader
  instead of maintaining separate directive-scanning logic.
- The slice must update parser tests that currently encode the stricter
  `{comment:<Verse>}` boundary behavior.

### Support in-song `{transpose: ...}` modulation after song start

This deferred item only covers in-song ChordPro `transpose` modulation after song start.

Later transpose changes inside the song body are still unsupported. When that work is resumed, it must cover:

- parser support for modulation directives in song flow
- projection behavior that changes sounding chords from the modulation point onward
- UI behavior that makes the active transpose state understandable while reading

Do not silently infer modulation support from the current global-only reader slice. Keep this gap visible until a dedicated slice closes it.

## Planning Note

Any future slice that changes ChordPro transpose semantics must update this note in the same change set. The current reader contract is global-only transpose plus reader-local delta controls, not full modulation-aware parsing.
