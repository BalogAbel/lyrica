# ChordPro Parser & Rendering Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the ChordPro parser to cover the full standard directive set, normalize aliases on save, and render unrecognized content visibly instead of silently dropping it.

**Architecture:** Seal `SongLine` into four variants (`LyricLine`, `CommentLine`, `TabBlock`, `DirectiveLine`), add `SongSectionKind.unknown/tab`, introduce a `ChordproNormalizer` that runs at save time, extend the parser to handle all standard directives, add new projection types, and wire up new rendering widgets.

**Tech Stack:** Dart, Flutter, flutter_test, existing `ChordproParser` / `SongReaderProjection` / `SongLibraryService` architecture.

**Spec:** `docs/specs/2026-05-15-chordpro-parser-rendering-improvements.md`

---

## File Map

**Create:**
- `apps/lyron_app/lib/src/infrastructure/song_library/chordpro/chordpro_normalizer.dart`
- `apps/lyron_app/test/infrastructure/song_library/chordpro/chordpro_normalizer_test.dart`
- `apps/lyron_app/lib/src/presentation/song_reader/widgets/comment_line_view.dart`
- `apps/lyron_app/lib/src/presentation/song_reader/widgets/tab_block_view.dart`
- `apps/lyron_app/lib/src/presentation/song_reader/widgets/directive_line_view.dart`

**Modify:**
- `apps/lyron_app/lib/src/domain/song/song_line.dart`
- `apps/lyron_app/lib/src/domain/song/song_section.dart`
- `apps/lyron_app/lib/src/infrastructure/song_library/chordpro/chordpro_parser.dart`
- `apps/lyron_app/lib/src/application/song_library/song_library_service.dart`
- `apps/lyron_app/lib/src/presentation/song_reader/song_reader_projection.dart`
- `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_section_view.dart`
- `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_line_view.dart`
- `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_section_grid.dart`
- `apps/lyron_app/test/infrastructure/song_library/chordpro/chordpro_parser_test.dart`
- `apps/lyron_app/test/infrastructure/song_library/chordpro/chordpro_diagnostics_test.dart`

---

## Task 1: Seal SongLine

**Files:**
- Modify: `apps/lyron_app/lib/src/domain/song/song_line.dart`
- Modify: `apps/lyron_app/lib/src/infrastructure/song_library/chordpro/chordpro_parser.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_projection.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_section_grid.dart`
- Modify: `apps/lyron_app/test/infrastructure/song_library/chordpro/chordpro_parser_test.dart`

- [ ] **Step 1: Write a failing test asserting LyricLine exists**

Add to `chordpro_parser_test.dart` after the existing tests:

```dart
test('parsed lyric lines are LyricLine instances', () {
  final parser = ChordproParser();
  final song = parser.parse('{title:T}\n{comment:<Verse>}\n[A]Hello\n');
  expect(song.sections.single.lines.single, isA<LyricLine>());
});
```

- [ ] **Step 2: Run to confirm it fails**

```bash
cd apps/lyron_app && flutter test test/infrastructure/song_library/chordpro/chordpro_parser_test.dart
```

Expected: compile error — `LyricLine` not defined.

- [ ] **Step 3: Replace song_line.dart with sealed class**

```dart
import 'package:lyron_app/src/domain/song/lyric_segment.dart';

sealed class SongLine {}

class LyricLine extends SongLine {
  LyricLine({required List<LyricSegment> segments})
      : segments = List.unmodifiable(segments);

  final List<LyricSegment> segments;

  @override
  bool operator ==(Object other) =>
      other is LyricLine && _listEquals(other.segments, segments);

  @override
  int get hashCode => Object.hashAll(segments);
}

class CommentLine extends SongLine {
  const CommentLine({required this.text});
  final String text;

  @override
  bool operator ==(Object other) => other is CommentLine && other.text == text;

  @override
  int get hashCode => text.hashCode;
}

class TabBlock extends SongLine {
  TabBlock({required List<String> rawLines})
      : rawLines = List.unmodifiable(rawLines);
  final List<String> rawLines;

  @override
  bool operator ==(Object other) =>
      other is TabBlock && _listEquals(other.rawLines, rawLines);

  @override
  int get hashCode => Object.hashAll(rawLines);
}

class DirectiveLine extends SongLine {
  const DirectiveLine({required this.name, this.value});
  final String name;
  final String? value;

  @override
  bool operator ==(Object other) =>
      other is DirectiveLine && other.name == name && other.value == value;

  @override
  int get hashCode => Object.hash(name, value);
}

bool _listEquals<T>(List<T> left, List<T> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}
```

- [ ] **Step 4: Update chordpro_parser.dart — SongLine → LyricLine**

In `chordpro_parser.dart`, change every `SongLine(segments: ...)` to `LyricLine(segments: ...)`. There are two occurrences:

Line ~28 (empty line handler):
```dart
currentSection.lines.add(LyricLine(segments: const [LyricSegment(text: '')]));
```

Line ~39 (lyric line handler):
```dart
currentSection.lines.add(LyricLine(segments: _parseLyricLine(line.raw)));
```

The `_SectionBuilder` class field stays `List<SongLine>` (the sealed base). No other change needed here yet.

- [ ] **Step 5: Update song_reader_projection.dart — add _projectLine helper**

Replace the inner `section.lines.map(...)` lambda with a call to a top-level helper. Add at the bottom of `song_reader_projection.dart` (after all classes):

```dart
SongReaderLineProjection _projectLine(
  SongLine line,
  SongReaderState state,
  ParsedSong song,
  SongChordTransposer transposeChord,
) {
  return switch (line) {
    LyricLine() => SongReaderLineProjection(
        segments: List.unmodifiable(
          line.segments
              .map(
                (segment) => SongReaderSegmentProjection(
                  displayChord: SongReaderProjection._displayChord(
                    segment.leadingChord,
                    state,
                    song,
                    transposeChord,
                  ),
                  text: segment.text,
                ),
              )
              .toList(growable: false),
        ),
      ),
    CommentLine() || TabBlock() || DirectiveLine() =>
      SongReaderLineProjection(segments: const []),
  };
}
```

In the `SongReaderProjection` constructor initializer, replace the current `section.lines.map(...)` block with:

```dart
lines: List.unmodifiable(
  section.lines
      .map((line) => _projectLine(line, state, song, transposeChord))
      .toList(growable: false),
),
```

Make `_displayChord` accessible by changing it from `static String? _displayChord` to just keeping it static (it already is static, but the top-level `_projectLine` calls it as `SongReaderProjection._displayChord`). That compiles because it is a static method.

