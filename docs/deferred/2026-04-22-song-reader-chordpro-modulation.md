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

## Planning Note

Any future slice that changes ChordPro transpose semantics must update this note in the same change set. The current reader contract is global-only transpose plus reader-local delta controls, not full modulation-aware parsing.
