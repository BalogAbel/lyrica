# Tablet-First ChordPro Song Reader Spec

> Status: Implemented; partially superseded by `docs/specs/2026-03-23-executable-local-supabase-authenticated-song-reading.md`, `docs/specs/2026-03-25-local-first-cached-authenticated-song-reading.md`

## Goal

Deliver the first real Lyron Chords product slice as a tablet-first song reading flow built on ChordPro, using an asset-backed mock catalog and a repository boundary instead of auth or a real backend.

## Scope

- Add a simple song list screen backed by a song repository contract.
- Implement an asset-backed mock song repository for the first song catalog.
- Add a song reader screen for ChordPro-based lyrics and chords.
- Support reader view mode switching between `chords + lyrics` and `lyrics only`.
- Support semitone transpose up/down controls.
- Support shared font scaling that affects both lyrics and chords together.
- Render visible structural sections such as Verse, Chorus, and Bridge.
- Surface non-blocking parse warnings when a song can be rendered only partially or contains unsupported directives.
- Keep detailed parse diagnostics available for developer logging.

## Non-Goals

- No auth flow.
- No real backend integration.
- No local persistence of reader preferences.
- No editing.
- No import flow.
- No raw ChordPro source view.
- No autoscroll.
- No performer mode.
- No FreeShow integration.
- No full ChordPro specification compliance guarantee in this slice.

## Product Slice Summary

This slice validates the core Lyron Chords reading experience before offline sync, backend data flow, or editing are introduced. The user should be able to open the app, see a minimal list of mock songs, open a song, and use a reader optimized for tablet reading distance and touch interaction.

The slice is intentionally balanced rather than parser-heavy or UI-only. It includes a clean ChordPro parsing foundation, but only for an explicit supported subset. It also includes reader controls that prove the UX value of the format without forcing premature decisions about persistence, sync, or collaborative editing.
The first catalog is bundled as app assets so the repository boundary stays real without requiring backend song storage.

## User Flows

### Song List

1. The user opens the app.
2. The app shows a simple list of songs.
3. Each list item displays only the song title.
4. The user selects a title to open the reader.

### Song Reader

1. The reader opens with the parsed song title and available subtitle metadata.
2. The song body is rendered as readable sections and lyric lines, with chords visible by default.
3. The user can switch between `chords + lyrics` and `lyrics only`.
4. The user can transpose the displayed chords down or up in semitone steps.
5. The user can adjust a shared font scale that affects both chord and lyric rendering.
6. If parsing produced warnings but enough structure was recovered to render the song, the user sees a subtle, non-blocking warning indicator.

## Reader UX Requirements

### Layout

- The reader is tablet-first.
- Vertical reading is the primary interaction model.
- Horizontal scrolling must not be the default solution for normal reading.
- The layout should preserve a stable relationship between each chord and its associated lyric segment.
- Minor alignment compromises are acceptable in edge cases if the song remains readable and the chord-to-lyric relationship is still understandable.

### Visual Structure

- Song metadata should appear in a compact header area.
- Structural sections such as Verse, Chorus, and Bridge should be visibly labeled.
- Repeated section numbering such as `Verse 1` and `Chorus 2` should remain visible when present in the source.
- Chorus sections identified by explicit Chorus directives should remain visually distinct from surrounding verses.

### Reader Controls

- View mode toggle:
  - `chords + lyrics`
  - `lyrics only`
- Transpose controls:
  - `-1 semitone`
  - `+1 semitone`
- Font scale controls:
  - decrease shared reading size
  - increase shared reading size

The first slice does not need gesture-heavy controls, presets, or persisted reader preferences.

## ChordPro Support Boundary

### Supported First-Slice Subset

The parser must correctly support the patterns used in the current reference songs and the nearby variants needed to keep the implementation practical:

- Metadata directives:
  - `{title:...}`
  - `{subtitle:...}`
  - `{key:...}`
- Structural directives and conventions:
  - `{comment:<Verse>}`
  - `{comment:<Verse 1>}`
  - `{comment:<Chorus>}`
  - `{comment:<Chorus 1>}`
  - `{comment:<Bridge>}`
  - nearby variants that can be normalized by the parser without expanding into open-ended directive support
- Chorus block markers:
  - `{start_of_chorus}`
  - `{end_of_chorus}`
- Inline chord annotations:
  - `[A]`
  - `[F#m]`
  - `[E/G#]`
  - `[(B)]`
- Empty lines
- Plain lyric lines

### Unsupported Or Unknown Input