- [ ] **Step 6: Update song_reader_section_grid.dart — switch in _estimatedSectionHeight**

Replace the `for (final line in section.lines)` loop body:

```dart
for (final line in section.lines) {
  switch (line) {
    case SongReaderLineProjection():
      final text = line.segments.map((segment) => segment.text).join();
      final lyricLength = text.trimRight().length;
      final hasChord =
          viewMode == SongReaderViewMode.chordsAndLyrics &&
          line.segments.any((segment) => segment.displayChord != null);
      final wrapCount = lyricLength == 0
          ? 1
          : (lyricLength / charsPerLine).ceil().clamp(1, 14);
      final chordRowHeight =
          hasChord ? (_chordRowHeight * sharedFontScale) : 0;
      final lyricRowsHeight = wrapCount * (_lyricRowHeight * sharedFontScale);
      linesHeight += chordRowHeight + lyricRowsHeight + _lineGap;
  }
}
```

Wait — at this stage `section.lines` is still `List<SongReaderLineProjection>` (no new types yet). The switch is a no-op for now but future-proofs the structure. Leave this step for Task 8 — the existing code still compiles since all lines are `SongReaderLineProjection`.

Actually, no change needed in `song_reader_section_grid.dart` for Task 1. The type of `section.lines` stays `List<SongReaderLineProjection>` until Task 8.

- [ ] **Step 7: Update existing parser tests to use LyricLine**

In `chordpro_parser_test.dart`, the tests access `line.segments` directly. Change every `song.sections[x].lines[y].segments` access to cast first:

```dart
// Before:
expect(song.sections[0].lines[0].segments, hasLength(2));
expect(song.sections[0].lines[0].segments[0].leadingChord, 'A');

// After:
final line0 = song.sections[0].lines[0] as LyricLine;
expect(line0.segments, hasLength(2));
expect(line0.segments[0].leadingChord, 'A');
```

Apply this pattern throughout the test file wherever `.segments` is accessed directly on a line.

- [ ] **Step 8: Run full test suite**

```bash
cd apps/lyron_app && flutter test
```

Expected: all tests pass.

- [ ] **Step 9: Commit**

```bash
git add apps/lyron_app/lib/src/domain/song/song_line.dart \
        apps/lyron_app/lib/src/infrastructure/song_library/chordpro/chordpro_parser.dart \
        apps/lyron_app/lib/src/presentation/song_reader/song_reader_projection.dart \
        apps/lyron_app/test/infrastructure/song_library/chordpro/chordpro_parser_test.dart
git commit -m "refactor: seal SongLine into LyricLine/CommentLine/TabBlock/DirectiveLine variants"
```

---

## Task 2: SongSectionKind — add unknown and tab

**Files:**
- Modify: `apps/lyron_app/lib/src/domain/song/song_section.dart`
- Modify: `apps/lyron_app/test/infrastructure/song_library/chordpro/chordpro_parser_test.dart`

- [ ] **Step 1: Write a failing test for new enum values**

Add to `chordpro_parser_test.dart`:

```dart
test('SongSectionKind has unknown and tab values', () {
  expect(SongSectionKind.values, contains(SongSectionKind.unknown));
  expect(SongSectionKind.values, contains(SongSectionKind.tab));
});
```

- [ ] **Step 2: Run to confirm it fails**

```bash
cd apps/lyron_app && flutter test test/infrastructure/song_library/chordpro/chordpro_parser_test.dart --name "SongSectionKind has"
```

Expected: compile error — `SongSectionKind.unknown` not defined.

- [ ] **Step 3: Add new values to enum**

In `song_section.dart`, change:

```dart
enum SongSectionKind { verse, chorus, bridge, other }
```

to:

```dart
enum SongSectionKind { verse, chorus, bridge, other, unknown, tab }
```

- [ ] **Step 4: Run tests**

```bash
cd apps/lyron_app && flutter test
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add apps/lyron_app/lib/src/domain/song/song_section.dart \
        apps/lyron_app/test/infrastructure/song_library/chordpro/chordpro_parser_test.dart
git commit -m "feat: add SongSectionKind.unknown and .tab enum values"
```

---

## Task 3: ChordproNormalizer

**Files:**
- Create: `apps/lyron_app/lib/src/infrastructure/song_library/chordpro/chordpro_normalizer.dart`
- Create: `apps/lyron_app/test/infrastructure/song_library/chordpro/chordpro_normalizer_test.dart`

- [ ] **Step 1: Write failing tests**

Create `apps/lyron_app/test/infrastructure/song_library/chordpro/chordpro_normalizer_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/infrastructure/song_library/chordpro/chordpro_normalizer.dart';

void main() {
  final normalizer = ChordproNormalizer();

  group('title aliases', () {
    test('{t: value} becomes {title: value}', () {
      expect(normalizer.normalize('{t: My Song}'), '{title: My Song}');
    });

    test('{st: value} becomes {subtitle: value}', () {
      expect(normalizer.normalize('{st: Sub}'), '{subtitle: Sub}');
    });

    test('{c: text} becomes {comment: text}', () {
      expect(normalizer.normalize('{c: text}'), '{comment: text}');
    });
  });

  group('chorus aliases', () {
    test('{soc} becomes {start_of_chorus}', () {
      expect(normalizer.normalize('{soc}'), '{start_of_chorus}');
    });

    test('{eoc} becomes {end_of_chorus}', () {
      expect(normalizer.normalize('{eoc}'), '{end_of_chorus}');
    });

    test('{soc: My Chorus} becomes {start_of_chorus: My Chorus}', () {
      expect(
        normalizer.normalize('{soc: My Chorus}'),
        '{start_of_chorus: My Chorus}',
      );
    });
  });

  group('verse aliases', () {
    test('{sov} becomes {start_of_verse}', () {
      expect(normalizer.normalize('{sov}'), '{start_of_verse}');
    });

    test('{eov} becomes {end_of_verse}', () {
      expect(normalizer.normalize('{eov}'), '{end_of_verse}');
    });
  });

  group('bridge aliases', () {
    test('{sob} becomes {start_of_bridge}', () {
      expect(normalizer.normalize('{sob}'), '{start_of_bridge}');
    });

    test('{eob} becomes {end_of_bridge}', () {
      expect(normalizer.normalize('{eob}'), '{end_of_bridge}');
    });
  });

  group('tab aliases', () {
    test('{sot} becomes {start_of_tab}', () {
      expect(normalizer.normalize('{sot}'), '{start_of_tab}');
    });

    test('{eot} becomes {end_of_tab}', () {
      expect(normalizer.normalize('{eot}'), '{end_of_tab}');
    });
  });

  test('non-directive lines are unchanged', () {
    const source = '[A]Hello [Bm]world\n';
    expect(normalizer.normalize(source), source);
  });

  test('unknown directives are unchanged', () {
    const source = '{zoom-ipad: 1.9}\n';
    expect(normalizer.normalize(source), source);
  });

  test('canonical directives are unchanged', () {
    const source = '{title: My Song}\n{start_of_chorus}\n';
    expect(normalizer.normalize(source), source);
  });

  test('normalizes multi-line source', () {
    expect(
      normalizer.normalize('{t: My Song}\n{soc}\n[A]Hello\n{eoc}\n'),
      '{title: My Song}\n{start_of_chorus}\n[A]Hello\n{end_of_chorus}\n',
    );
  });

  test('case insensitive alias matching', () {
    expect(normalizer.normalize('{SOC}'), '{start_of_chorus}');
    expect(normalizer.normalize('{T: My Song}'), '{title: My Song}');
  });
}
```

