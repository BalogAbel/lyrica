# ChordPro Base Directive Residuals

Originating slice:
- `docs/specs/2026-10-12-chordpro-base-directives.md` (S2)
- `docs/plans/2026-10-12-chordpro-base-directives.md`

## Status

Deferred. Non-blocking findings of the S2 final adversarial review. None of
them lets the editor and the reader disagree on a base value, and none
touches a line at or after the base boundary.

## R1. A lone-CR line without braces can still be rewritten whole

`_isSingleDirective` (`song_editor_controller.dart`) treats a base-region
directive line as rewritable when its value holds no brace. A line such as
`{transpose: 2\rLyric text}` (a lone `\r` inside the braces) passes, and a
Transpose tap rewrites it to `{transpose: N}`, dropping `Lyric text`. The
parser already ignores that line's invalid value, and the text is not
rendered by the reader. Contrived: it needs a lone CR inside a directive.

Fix sketch: also refuse values that contain `\r`, or that `int.tryParse`
rejects after trim, and insert a new directive instead.

## R2. Rewriting a base directive drops its leading BOM and indentation

The kept occurrence is replaced by `{name: value}`, so a leading U+FEFF or
leading whitespace on that line is lost. Cosmetic; the parser trims both.

Fix sketch: keep the prefix up to the first `{` of the original record.

## R3. Transpose has no range clamp

`transposeUp` on `{transpose: 9223372036854775807}` wraps to the minimum
`int` on native; on web `int.tryParse` loses precision earlier. Capo is
clamped at 0 only. Real songs stay within a few semitones.

Fix sketch: clamp the written transpose to a musical range (for example
±24) in the editor, and let the parser warn outside it. S3 should pick the
same bound for saved personal transpose.

## R4. A whitespace-only source is replaced wholesale

`_upsertDirective` returns the directive alone when `source.trim()` is
empty, so a source of only spaces or line breaks loses them. Harmless; kept
from the pre-S2 behaviour.

## Trigger

The next change to the song editor's directive write path, or S3 (R3's
bound), whichever comes first.