- Unknown directives must not stop rendering.
- Unsupported directives should produce parse diagnostics.
- If the parser can recover a usable document, the song should still render.
- Diagnostics should distinguish recoverable warnings from more serious parse errors.
- Detailed diagnostic information should be emitted to logs for developer use.
- The reader UI should summarize recoverable warnings without blocking song playback or reading flow.

### First-Slice Compatibility Rule

This slice supports an explicit, tested ChordPro subset rather than promising full compatibility. New directives or formatting patterns may be added later, but only once they are covered by repository tests and documented behavior.

## Parser And Domain Requirements

### Architectural Requirements

The parser must be designed as a clean, extensible foundation rather than a UI-specific string transformation. The initial implementation should keep these responsibilities separate:

- source loading
- lexical or line-level scanning
- parsing into a song document model
- parse diagnostics
- chord parsing and transposition
- reader-oriented projection or presentation mapping

### Domain Expectations

The parsed song model should preserve:

- song title
- optional subtitle
- optional source key
- ordered song sections
- section labels and numbering when present
- line content as chord-aware lyric data rather than preformatted display strings
- parse diagnostics

### Diagnostic Expectations

Each diagnostic should support enough context to be actionable in logs and tests:

- severity
- message
- line reference
- optional directive or token context

## Chord Handling Requirements

- Transposition must operate on a musical chord model, not by string replacement hacks.
- Displayed chord names should use international note naming.
- Slash chords must be supported.
- Parenthesized chords must be supported.
- The first UI only needs stepwise transpose up/down controls.

The exact enharmonic spelling policy may remain simple in this slice as long as it is consistent and test-covered.

## Data Access Requirements

- Introduce a song repository boundary in the app.
- The repository must provide song list data and song detail/source access.
- The first mock catalog is the three bundled `.pro` assets under `apps/lyron_app/assets/songs/`.
- The repository boundary intentionally returns minimal song summaries plus raw ChordPro source text.
- UI code must not read asset files directly.
- The first song list intentionally remains minimal and shows only titles.
- `SongLibraryService` stays intentionally thin in this slice and only orchestrates repository access.
- Unknown song IDs must fail through a domain-level not-found exception rather than leaking infrastructure errors.

## Proposed Architecture

### Domain Layer

Owns the durable song-reading concepts:

- song metadata
- section model
- chord-aware lyric segments
- chord symbol model
- parse diagnostic model
- repository contract

### Application Layer

Owns orchestration and UI-facing use cases:

- load song list
- load song detail
- adapt parser output into reader results and warning semantics
- keep repository and parser orchestration independent from widget concerns

### Infrastructure Layer

Owns implementations that can change later:

- asset-backed song repository
- ChordPro scanner/parser
- chord transposition service

### Presentation Layer

Owns screens and reader-local UI state:

- song list screen
- song reader screen
- reader state, projection, and local controls
- reader controls
- widget composition for metadata, sections, and lines

## Testing Requirements

TDD is mandatory for this slice.

### Unit Tests

- Parse the existing reference ChordPro files into the expected document structure.
- Verify directive recognition and section normalization.
- Verify recoverable diagnostics for unknown directives.
- Verify chord parsing for major, minor, slash, and parenthesized chords.
- Verify semitone transposition behavior.
- Verify repository behavior for asset-backed song loading.
- Verify full catalog mapping from the three bundled assets.
- Verify each listed song loads the expected asset content for its ID.

### Widget Tests

- Song list renders mock titles.
- Selecting a song opens the reader.
- Reader renders metadata and structural labels.
- View mode toggle hides chords without removing lyrics.
- Transpose controls update displayed chords.
- Font scale controls update reader text sizing.
- Recoverable parse warnings appear as non-blocking UI.

### Integration-Level Coverage

- Route-level flow from song list to reader.
- Basic provider wiring for repository-backed reading flow.

## Risks

- ChordPro input variability can cause scope creep if the supported subset is not enforced explicitly.
- Flutter text layout may produce imperfect alignment in some wrapped lines.
- Section extraction from `comment` directives depends on conventions rather than a universal source of truth.
- Enharmonic spelling expectations may later require a richer notation policy than the first slice needs.

## Deferred Decisions

- Full ChordPro compatibility policy
- Import validation UX
- Reader preference persistence
- Editing model
- Offline caching and sync behavior for songs
- Backend song storage contract
- FreeShow runtime integration
- Autoscroll and performer mode
- More advanced transpose UX such as direct key selection

## Success Criteria

- The app ships a mock-backed song list and a usable tablet-first song reader.
- The three reference songs render correctly within the supported subset.
- The reader supports view mode switching, semitone transposition, and shared font scaling.
- Structural sections are visible and readable.
- Unknown directives produce diagnostics without blocking rendering.
- The implementation leaves a clean parser and repository foundation for later slices.