- [ ] **Step 2: Run to confirm all fail**

```bash
cd apps/lyron_app && flutter test test/infrastructure/song_library/chordpro/chordpro_normalizer_test.dart
```

Expected: compile error — `ChordproNormalizer` not defined.

- [ ] **Step 3: Implement ChordproNormalizer**

Create `apps/lyron_app/lib/src/infrastructure/song_library/chordpro/chordpro_normalizer.dart`:

```dart
class ChordproNormalizer {
  static final _aliasPattern = RegExp(
    r'^\s*\{([A-Za-z][A-Za-z0-9_-]*)(:[^}]*)?\}\s*$',
  );

  static const _aliases = <String, String>{
    't': 'title',
    'st': 'subtitle',
    'c': 'comment',
    'soc': 'start_of_chorus',
    'eoc': 'end_of_chorus',
    'sov': 'start_of_verse',
    'eov': 'end_of_verse',
    'sob': 'start_of_bridge',
    'eob': 'end_of_bridge',
    'sot': 'start_of_tab',
    'eot': 'end_of_tab',
  };

  String normalize(String source) {
    final lines = source.split('\n');
    final result = StringBuffer();
    for (var i = 0; i < lines.length; i++) {
      result.write(_normalizeLine(lines[i]));
      if (i < lines.length - 1) result.write('\n');
    }
    return result.toString();
  }

  String _normalizeLine(String line) {
    final match = _aliasPattern.firstMatch(line);
    if (match == null) return line;
    final name = match.group(1)!.toLowerCase();
    final rest = match.group(2) ?? '';
    final canonical = _aliases[name];
    if (canonical == null) return line;
    return '{$canonical$rest}';
  }
}
```

- [ ] **Step 4: Run tests**

```bash
cd apps/lyron_app && flutter test test/infrastructure/song_library/chordpro/chordpro_normalizer_test.dart
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add apps/lyron_app/lib/src/infrastructure/song_library/chordpro/chordpro_normalizer.dart \
        apps/lyron_app/test/infrastructure/song_library/chordpro/chordpro_normalizer_test.dart
git commit -m "feat: add ChordproNormalizer to canonicalize ChordPro directive aliases"
```

---

## Task 4: Normalizer injection in SongLibraryService

**Files:**
- Modify: `apps/lyron_app/lib/src/application/song_library/song_library_service.dart`
- Modify: `apps/lyron_app/test/application/song_library/song_library_service_test.dart`

- [ ] **Step 1: Write a failing test asserting source is normalized on create**

Add to `song_library_service_test.dart`:

```dart
test('create normalizes chordpro source aliases before storing', () async {
  final repository = _FakeSongRepository();
  final service = SongLibraryService(repository, repository);

  await service.createSong(
    context: const ActiveCatalogContext(
      userId: 'user-1',
      organizationId: 'org-1',
    ),
    title: 'Test',
    chordproSource: '{t: Test}\n{soc}\n[A]Hello\n{eoc}\n',
  );

  expect(
    repository.lastUpsertedRecord?.chordproSource,
    '{title: Test}\n{start_of_chorus}\n[A]Hello\n{end_of_chorus}\n',
  );
});

test('update normalizes chordpro source aliases before storing', () async {
  final repository = _FakeSongRepository();
  repository.songById = const SongMutationRecord(
    id: 'song-1',
    organizationId: 'org-1',
    slug: 'test',
    title: 'Test',
    chordproSource: '{title: Test}',
    version: 1,
    baseVersion: 1,
    syncStatus: SongSyncStatus.synced,
  );
  final service = SongLibraryService(repository, repository);

  await service.updateSong(
    context: const ActiveCatalogContext(
      userId: 'user-1',
      organizationId: 'org-1',
    ),
    songId: 'song-1',
    title: 'Test',
    chordproSource: '{t: Test}\n{soc}\n[A]Hello\n{eoc}\n',
  );

  expect(
    repository.lastUpsertedRecord?.chordproSource,
    '{title: Test}\n{start_of_chorus}\n[A]Hello\n{end_of_chorus}\n',
  );
});
```

Also add `lastUpsertedRecord` tracking to `_FakeSongRepository` in the test file. Add the field declaration and update `upsertSong`:

```dart
// Add field alongside existing ones:
SongMutationRecord? lastUpsertedRecord;

// Replace the existing upsertSong override:
@override
Future<void> upsertSong({
  required String userId,
  required SongMutationRecord record,
}) async {
  lastUpsertedRecord = record;
  upsertedSlugs.add(record.slug);
  if (rejectFirstUpsertWithSlugConflict) {
    rejectFirstUpsertWithSlugConflict = false;
    throw const LocalSongSlugConflictException();
  }
  songById = record;
}
```

- [ ] **Step 2: Run to confirm tests fail**

```bash
cd apps/lyron_app && flutter test test/application/song_library/song_library_service_test.dart
```

Expected: tests fail — source is stored verbatim without normalization.

- [ ] **Step 3: Add normalizer to SongLibraryService**

In `song_library_service.dart`, add import and field:

```dart
import 'package:lyron_app/src/infrastructure/song_library/chordpro/chordpro_normalizer.dart';
```

Add field to class:

```dart
final _normalizer = ChordproNormalizer();
```

In `createSong`, normalize before using:

