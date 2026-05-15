# ChordPro Parser & Rendering Improvements

**Date:** 2026-05-15
**Branch:** `feat/chordpro-parser-rendering-improvements`
**Status:** Draft

## Context

The app uses ChordPro as its song format. The current parser covers a minimal subset of the ChordPro standard. This spec extends it to cover the full directive set, standard aliases, and graceful rendering of unrecognized content.

---

## Goals

- Align the parser with the ChordPro standard (directives, aliases, section blocks)
- Render unrecognized content visibly rather than silently dropping it
- Normalize raw source to canonical form on every save

---

## Data Model Changes

### `SongLine` → sealed class

`SongLine` becomes a sealed class with four variants:

```dart
sealed class SongLine {}

class LyricLine extends SongLine {
  final List<LyricSegment> segments;
}

class CommentLine extends SongLine {
  final String text;
}

class TabBlock extends SongLine {
  final List<String> rawLines;
}

class DirectiveLine extends SongLine {
  final String name;
  final String? value;
}
```

`LyricLine` replaces the current `SongLine(segments: ...)` constructor. All consumers update to exhaustive `switch`.

### `SongSectionKind` — new values

```dart
enum SongSectionKind { verse, chorus, bridge, other, unknown, tab }
```

- `unknown` — section with an unrecognized label (e.g. `<PreChorus>`, `<Instrumental>`)
- `tab` — `{start_of_tab}` block

### Preamble section

When unknown directives or comment lines appear before the first named section, the parser collects them into a synthetic preamble section (`kind: other`, no label, no header rendered). This preserves position without moving content.

### `ParsedSong` — no new top-level directive field

Unknown directives are represented as `DirectiveLine` instances inside sections (or the preamble section). No separate top-level list.

---

## ChordproNormalizer

New class: `ChordproNormalizer`. Applied on every save (create and edit), before writing `chordpro_source` to the database. Pure string transformation, line by line.

### Alias → canonical mappings

| Alias | Canonical |
|---|---|
| `{t:}` | `{title:}` |
| `{st:}` | `{subtitle:}` |
| `{c:}` | `{comment:}` |
| `{soc}` / `{soc: label}` | `{start_of_chorus}` / `{start_of_chorus: label}` |
| `{eoc}` | `{end_of_chorus}` |
| `{sov}` / `{eov}` | `{start_of_verse}` / `{end_of_verse}` |
| `{sob}` / `{eob}` | `{start_of_bridge}` / `{end_of_bridge}` |
| `{sot}` / `{eot}` | `{start_of_tab}` / `{end_of_tab}` |

The normalizer runs on save so stored source is always canonical. The parser also accepts aliases for robustness (e.g. when source arrives from an external sync before being re-saved).

---

## Parser Changes

### New directives

| Directive | Result |
|---|---|
| `{start_of_verse}` / `{end_of_verse}` | `SongSectionKind.verse` |
| `{start_of_bridge}` / `{end_of_bridge}` | `SongSectionKind.bridge` |
| `{start_of_tab}` / `{end_of_tab}` | `SongSectionKind.tab`, lines become `TabBlock` |
| `{start_of_<anything>}` | `SongSectionKind.unknown`, label = `<anything>` |
| `{start_of_chorus: Label}` | chorus section with label override |
| `{start_of_verse: Label}` | verse section with label override |
| `{tag:}` | alias for `{tags:}` |
| `{meta: key value}` | ignored silently (no warning) |

### `{comment:}` directive — full behaviour

| Comment value | Result |
|---|---|
| Matches section pattern (`<Verse>`, `<Chorus>`, `[Bridge]`, etc.) | Section header (current behaviour) |
| `//` prefix or `#` prefix | `CommentLine` |
| Any other non-section text | `CommentLine` |

### Section label normalization fixes

| Problem | Fix |
|---|---|
| `<Verse1>` no-match | Regex: `^([A-Za-z]+)\s*(\d+)?$` (space optional before digit) |
| `<Bridge 1>` → null (bridge numbering disallowed) | Allow numbered bridge |
| Any non-standard label (`PreChorus`, `Instrumental`, `Interlude`, `Outro`, etc.) → null | `SongSectionKind.unknown`, label = raw normalized text |
| Any other unrecognized label | `SongSectionKind.unknown`, label = raw text |

### Unknown directives

Directives not handled by any case (e.g. app-specific extensions, `{x_...}` custom directives) become `DirectiveLine(name, value)` inside the current section or preamble. No warning generated.

---

## Projection Changes

### `SongReaderSectionProjection`

New field: `isUnknown: bool` — set when `SongSectionKind.unknown`. Used by header widget to select color.

### New projection types

```dart
class SongReaderCommentProjection { final String text; }
class SongReaderTabProjection     { final List<String> rawLines; }
class SongReaderDirectiveProjection { final String name; final String? value; }
```

`SongReaderLineProjection` (existing) remains for `LyricLine`. The projection maps each `SongLine` variant to its corresponding projection type.

---

## UI Changes

### Unknown section header

`isUnknown: true` → header label rendered in `colorScheme.tertiary` instead of `colorScheme.primary`. Label text is the raw normalized label (e.g. "PreChorus", "Instrumental").

### CommentLine widget

- Italic text
- Color: `colorScheme.onSurface.withOpacity(0.6)`
- Smaller font than lyric rows
- Left-aligned, no chord row above it

### TabBlock widget

- Monospace font
- Background: `colorScheme.surfaceVariant` with inner padding
- Horizontally scrollable (tab ASCII can exceed screen width)
- Rendered as a single block within the section

### DirectiveLine widget

- Same visual style as the existing capo `_DirectiveLine`
- Color: `colorScheme.tertiary`
- Format: `{name: value}` or `{name}` if no value

---

## Affected Files

| File | Change |
|---|---|
| `domain/song/song_line.dart` | sealed class refactor |
| `domain/song/song_section.dart` | `SongSectionKind` new values |
| `domain/song/parsed_song.dart` | no structural change (preamble is a regular section) |
| `infrastructure/song_library/chordpro/chordpro_parser.dart` | all parser fixes |
| `infrastructure/song_library/chordpro/chordpro_normalizer.dart` | new class |
| `presentation/song_reader/song_reader_projection.dart` | new projection types |
| `presentation/song_reader/widgets/song_reader_section_grid.dart` | `isUnknown` color + height calc |
| `presentation/song_reader/widgets/song_section_view.dart` | CommentLine, TabBlock, DirectiveLine widgets |
| Save layer (song editor + import) | normalizer call before DB write |

---

## Out of Scope

- Chord diagram / `{define:}` rendering
- `{column_break}` / `{new_page}` layout directives
- Chorus repeat marker `{chorus}`
- Conditional directives (`{ifdef:}` etc.)