```dart
Future<SongMutationRecord> createSong({
  required ActiveCatalogContext context,
  required String title,
  required String chordproSource,
}) async {
  final normalizedSource = _normalizer.normalize(chordproSource);
  final mutationStore = _requireMutationStore();
  final songId = _idGenerator();

  for (var attempt = 0; attempt < _maxCreateSlugRetries; attempt += 1) {
    final slug = await mutationStore.allocateUniqueSlug(
      userId: context.userId,
      organizationId: context.organizationId,
      title: title,
    );
    final record = SongMutationRecord(
      id: songId,
      organizationId: context.organizationId,
      slug: slug,
      title: title,
      chordproSource: normalizedSource,
      version: 1,
      baseVersion: null,
      syncStatus: SongSyncStatus.pendingCreate,
    );
    try {
      await mutationStore.upsertSong(userId: context.userId, record: record);
      return record;
    } on Object catch (error) {
      if (error is! LocalSongSlugConflictException) rethrow;
    }
  }
  throw StateError(
    'Failed to allocate a unique local song slug after $_maxCreateSlugRetries attempts.',
  );
}
```

In `updateSong`, normalize before using:

```dart
Future<SongMutationRecord> updateSong({
  required ActiveCatalogContext context,
  required String songId,
  required String title,
  required String chordproSource,
}) async {
  final normalizedSource = _normalizer.normalize(chordproSource);
  // rest of existing method unchanged, but use normalizedSource instead of chordproSource
  final mutationStore = _requireMutationStore();
  final existing = await mutationStore.readById(
    userId: context.userId,
    organizationId: context.organizationId,
    songId: songId,
  );
  if (existing == null) {
    throw StateError('Song mutation record not found: $songId');
  }
  if (existing.syncStatus == SongSyncStatus.conflict) {
    throw SongConflictResolutionRequiredException(songId);
  }
  final updated = existing.copyWith(
    title: title,
    chordproSource: normalizedSource,
    baseVersion: existing.version,
    syncStatus: existing.syncStatus == SongSyncStatus.pendingCreate
        ? SongSyncStatus.pendingCreate
        : SongSyncStatus.pendingUpdate,
    clearErrorCode: true,
    clearErrorMessage: true,
  );
  await mutationStore.upsertSong(userId: context.userId, record: updated);
  return updated;
}
```

- [ ] **Step 4: Run tests**

```bash
cd apps/lyron_app && flutter test test/application/song_library/song_library_service_test.dart
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add apps/lyron_app/lib/src/application/song_library/song_library_service.dart \
        apps/lyron_app/test/application/song_library/song_library_service_test.dart
git commit -m "feat: normalize ChordPro source aliases on every save in SongLibraryService"
```

---

## Task 5: Parser — metadata improvements

**Files:**
- Modify: `apps/lyron_app/lib/src/infrastructure/song_library/chordpro/chordpro_parser.dart`
- Modify: `apps/lyron_app/test/infrastructure/song_library/chordpro/chordpro_parser_test.dart`

- [ ] **Step 1: Write failing tests**

Add to `chordpro_parser_test.dart`:

```dart
test('{tag:} singular is an alias for {tags:}', () {
  final parser = ChordproParser();
  final song = parser.parse('{title:T}\n{tag: Worship, Praise}\n');
  expect(song.tags, ['Worship', 'Praise']);
  expect(song.diagnostics, isEmpty);
});

test('{meta:} is silently ignored without a diagnostic', () {
  final parser = ChordproParser();
  final song = parser.parse('{title:T}\n{meta: key value}\n');
  expect(song.diagnostics, isEmpty);
});

test('parser accepts short aliases robustly (post-normalizer fallback)', () {
  final parser = ChordproParser();
  // {t:} and {st:} should be accepted even without normalizer running first
  final song = parser.parse('{t:My Song}\n{st:Sub}\n');
  expect(song.title, 'My Song');
  expect(song.subtitle, 'Sub');
  expect(song.diagnostics, isEmpty);
});
```

- [ ] **Step 2: Run to confirm they fail**

```bash
cd apps/lyron_app && flutter test test/infrastructure/song_library/chordpro/chordpro_parser_test.dart --name "tag\|meta\|aliases"
```

Expected: 3 failures.

- [ ] **Step 3: Update parser directive handling**

In `chordpro_parser.dart`, in the directive `if/else` chain, add aliases and new cases. After the existing `directiveName == 'tags'` branch, change it and add:

```dart
} else if (directiveName == 'tags' || directiveName == 'tag') {
  tags = _parseTags(line.directiveValue);
} else if (directiveName == 't') {
  title = line.directiveValue ?? '';
} else if (directiveName == 'st') {
  subtitle = line.directiveValue;
} else if (directiveName == 'c') {
  // alias for comment — handled below; re-route by treating as comment
  // (fall through to comment handler by duplicating logic)
  final commentValue = line.directiveValue ?? '';
  final parsedSection = _parseCommentSection(commentValue);
  if (parsedSection != null && !_isSameSection(currentSection, parsedSection)) {
    sections.add(parsedSection);
    currentSection = parsedSection;
    hasSeenSongContent = true;
  }
} else if (directiveName == 'meta') {
  // silently ignore — ChordPro generic metadata, no rendering
```

Note: The `{c:}` case is a stopgap. In Task 7, `{comment:}` gets full CommentLine support, and `{c:}` should behave identically. For now, the normalizer will convert `{c:}` to `{comment:}` before save, so this branch is only hit for sources that arrive un-normalized.

- [ ] **Step 4: Run tests**

```bash
cd apps/lyron_app && flutter test test/infrastructure/song_library/chordpro/chordpro_parser_test.dart
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add apps/lyron_app/lib/src/infrastructure/song_library/chordpro/chordpro_parser.dart \
        apps/lyron_app/test/infrastructure/song_library/chordpro/chordpro_parser_test.dart
git commit -m "feat: add {tag:}, {meta:}, and short alias support to ChordPro parser"
```

---

## Task 6: Parser — section block directives

**Files:**
- Modify: `apps/lyron_app/lib/src/infrastructure/song_library/chordpro/chordpro_parser.dart`
- Modify: `apps/lyron_app/test/infrastructure/song_library/chordpro/chordpro_parser_test.dart`

- [ ] **Step 1: Write failing tests**

Add to `chordpro_parser_test.dart`:

```dart
test('{start_of_verse}/{end_of_verse} creates a verse section', () {
  final parser = ChordproParser();
  final song = parser.parse(
    '{title:T}\n{start_of_verse}\n[A]Line\n{end_of_verse}\n',
  );
  expect(song.sections.single.kind, SongSectionKind.verse);
  expect(song.sections.single.label, 'Verse');
  expect(song.diagnostics, isEmpty);
});

test('{start_of_bridge}/{end_of_bridge} creates a bridge section', () {
  final parser = ChordproParser();
  final song = parser.parse(
    '{title:T}\n{start_of_bridge}\n[A]Line\n{end_of_bridge}\n',
  );
  expect(song.sections.single.kind, SongSectionKind.bridge);
  expect(song.diagnostics, isEmpty);
});

test('{start_of_verse: Verse 1} uses label override', () {
  final parser = ChordproParser();
  final song = parser.parse(
    '{title:T}\n{start_of_verse: Verse 1}\n[A]Line\n{end_of_verse}\n',
  );
  expect(song.sections.single.kind, SongSectionKind.verse);
  expect(song.sections.single.label, 'Verse 1');
  expect(song.diagnostics, isEmpty);
});

test('{start_of_chorus: Refrén} uses label override', () {
  final parser = ChordproParser();
  final song = parser.parse(
    '{title:T}\n{start_of_chorus: Refrén}\n[A]Line\n{end_of_chorus}\n',
  );
  expect(song.sections.single.kind, SongSectionKind.chorus);
  expect(song.sections.single.label, 'Refrén');
  expect(song.diagnostics, isEmpty);
});

test('{start_of_tab}/{end_of_tab} creates a tab section', () {
  final parser = ChordproParser();
  final song = parser.parse(
    '{title:T}\n{start_of_tab}\ne|---0---\nB|---1---\n{end_of_tab}\n',
  );
  expect(song.sections.single.kind, SongSectionKind.tab);
  expect(song.sections.single.lines, hasLength(2));
  expect(song.sections.single.lines[0], isA<TabBlock>());
  final tab = song.sections.single.lines[0] as TabBlock;
  expect(tab.rawLines, ['e|---0---', 'B|---1---']);
  expect(song.diagnostics, isEmpty);
});

test('{start_of_prechorus} creates an unknown section', () {
  final parser = ChordproParser();
  final song = parser.parse(
    '{title:T}\n{start_of_prechorus}\n[A]Line\n{end_of_prechorus}\n',
  );
  expect(song.sections.single.kind, SongSectionKind.unknown);
  expect(song.sections.single.label, 'prechorus');
  expect(song.diagnostics, isEmpty);
});
```

- [ ] **Step 2: Run to confirm they fail**

```bash
cd apps/lyron_app && flutter test test/infrastructure/song_library/chordpro/chordpro_parser_test.dart --name "start_of"
```

Expected: 6 failures.

- [ ] **Step 3: Implement section block directive handling in parser**

In `chordpro_parser.dart`, replace the existing `start_of_chorus` / `end_of_chorus` branches and add a generalized block handler. Replace the current two branches with:

```dart
} else if (directiveName.startsWith('start_of_')) {
  hasSeenSongContent = true;
  final sectionType = directiveName.substring('start_of_'.length);
  final labelOverride = line.directiveValue?.trim();

  switch (sectionType) {
    case 'chorus':
      if (currentSection?.kind != SongSectionKind.chorus) {
        final section = _SectionBuilder(
          kind: SongSectionKind.chorus,
          label: labelOverride ?? 'Chorus',
        );
        sections.add(section);
        currentSection = section;
      }
    case 'verse':
      final section = _SectionBuilder(
        kind: SongSectionKind.verse,
        label: labelOverride ?? 'Verse',
      );
      sections.add(section);
      currentSection = section;
    case 'bridge':
      final section = _SectionBuilder(
        kind: SongSectionKind.bridge,
        label: labelOverride ?? 'Bridge',
      );
      sections.add(section);
      currentSection = section;
    case 'tab':
      final section = _SectionBuilder(
        kind: SongSectionKind.tab,
        label: 'Tab',
      );
      sections.add(section);
      currentSection = section;
    default:
      final section = _SectionBuilder(
        kind: SongSectionKind.unknown,
        label: labelOverride ?? sectionType,
      );
      sections.add(section);
      currentSection = section;
  }
} else if (directiveName.startsWith('end_of_')) {
  hasSeenSongContent = true;
  currentSection = null;
```

Now handle tab content: in the lyric line handler, when the current section is a tab block, accumulate raw lines into a `TabBlock` instead of parsing as lyrics:

```dart
} else if (line.kind == ChordproLineKind.lyric) {
  hasSeenSongContent = true;
  currentSection = _ensureSection(
    sections: sections,
    currentSection: currentSection,
    kind: SongSectionKind.other,
    label: 'Unlabeled',
  );
  if (currentSection.kind == SongSectionKind.tab) {
    currentSection.appendTabLine(line.raw);
  } else {
    currentSection.lines.add(LyricLine(segments: _parseLyricLine(line.raw)));
  }
```

Add `appendTabLine` to `_SectionBuilder`:

```dart
class _SectionBuilder {
  _SectionBuilder({required this.kind, required this.label, this.number});

  final SongSectionKind kind;
  final String label;
  final int? number;
  final List<SongLine> lines = <SongLine>[];
  final List<String> _pendingTabLines = <String>[];

  void appendTabLine(String rawLine) {
    _pendingTabLines.add(rawLine);
  }

  SongSection build() {
    final builtLines = List<SongLine>.from(lines);
    if (_pendingTabLines.isNotEmpty) {
      builtLines.add(TabBlock(rawLines: List.unmodifiable(_pendingTabLines)));
    }
    return SongSection(
      kind: kind,
      label: label,
      number: number,
      lines: builtLines,
    );
  }
}
```

Also handle empty lines inside tab blocks — they should also go into `_pendingTabLines`. Update the empty line handler:

```dart
if (line.kind == ChordproLineKind.empty) {
  if (currentSection != null) {
    if (currentSection.kind == SongSectionKind.tab) {
      currentSection.appendTabLine('');
    } else {
      currentSection.lines.add(LyricLine(segments: const [LyricSegment(text: '')]));
    }
  }
}
```

- [ ] **Step 4: Run tests**

```bash
cd apps/lyron_app && flutter test test/infrastructure/song_library/chordpro/chordpro_parser_test.dart
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add apps/lyron_app/lib/src/infrastructure/song_library/chordpro/chordpro_parser.dart \
        apps/lyron_app/test/infrastructure/song_library/chordpro/chordpro_parser_test.dart
git commit -m "feat: add start_of_verse/bridge/tab/unknown block directive support to parser"
```

---

## Task 7: Parser — comment directive + CommentLine + preamble + unknown directives

This task changes several existing behaviors. The `chordpro_diagnostics_test.dart` test that expects a warning for unknown directives will need updating.

**Files:**
- Modify: `apps/lyron_app/lib/src/infrastructure/song_library/chordpro/chordpro_parser.dart`
- Modify: `apps/lyron_app/test/infrastructure/song_library/chordpro/chordpro_parser_test.dart`
- Modify: `apps/lyron_app/test/infrastructure/song_library/chordpro/chordpro_diagnostics_test.dart`

- [ ] **Step 1: Write failing tests**

Add to `chordpro_parser_test.dart`:

```dart
test('<Verse1> (no space) is parsed as verse section with number 1', () {
  final parser = ChordproParser();
  final song = parser.parse('{title:T}\n{comment:<Verse1>}\n[A]Line\n');
  expect(song.sections.single.kind, SongSectionKind.verse);
  expect(song.sections.single.number, 1);
  expect(song.diagnostics, isEmpty);
});

test('<Bridge 1> (numbered bridge) is parsed correctly', () {
  final parser = ChordproParser();
  final song = parser.parse('{title:T}\n{comment:<Bridge 1>}\n[A]Line\n');
  expect(song.sections.single.kind, SongSectionKind.bridge);
  expect(song.sections.single.number, 1);
  expect(song.diagnostics, isEmpty);
});

test('<PreChorus> creates an unknown section with label PreChorus', () {
  final parser = ChordproParser();
  final song = parser.parse('{title:T}\n{comment:<PreChorus>}\n[A]Line\n');
  expect(song.sections.single.kind, SongSectionKind.unknown);
  expect(song.sections.single.label, 'PreChorus');
  expect(song.diagnostics, isEmpty);
});

test('{comment:// note} creates a CommentLine in current section', () {
  final parser = ChordproParser();
  final song = parser.parse(
    '{title:T}\n{comment:<Verse>}\n[A]Line\n{comment:// Note}\n',
  );
  expect(song.sections.single.lines, hasLength(2));
  expect(song.sections.single.lines[1], isA<CommentLine>());
  final comment = song.sections.single.lines[1] as CommentLine;
  expect(comment.text, '// Note');
  expect(song.diagnostics, isEmpty);
});

test('{comment:# Author} creates a CommentLine', () {
  final parser = ChordproParser();
  final song = parser.parse(
    '{title:T}\n{comment:<Verse>}\n[A]Line\n{comment:#Szerző: Pintér}\n',
  );
  expect(song.sections.single.lines[1], isA<CommentLine>());
  final comment = song.sections.single.lines[1] as CommentLine;
  expect(comment.text, '#Szerző: Pintér');
  expect(song.diagnostics, isEmpty);
});

test('{comment: plain text} creates a CommentLine', () {
  final parser = ChordproParser();
  final song = parser.parse(
    '{title:T}\n{comment:<Verse>}\n[A]Line\n{comment:Some remark}\n',
  );
  expect(song.sections.single.lines[1], isA<CommentLine>());
  expect((song.sections.single.lines[1] as CommentLine).text, 'Some remark');
  expect(song.diagnostics, isEmpty);
});

test('unknown directive before any section goes into preamble section', () {
  final parser = ChordproParser();
  final song = parser.parse(
    '{title:T}\n{zoom-ipad: 1.9}\n{comment:<Verse>}\n[A]Line\n',
  );
  expect(song.sections, hasLength(2));
  expect(song.sections[0].kind, SongSectionKind.other);
  expect(song.sections[0].label, 'Unlabeled');
  expect(song.sections[0].lines.single, isA<DirectiveLine>());
  final directive = song.sections[0].lines.single as DirectiveLine;
  expect(directive.name, 'zoom-ipad');
  expect(directive.value, '1.9');
  expect(song.diagnostics, isEmpty);
});

test('unknown directive inside a section becomes DirectiveLine in that section', () {
  final parser = ChordproParser();
  final song = parser.parse(
    '{title:T}\n{comment:<Verse>}\n[A]Line\n{metronome:120}\n',
  );
  expect(song.sections.single.lines, hasLength(2));
  expect(song.sections.single.lines[1], isA<DirectiveLine>());
  final directive = song.sections.single.lines[1] as DirectiveLine;
  expect(directive.name, 'metronome');
  expect(directive.value, '120');
  expect(song.diagnostics, isEmpty);
});
```

- [ ] **Step 2: Run to confirm they fail**

```bash
cd apps/lyron_app && flutter test test/infrastructure/song_library/chordpro/chordpro_parser_test.dart --name "Verse1\|Bridge 1\|PreChorus\|CommentLine\|preamble\|DirectiveLine"
```

Expected: failures.

- [ ] **Step 3: Update _parseCommentSection — regex, bridge numbering, unknown labels**

Replace `_parseCommentSection` in `chordpro_parser.dart`:

```dart
_SectionBuilder? _parseCommentSection(String directiveValue) {
  final normalizedValue = _normalizeCommentSectionValue(directiveValue);
  final match = RegExp(
    r'^([A-Za-z]+)\s*(\d+)?$',
  ).firstMatch(normalizedValue);
  if (match == null) return null;

  final labelWord = match.group(1)!;
  final number = match.group(2) == null ? null : int.parse(match.group(2)!);
  switch (labelWord.toLowerCase()) {
    case 'verse':
      return _SectionBuilder(
        kind: SongSectionKind.verse,
        label: 'Verse',
        number: number,
      );
    case 'chorus':
      return _SectionBuilder(
        kind: SongSectionKind.chorus,
        label: 'Chorus',
        number: number,
      );
    case 'bridge':
      return _SectionBuilder(
        kind: SongSectionKind.bridge,
        label: 'Bridge',
        number: number,
      );
    case 'intro':
      return _SectionBuilder(
        kind: SongSectionKind.other,
        label: 'Intro',
        number: number,
      );
    default:
      return _SectionBuilder(
        kind: SongSectionKind.unknown,
        label: labelWord,
        number: number,
      );
  }
}
```

- [ ] **Step 4: Update comment directive handler — add CommentLine path**

Replace the `directiveName == 'comment'` block:

```dart
} else if (directiveName == 'comment') {
  final commentValue = line.directiveValue ?? '';
  final parsedSection = _parseCommentSection(commentValue);
  if (parsedSection != null) {
    if (!_isSameSection(currentSection, parsedSection)) {
      sections.add(parsedSection);
      currentSection = parsedSection;
      hasSeenSongContent = true;
    }
  } else {
    // Not a section header — treat as inline comment line.
    final targetSection = _ensurePreambleOrCurrentSection(
      sections: sections,
      currentSection: currentSection,
    );
    currentSection = targetSection;
    targetSection.lines.add(CommentLine(text: commentValue));
    hasSeenSongContent = true;
  }
```

Add helper `_ensurePreambleOrCurrentSection`:

```dart
_SectionBuilder _ensurePreambleOrCurrentSection({
  required List<_SectionBuilder> sections,
  required _SectionBuilder? currentSection,
}) {
  if (currentSection != null) return currentSection;
  final preamble = _SectionBuilder(
    kind: SongSectionKind.other,
    label: 'Unlabeled',
  );
  sections.add(preamble);
  return preamble;
}
```

- [ ] **Step 5: Update the `c` alias branch to match new comment logic**

In Task 5 the `c` branch only handled section headers. Update it to match the full new `comment` behavior:

```dart
} else if (directiveName == 'c') {
  final commentValue = line.directiveValue ?? '';
  final parsedSection = _parseCommentSection(commentValue);
  if (parsedSection != null) {
    if (!_isSameSection(currentSection, parsedSection)) {
      sections.add(parsedSection);
      currentSection = parsedSection;
      hasSeenSongContent = true;
    }
  } else {
    final targetSection = _ensurePreambleOrCurrentSection(
      sections: sections,
      currentSection: currentSection,
    );
    currentSection = targetSection;
    targetSection.lines.add(CommentLine(text: commentValue));
    hasSeenSongContent = true;
  }
```

- [ ] **Step 6: Replace the unknown directive else branch with DirectiveLine**

Replace the final `else` branch that generates a warning:

```dart
} else {
  final targetSection = _ensurePreambleOrCurrentSection(
    sections: sections,
    currentSection: currentSection,
  );
  currentSection = targetSection;
  targetSection.lines.add(
    DirectiveLine(name: directiveName, value: line.directiveValue?.trim()),
  );
}
```

- [ ] **Step 6: Update chordpro_diagnostics_test.dart**

The existing test asserts that unknown directives produce a warning. This behavior has changed — they now produce a `DirectiveLine` with no diagnostic. Update the test:

```dart
test('unknown directive produces a DirectiveLine and no diagnostic', () {
  final parser = ChordproParser();

  final song = parser.parse('''
{title:Example Song}
{comment:<Verse>}
Line one
{unknown:token}
Line two
''');

  expect(song.sections.single.lines, hasLength(3));
  expect(song.sections.single.lines[1], isA<DirectiveLine>());
  final directive = song.sections.single.lines[1] as DirectiveLine;
  expect(directive.name, 'unknown');
  expect(directive.value, 'token');
  expect(song.diagnostics, isEmpty);
});
```

Also remove the `SongReaderResult` import from this test if it is no longer needed after removing `hasRecoverableWarnings` assertion. Keep it if the test still uses it for other assertions.

- [ ] **Step 7: Run all tests**

(Was Step 6 before adding Step 5 above — renumber mentally if needed.)

```bash
cd apps/lyron_app && flutter test
```

Expected: all tests pass.

- [ ] **Step 8: Commit**

```bash
git add apps/lyron_app/lib/src/infrastructure/song_library/chordpro/chordpro_parser.dart \
        apps/lyron_app/test/infrastructure/song_library/chordpro/chordpro_parser_test.dart \
        apps/lyron_app/test/infrastructure/song_library/chordpro/chordpro_diagnostics_test.dart
git commit -m "feat: CommentLine, DirectiveLine, preamble section, and comment label parsing fixes"
```

---

## Task 8: Projection types + UI rendering

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_projection.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_section_view.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_line_view.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_section_grid.dart`
- Create: `apps/lyron_app/lib/src/presentation/song_reader/widgets/comment_line_view.dart`
- Create: `apps/lyron_app/lib/src/presentation/song_reader/widgets/tab_block_view.dart`
- Create: `apps/lyron_app/lib/src/presentation/song_reader/widgets/directive_line_view.dart`

- [ ] **Step 1: Add sealed projection base + rename SongReaderLineProjection**

In `song_reader_projection.dart`, introduce a sealed base and rename the existing concrete type:

```dart
sealed class SongReaderSectionItemProjection {}

class SongReaderLyricLineProjection extends SongReaderSectionItemProjection {
  SongReaderLyricLineProjection({
    required List<SongReaderSegmentProjection> segments,
  }) : segments = List.unmodifiable(segments);

  final List<SongReaderSegmentProjection> segments;
}

class SongReaderCommentProjection extends SongReaderSectionItemProjection {
  const SongReaderCommentProjection({required this.text});
  final String text;
}

class SongReaderTabProjection extends SongReaderSectionItemProjection {
  SongReaderTabProjection({required List<String> rawLines})
      : rawLines = List.unmodifiable(rawLines);
  final List<String> rawLines;
}

class SongReaderDirectiveProjection extends SongReaderSectionItemProjection {
  const SongReaderDirectiveProjection({required this.name, this.value});
  final String name;
  final String? value;
}
```

Remove the old `SongReaderLineProjection` class (or keep as a typedef for backward compat during this task — easier to remove).

Update `SongReaderSectionProjection`:
- Change `lines` type to `List<SongReaderSectionItemProjection>`
- Add `isUnknown: bool`

```dart
class SongReaderSectionProjection {
  SongReaderSectionProjection({
    required this.kind,
    required this.label,
    required this.number,
    required this.isUnknown,
    required List<SongReaderSectionItemProjection> lines,
  }) : lines = List.unmodifiable(lines);

  final SongSectionKind kind;
  final String label;
  final int? number;
  final bool isUnknown;
  final List<SongReaderSectionItemProjection> lines;
}
```

Update `_projectLine` top-level function to return `SongReaderSectionItemProjection`:

```dart
SongReaderSectionItemProjection _projectLine(
  SongLine line,
  SongReaderState state,
  ParsedSong song,
  SongChordTransposer transposeChord,
) {
  return switch (line) {
    LyricLine() => SongReaderLyricLineProjection(
        segments: List.unmodifiable(
          line.segments
              .map(
                (segment) => SongReaderSegmentProjection(
                  displayChord: SongReaderProjection._displayChord(
                    segment.leadingChord,
                    state,
                    song,
                    transposeChord,
                  ),
                  text: segment.text,
                ),
              )
              .toList(growable: false),
        ),
      ),
    CommentLine() => SongReaderCommentProjection(text: line.text),
    TabBlock() => SongReaderTabProjection(rawLines: line.rawLines),
    DirectiveLine() =>
      SongReaderDirectiveProjection(name: line.name, value: line.value),
  };
}
```

Update `SongReaderProjection` constructor for `sections`:

```dart
sections = List.unmodifiable(
  song.sections
      .map(
        (section) => SongReaderSectionProjection(
          kind: section.kind,
          label: section.label,
          number: section.number,
          isUnknown: section.kind == SongSectionKind.unknown,
          lines: List.unmodifiable(
            section.lines
                .map((line) => _projectLine(line, state, song, transposeChord))
                .toList(growable: false),
          ),
        ),
      )
      .toList(growable: false),
),
```

- [ ] **Step 2: Update SongLineView to use SongReaderLyricLineProjection**

In `song_line_view.dart`, change the `line` parameter type:

```dart
class SongLineView extends StatelessWidget {
  const SongLineView({
    super.key,
    required this.line,
    required this.viewMode,
    required this.sharedFontScale,
  });

  final SongReaderLyricLineProjection line;  // was SongReaderLineProjection
  ...
```

No other changes needed in `SongLineView`.

- [ ] **Step 3: Create CommentLineView**

Create `apps/lyron_app/lib/src/presentation/song_reader/widgets/comment_line_view.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';

class CommentLineView extends StatelessWidget {
  const CommentLineView({
    super.key,
    required this.projection,
    required this.sharedFontScale,
  });

  final SongReaderCommentProjection projection;
  final double sharedFontScale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      projection.text,
      style: theme.textTheme.bodyMedium?.copyWith(
        fontSize:
            (theme.textTheme.bodyMedium?.fontSize ?? 14) * sharedFontScale,
        fontStyle: FontStyle.italic,
        color: theme.colorScheme.onSurface.withOpacity(0.55),
        height: 1.4,
      ),
    );
  }
}
```

- [ ] **Step 4: Create TabBlockView**

Create `apps/lyron_app/lib/src/presentation/song_reader/widgets/tab_block_view.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';

class TabBlockView extends StatelessWidget {
  const TabBlockView({
    super.key,
    required this.projection,
    required this.sharedFontScale,
  });

  final SongReaderTabProjection projection;
  final double sharedFontScale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: 13.0 * sharedFontScale,
      height: 1.5,
      color: theme.colorScheme.onSurface,
    );
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final rawLine in projection.rawLines)
              Text(rawLine, style: textStyle),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Create DirectiveLineView**

Create `apps/lyron_app/lib/src/presentation/song_reader/widgets/directive_line_view.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';

class DirectiveLineView extends StatelessWidget {
  const DirectiveLineView({super.key, required this.projection});

  final SongReaderDirectiveProjection projection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = projection.value != null
        ? '{${projection.name}: ${projection.value}}'
        : '{${projection.name}}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.tertiary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Update SongSectionView to switch on projection types**

Replace `song_section_view.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:lyron_app/src/domain/song/song_section.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/comment_line_view.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/directive_line_view.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_line_view.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/tab_block_view.dart';

class SongSectionView extends StatelessWidget {
  const SongSectionView({
    super.key,
    required this.section,
    required this.viewMode,
    required this.sharedFontScale,
  });

  final SongReaderSectionProjection section;
  final SongReaderViewMode viewMode;
  final double sharedFontScale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = _sectionLabel(section);
    final labelColor = section.isUnknown
        ? theme.colorScheme.tertiary
        : theme.colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label,
            style: theme.textTheme.titleLarge?.copyWith(color: labelColor),
          ),
          const SizedBox(height: 12),
        ],
        for (final item in section.lines) ...[
          switch (item) {
            SongReaderLyricLineProjection() => SongLineView(
                line: item,
                viewMode: viewMode,
                sharedFontScale: sharedFontScale,
              ),
            SongReaderCommentProjection() => CommentLineView(
                projection: item,
                sharedFontScale: sharedFontScale,
              ),
            SongReaderTabProjection() => TabBlockView(
                projection: item,
                sharedFontScale: sharedFontScale,
              ),
            SongReaderDirectiveProjection() =>
              DirectiveLineView(projection: item),
          },
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  String? _sectionLabel(SongReaderSectionProjection section) {
    final isUnlabeled = section.label == 'Unlabeled' && section.number == null;
    if (isUnlabeled) return null;
    if (section.number == null) return section.label;
    return '${section.label} ${section.number}';
  }
}
```

- [ ] **Step 7: Update song_reader_section_grid.dart height estimation**

Replace the `for (final line in section.lines)` loop in `_estimatedSectionHeight`:

```dart
for (final item in section.lines) {
  switch (item) {
    case SongReaderLyricLineProjection():
      final text = item.segments.map((segment) => segment.text).join();
      final lyricLength = text.trimRight().length;
      final hasChord =
          viewMode == SongReaderViewMode.chordsAndLyrics &&
          item.segments.any((segment) => segment.displayChord != null);
      final wrapCount = lyricLength == 0
          ? 1
          : (lyricLength / charsPerLine).ceil().clamp(1, 14);
      final chordRowHeight =
          hasChord ? (_chordRowHeight * sharedFontScale) : 0;
      final lyricRowsHeight = wrapCount * (_lyricRowHeight * sharedFontScale);
      linesHeight += chordRowHeight + lyricRowsHeight + _lineGap;
    case SongReaderCommentProjection():
      linesHeight += _lyricRowHeight * sharedFontScale + _lineGap;
    case SongReaderTabProjection():
      linesHeight +=
          item.rawLines.length * (_lyricRowHeight * sharedFontScale) +
          _lineGap +
          16; // container padding
    case SongReaderDirectiveProjection():
      linesHeight += _directiveLineHeight;
  }
}
```

Also update `hasHeader` check to use the new `isUnknown` field for the preamble section (preamble has `label == 'Unlabeled'` and `number == null` so it already has no header — no change needed).

- [ ] **Step 8: Run all tests**

```bash
cd apps/lyron_app && flutter test
```

Expected: all tests pass.

- [ ] **Step 9: Commit**

```bash
git add apps/lyron_app/lib/src/presentation/song_reader/song_reader_projection.dart \
        apps/lyron_app/lib/src/presentation/song_reader/widgets/song_section_view.dart \
        apps/lyron_app/lib/src/presentation/song_reader/widgets/song_line_view.dart \
        apps/lyron_app/lib/src/presentation/song_reader/widgets/song_reader_section_grid.dart \
        apps/lyron_app/lib/src/presentation/song_reader/widgets/comment_line_view.dart \
        apps/lyron_app/lib/src/presentation/song_reader/widgets/tab_block_view.dart \
        apps/lyron_app/lib/src/presentation/song_reader/widgets/directive_line_view.dart
git commit -m "feat: add CommentLineView/TabBlockView/DirectiveLineView and unknown section color"
```

---

## Post-implementation

After all tasks pass, run the full test suite one final time:

```bash
cd apps/lyron_app && flutter test
```

Then verify visually by loading a song with `{comment:<PreChorus>}`, a tab block, and an unknown directive. Check that:
- PreChorus header renders in tertiary color
- Tab block renders in monospace with scrollable container
- Unknown directives render in tertiary color as `{name: value}`
- Comment lines render italic and muted
