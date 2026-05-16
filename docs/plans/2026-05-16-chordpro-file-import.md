# ChordPro File Import Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add single and bulk ChordPro file import (`.cho` / `.chordpro` / `.chopro`) via `file_picker` on Android, iOS, and Web, with duplicate detection, resolution dialog, and import summary.

**Architecture:** New `ChordProImportService` (application layer) handles parse → duplicate-check → commit. A `ChordProImportController` (Riverpod `StateNotifier`) drives state transitions. Two new dialog widgets (`ImportDuplicateDialog`, `ImportSummaryDialog`) are shown by the screen in response to controller state. Entry point: an **Import** `TextButton` in `SongListScreen`'s `AppBar`.

**Tech Stack:** Flutter, Riverpod (`StateNotifier`), `file_picker ^8.0.0`, existing `ChordproNormalizer` + `ChordproParser` + `SongLibraryService`.

---

## File Map

### New files

| Path | Responsibility |
|---|---|
| `lib/src/application/song_library/chordpro_import_types.dart` | Sealed result types, `ImportFileInput`, `ImportBatchResult`, `DuplicateResolution`, `kSupportedChordProExtensions` |
| `lib/src/application/song_library/chordpro_import_service.dart` | `ChordProImportService` — analyse files, commit imports |
| `lib/src/presentation/song_library/chordpro_import_controller.dart` | `ChordProImportController` + `ChordProImportState` sealed states + `chordProImportControllerProvider` |
| `lib/src/presentation/song_library/widgets/import_duplicate_dialog.dart` | `ImportDuplicateDialog` widget |
| `lib/src/presentation/song_library/widgets/import_summary_dialog.dart` | `ImportSummaryDialog` widget |
| `test/application/song_library/chordpro_import_service_test.dart` | Unit tests for `ChordProImportService` |
| `test/presentation/song_library/import_duplicate_dialog_test.dart` | Widget tests for `ImportDuplicateDialog` |
| `test/presentation/song_library/import_summary_dialog_test.dart` | Widget tests for `ImportSummaryDialog` |

### Modified files

| Path | Change |
|---|---|
| `pubspec.yaml` | Add `file_picker: ^8.0.0` |
| `lib/src/shared/app_strings.dart` | Add import-related string constants |
| `lib/src/presentation/song_library/song_library_providers.dart` | Add `chordProImportControllerProvider` |
| `lib/src/presentation/song_library/song_list_screen.dart` | Add Import `TextButton` in `AppBar.actions` |

---

## Task 1: Add `file_picker` dependency

**Files:**
- Modify: `apps/lyron_app/pubspec.yaml`

- [ ] **Step 1: Add dependency**

In `pubspec.yaml`, under `dependencies:`, after `supabase_flutter: ^2.12.0` add:

```yaml
  file_picker: ^8.0.0
```

- [ ] **Step 2: Fetch packages**

```bash
cd apps/lyron_app && flutter pub get
```

Expected: no errors, `pubspec.lock` updated with `file_picker`.

- [ ] **Step 3: Verify tests still pass**

```bash
cd apps/lyron_app && flutter test --no-pub
```

Expected: `All tests passed!`

- [ ] **Step 4: Commit**

```bash
git add apps/lyron_app/pubspec.yaml apps/lyron_app/pubspec.lock
git commit -m "chore: add file_picker dependency for ChordPro import"
```

---

## Task 2: Create import types

**Files:**
- Create: `apps/lyron_app/lib/src/application/song_library/chordpro_import_types.dart`

- [ ] **Step 1: Create the types file**

```dart
// apps/lyron_app/lib/src/application/song_library/chordpro_import_types.dart

/// File extensions accepted by the ChordPro importer (without leading dot).
/// Extend this set to support additional formats without changing any other file.
const Set<String> kSupportedChordProExtensions = {'cho', 'chordpro', 'chopro'};

/// Raw input from the file picker, before parsing.
class ImportFileInput {
  const ImportFileInput({required this.filename, required this.source});

  final String filename;
  final String source; // raw UTF-8 ChordPro text
}

sealed class ImportFileResult {
  const ImportFileResult();
}

/// File was parsed and has no title conflict with an existing song.
/// [source] is the normalised ChordPro text ready for storage.
class ImportSuccess extends ImportFileResult {
  const ImportSuccess({required this.title, required this.source});

  final String title;
  final String source;
}

/// File title matches an existing song (case-insensitive).
class ImportDuplicate extends ImportFileResult {
  const ImportDuplicate({
    required this.filename,
    required this.incomingSource,
    required this.incomingTitle,
    required this.existingSongId,
    required this.existingTitle,
  });

  final String filename;
  final String incomingSource;
  final String incomingTitle;
  final String existingSongId;
  final String existingTitle;
}

/// File could not be read or parsed.
class ImportError extends ImportFileResult {
  const ImportError({required this.filename, required this.reason});

  final String filename;
  final String reason;
}

class ImportBatchResult {
  const ImportBatchResult({
    required this.successes,
    required this.duplicates,
    required this.errors,
  });

  final List<ImportSuccess> successes;
  final List<ImportDuplicate> duplicates;
  final List<ImportError> errors;

  bool get hasIssues => duplicates.isNotEmpty || errors.isNotEmpty;

  int get totalImported => successes.length;
  int get totalSkipped =>
      duplicates.where((d) => d == d).length; // filled by controller after resolution
}

enum DuplicateResolution { overwrite, skip }

class ResolvedDuplicate {
  const ResolvedDuplicate({
    required this.duplicate,
    required this.resolution,
  });

  final ImportDuplicate duplicate;
  final DuplicateResolution resolution;
}
```

- [ ] **Step 2: Commit**

```bash
git add apps/lyron_app/lib/src/application/song_library/chordpro_import_types.dart
git commit -m "feat: add ChordPro import result types"
```

---

## Task 3: ChordProImportService — tests first

**Files:**
- Create: `apps/lyron_app/test/application/song_library/chordpro_import_service_test.dart`
- Create: `apps/lyron_app/lib/src/application/song_library/chordpro_import_service.dart`

### 3a: Write failing tests

- [ ] **Step 1: Create the test file**

```dart
// apps/lyron_app/test/application/song_library/chordpro_import_service_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/song_library/active_catalog_context.dart';
import 'package:lyron_app/src/application/song_library/chordpro_import_service.dart';
import 'package:lyron_app/src/application/song_library/chordpro_import_types.dart';
import 'package:lyron_app/src/application/song_library/song_catalog_read_repository.dart';
import 'package:lyron_app/src/application/song_library/song_library_service.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_types.dart';
import 'package:lyron_app/src/domain/song/song_source.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/infrastructure/song_library/chordpro/chordpro_normalizer.dart';
import 'package:lyron_app/src/infrastructure/song_library/chordpro/chordpro_parser.dart';

const _context = ActiveCatalogContext(userId: 'u1', organizationId: 'org1');

void main() {
  late _FakeRepo repo;
  late ChordProImportService service;

  setUp(() {
    repo = _FakeRepo();
    service = ChordProImportService(
      songLibraryService: SongLibraryService(repo, repo),
      catalogReadRepository: repo,
      normalizer: ChordproNormalizer(),
      parser: ChordproParser(),
    );
  });

  group('analyse', () {
    test('valid file with title directive → ImportSuccess', () async {
      final result = await service.analyse(
        context: _context,
        files: const [
          ImportFileInput(
            filename: 'amazing_grace.cho',
            source: '{title: Amazing Grace}\n[G]Amazing grace',
          ),
        ],
      );

      expect(result.successes, hasLength(1));
      expect(result.successes.single.title, 'Amazing Grace');
      expect(result.duplicates, isEmpty);
      expect(result.errors, isEmpty);
    });

    test('file without title directive → uses filename stem as title', () async {
      final result = await service.analyse(
        context: _context,
        files: const [
          ImportFileInput(
            filename: 'my_song.cho',
            source: '[G]Hello world',
          ),
        ],
      );

      expect(result.successes, hasLength(1));
      expect(result.successes.single.title, 'my_song');
    });

    test('title matches existing song (case-insensitive) → ImportDuplicate', () async {
      repo.songs = [
        const SongSummary(id: 'song-1', title: 'Amazing Grace'),
      ];

      final result = await service.analyse(
        context: _context,
        files: const [
          ImportFileInput(
            filename: 'ag.cho',
            source: '{title: amazing grace}\n[G]Amazing grace',
          ),
        ],
      );

      expect(result.duplicates, hasLength(1));
      expect(result.duplicates.single.existingSongId, 'song-1');
      expect(result.duplicates.single.incomingTitle, 'amazing grace');
      expect(result.successes, isEmpty);
    });

    test('empty file → ImportError', () async {
      final result = await service.analyse(
        context: _context,
        files: const [
          ImportFileInput(filename: 'empty.cho', source: ''),
        ],
      );

      expect(result.errors, hasLength(1));
      expect(result.errors.single.filename, 'empty.cho');
    });

    test('bulk: 1 success + 1 duplicate + 1 error → correct counts', () async {
      repo.songs = [
        const SongSummary(id: 'x', title: 'Existing Song'),
      ];

      final result = await service.analyse(
        context: _context,
        files: const [
          ImportFileInput(
            filename: 'new.cho',
            source: '{title: New Song}\n[C]Hello',
          ),
          ImportFileInput(
            filename: 'existing.cho',
            source: '{title: Existing Song}\n[G]World',
          ),
          ImportFileInput(filename: 'empty.cho', source: ''),
        ],
      );

      expect(result.successes, hasLength(1));
      expect(result.duplicates, hasLength(1));
      expect(result.errors, hasLength(1));
    });
  });

  group('commitImport', () {
    test('overwrite resolution → calls updateSong', () async {
      repo.songs = [const SongSummary(id: 'song-1', title: 'Amazing Grace')];

      const duplicate = ImportDuplicate(
        filename: 'ag.cho',
        incomingSource: '{title: Amazing Grace}\n[G]New version',
        incomingTitle: 'Amazing Grace',
        existingSongId: 'song-1',
        existingTitle: 'Amazing Grace',
      );

      await service.commitImport(
        context: _context,
        successes: const [],
        resolvedDuplicates: [
          const ResolvedDuplicate(
            duplicate: duplicate,
            resolution: DuplicateResolution.overwrite,
          ),
        ],
      );

      expect(repo.updatedSongIds, contains('song-1'));
    });

    test('skip resolution → does NOT call updateSong', () async {
      repo.songs = [const SongSummary(id: 'song-1', title: 'Amazing Grace')];

      const duplicate = ImportDuplicate(
        filename: 'ag.cho',
        incomingSource: '{title: Amazing Grace}\n[G]New version',
        incomingTitle: 'Amazing Grace',
        existingSongId: 'song-1',
        existingTitle: 'Amazing Grace',
      );

      await service.commitImport(
        context: _context,
        successes: const [],
        resolvedDuplicates: [
          const ResolvedDuplicate(
            duplicate: duplicate,
            resolution: DuplicateResolution.skip,
          ),
        ],
      );

      expect(repo.updatedSongIds, isEmpty);
    });

    test('success → calls createSong', () async {
      await service.commitImport(
        context: _context,
        successes: const [
          ImportSuccess(title: 'New Song', source: '{title: New Song}\n[C]Hi'),
        ],
        resolvedDuplicates: const [],
      );

      expect(repo.createdTitles, contains('New Song'));
    });
  });
}

// ---------------------------------------------------------------------------
// Fake repository — implements SongCatalogReadRepository + SongMutationStore
// ---------------------------------------------------------------------------

class _FakeRepo implements SongCatalogReadRepository, SongMutationStore {
  List<SongSummary> songs = [];
  final List<String> createdTitles = [];
  final List<String> updatedSongIds = [];

  @override
  Future<List<SongSummary>> listSongs({
    required String userId,
    required String organizationId,
  }) async => songs;

  @override
  Future<SongSource> getSongSource({
    required String userId,
    required String organizationId,
    required String songId,
  }) async => const SongSource(id: 'x', source: '');

  @override
  Future<SongSummary?> getSongSummaryById({
    required String userId,
    required String organizationId,
    required String songId,
  }) async => songs.where((s) => s.id == songId).firstOrNull;

  @override
  Future<SongSummary?> getSongSummaryBySlug({
    required String userId,
    required String organizationId,
    required String songSlug,
  }) async => null;

  // SongMutationStore — only the methods used by SongLibraryService
  final List<String> allocatedSlugs = [];
  bool rejectFirstUpsertWithSlugConflict = false;
  final _upserted = <SongMutationRecord>[];

  @override
  Future<String> allocateUniqueSlug({
    required String userId,
    required String organizationId,
    required String title,
  }) async {
    if (allocatedSlugs.isNotEmpty) {
      return allocatedSlugs.removeAt(0);
    }
    return title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  }

  @override
  Future<void> upsertSong({
    required String userId,
    required SongMutationRecord record,
  }) async {
    if (rejectFirstUpsertWithSlugConflict) {
      rejectFirstUpsertWithSlugConflict = false;
      throw LocalSongSlugConflictException(record.slug);
    }
    _upserted.add(record);
    if (record.syncStatus == SongSyncStatus.pendingCreate) {
      createdTitles.add(record.title);
    } else if (record.syncStatus == SongSyncStatus.pendingUpdate) {
      updatedSongIds.add(record.id);
    }
  }

  @override
  Future<SongMutationRecord?> readById({
    required String userId,
    required String organizationId,
    required String songId,
  }) async {
    // Return a minimal synced record so updateSong can proceed
    final song = songs.where((s) => s.id == songId).firstOrNull;
    if (song == null) return null;
    return SongMutationRecord(
      id: songId,
      organizationId: organizationId,
      slug: songId,
      title: song.title,
      chordproSource: '',
      version: 1,
      baseVersion: null,
      syncStatus: SongSyncStatus.synced,
    );
  }

  @override
  Future<int> countReferencingSessionItems({
    required String userId,
    required String organizationId,
    required String songId,
  }) async => 0;

  @override
  Future<void> deleteSong({
    required String userId,
    required String organizationId,
    required String songId,
  }) async {}

  @override
  Future<List<SongMutationRecord>> readPendingSongs({
    required String userId,
    required String organizationId,
  }) async => [];

  @override
  Future<List<SongMutationRecord>> readConflictSongs({
    required String userId,
    required String organizationId,
  }) async => [];

  @override
  Future<bool> hasUnsyncedChanges({required String userId}) async => false;
}
```

- [ ] **Step 2: Run test to confirm it fails**

```bash
cd apps/lyron_app && flutter test test/application/song_library/chordpro_import_service_test.dart --no-pub
```

Expected: compile error — `ChordProImportService` does not exist yet.

### 3b: Implement ChordProImportService

- [ ] **Step 3: Create the service**

```dart
// apps/lyron_app/lib/src/application/song_library/chordpro_import_service.dart

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:lyron_app/src/application/song_library/active_catalog_context.dart';
import 'package:lyron_app/src/application/song_library/chordpro_import_types.dart';
import 'package:lyron_app/src/application/song_library/song_catalog_read_repository.dart';
import 'package:lyron_app/src/application/song_library/song_library_service.dart';
import 'package:lyron_app/src/infrastructure/song_library/chordpro/chordpro_normalizer.dart';
import 'package:lyron_app/src/infrastructure/song_library/chordpro/chordpro_parser.dart';

class ChordProImportService {
  const ChordProImportService({
    required SongLibraryService songLibraryService,
    required SongCatalogReadRepository catalogReadRepository,
    required ChordproNormalizer normalizer,
    required ChordproParser parser,
  }) : _songLibraryService = songLibraryService,
       _catalogReadRepository = catalogReadRepository,
       _normalizer = normalizer,
       _parser = parser;

  final SongLibraryService _songLibraryService;
  final SongCatalogReadRepository _catalogReadRepository;
  final ChordproNormalizer _normalizer;
  final ChordproParser _parser;

  /// Read a [PlatformFile] as UTF-8 text.
  /// Returns null on any read or decode failure — never throws.
  static Future<String?> readPlatformFile(PlatformFile file) async {
    try {
      if (file.bytes != null) {
        return utf8.decode(file.bytes!, allowMalformed: false);
      }
      if (file.path != null) {
        return File(file.path!).readAsString();
      }
    } on FormatException {
      return null;
    } catch (_) {
      return null;
    }
    return null;
  }

  /// Parse [files] and classify each as success / duplicate / error.
  /// Does NOT write to the database.
  Future<ImportBatchResult> analyse({
    required ActiveCatalogContext context,
    required List<ImportFileInput> files,
  }) async {
    final existingSongs = await _catalogReadRepository.listSongs(
      userId: context.userId,
      organizationId: context.organizationId,
    );

    final successes = <ImportSuccess>[];
    final duplicates = <ImportDuplicate>[];
    final errors = <ImportError>[];

    for (final file in files) {
      if (file.source.trim().isEmpty) {
        errors.add(ImportError(filename: file.filename, reason: 'Üres fájl'));
        continue;
      }

      final normalizedSource = _normalizer.normalize(file.source);
      final parsed = _parser.parse(normalizedSource);

      final rawTitle = parsed.title.trim();
      final title = rawTitle.isNotEmpty ? rawTitle : _stemOf(file.filename);

      final matchingExisting = existingSongs
          .where(
            (s) => s.title.trim().toLowerCase() == title.trim().toLowerCase(),
          )
          .firstOrNull;

      if (matchingExisting != null) {
        duplicates.add(
          ImportDuplicate(
            filename: file.filename,
            incomingSource: normalizedSource,
            incomingTitle: title,
            existingSongId: matchingExisting.id,
            existingTitle: matchingExisting.title,
          ),
        );
      } else {
        successes.add(ImportSuccess(title: title, source: normalizedSource));
      }
    }

    return ImportBatchResult(
      successes: successes,
      duplicates: duplicates,
      errors: errors,
    );
  }

  /// Write imports to the song library after duplicate resolution.
  Future<ImportBatchResult> commitImport({
    required ActiveCatalogContext context,
    required List<ImportSuccess> successes,
    required List<ResolvedDuplicate> resolvedDuplicates,
  }) async {
    final committedSuccesses = <ImportSuccess>[];
    final skipped = <ImportDuplicate>[];
    final errors = <ImportError>[];

    for (final success in successes) {
      try {
        await _songLibraryService.createSong(
          context: context,
          title: success.title,
          chordproSource: success.source,
        );
        committedSuccesses.add(success);
      } catch (e) {
        errors.add(
          ImportError(filename: success.title, reason: e.toString()),
        );
      }
    }

    for (final resolved in resolvedDuplicates) {
      if (resolved.resolution == DuplicateResolution.skip) {
        skipped.add(resolved.duplicate);
        continue;
      }
      try {
        await _songLibraryService.updateSong(
          context: context,
          songId: resolved.duplicate.existingSongId,
          title: resolved.duplicate.incomingTitle,
          chordproSource: resolved.duplicate.incomingSource,
        );
        committedSuccesses.add(
          ImportSuccess(
            title: resolved.duplicate.incomingTitle,
            source: resolved.duplicate.incomingSource,
          ),
        );
      } catch (e) {
        errors.add(
          ImportError(
            filename: resolved.duplicate.filename,
            reason: e.toString(),
          ),
        );
      }
    }

    return ImportBatchResult(
      successes: committedSuccesses,
      duplicates: skipped,
      errors: errors,
    );
  }

  static String _stemOf(String filename) {
    final name = filename.contains('/')
        ? filename.split('/').last
        : filename;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }
}
```

- [ ] **Step 4: Run tests and confirm they pass**

```bash
cd apps/lyron_app && flutter test test/application/song_library/chordpro_import_service_test.dart --no-pub
```

Expected: all tests pass.

- [ ] **Step 5: Run full suite**

```bash
cd apps/lyron_app && flutter test --no-pub
```

Expected: `All tests passed!`

- [ ] **Step 6: Commit**

```bash
git add apps/lyron_app/lib/src/application/song_library/chordpro_import_service.dart \
        apps/lyron_app/test/application/song_library/chordpro_import_service_test.dart
git commit -m "feat: add ChordProImportService with TDD"
```

---

## Task 4: Add AppStrings for import UI

**Files:**
- Modify: `apps/lyron_app/lib/src/shared/app_strings.dart`

- [ ] **Step 1: Add import string constants**

At the end of the `AppStrings` class body, before the closing `}`, add:

```dart
  // ChordPro import
  static const songImportAction = 'Import';
  static const songImportPickerTitle = 'Import ChordPro files';
  static const songImportDuplicateDialogTitle = 'Duplicate songs';
  static const songImportDuplicateDialogMessage =
      'Some files match songs already in your library. Choose how to handle each.';
  static const songImportDuplicateOverwriteAction = 'Overwrite';
  static const songImportDuplicateSkipAction = 'Skip';
  static const songImportDuplicateOverwriteAllAction = 'Overwrite all';
  static const songImportDuplicateSkipAllAction = 'Skip all';
  static const songImportDuplicateConfirmAction = 'Continue';
  static const songImportSummaryTitle = 'Import complete';
  static const songImportSummaryImportedLabel = 'Imported';
  static const songImportSummarySkippedLabel = 'Skipped';
  static const songImportSummaryErrorsLabel = 'Errors';
  static const songImportSummaryDoneAction = 'Kész';
  static const songImportNoContextMessage =
      'Sign in before importing songs.';
  static const songImportReadErrorReason = 'Nem olvasható';
  static const songImportUtf8ErrorReason = 'Nem UTF-8 fájl';
  static const songImportEmptyFileReason = 'Üres fájl';
  static const songImportSaveErrorPrefix = 'Mentési hiba';
```

- [ ] **Step 2: Run tests**

```bash
cd apps/lyron_app && flutter test --no-pub
```

Expected: `All tests passed!`

- [ ] **Step 3: Commit**

```bash
git add apps/lyron_app/lib/src/shared/app_strings.dart
git commit -m "feat: add AppStrings constants for ChordPro import UI"
```

---

## Task 5: ImportDuplicateDialog — tests first

**Files:**
- Create: `apps/lyron_app/test/presentation/song_library/import_duplicate_dialog_test.dart`
- Create: `apps/lyron_app/lib/src/presentation/song_library/widgets/import_duplicate_dialog.dart`

### 5a: Write failing widget test

- [ ] **Step 1: Create the test file**

```dart
// apps/lyron_app/test/presentation/song_library/import_duplicate_dialog_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/song_library/chordpro_import_types.dart';
import 'package:lyron_app/src/presentation/song_library/widgets/import_duplicate_dialog.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

const _dup1 = ImportDuplicate(
  filename: 'ag.cho',
  incomingSource: '{title: Amazing Grace}',
  incomingTitle: 'Amazing Grace',
  existingSongId: 'song-1',
  existingTitle: 'Amazing Grace',
);

const _dup2 = ImportDuplicate(
  filename: 'ht.cho',
  incomingSource: '{title: Holy, Holy, Holy}',
  incomingTitle: 'Holy, Holy, Holy',
  existingSongId: 'song-2',
  existingTitle: 'Holy, Holy, Holy',
);

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('renders both duplicate rows', (tester) async {
    late List<ResolvedDuplicate> result;

    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showImportDuplicateDialog(
                context: context,
                duplicates: [_dup1, _dup2],
              ) ?? [];
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Amazing Grace'), findsWidgets);
    expect(find.text('Holy, Holy, Holy'), findsWidgets);
  });

  testWidgets('default resolution is skip; confirm returns skips', (tester) async {
    List<ResolvedDuplicate>? result;

    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showImportDuplicateDialog(
                context: context,
                duplicates: [_dup1],
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.songImportDuplicateConfirmAction));
    await tester.pumpAndSettle();

    expect(result, hasLength(1));
    expect(result!.single.resolution, DuplicateResolution.skip);
  });

  testWidgets('"Overwrite all" sets all items to overwrite', (tester) async {
    List<ResolvedDuplicate>? result;

    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showImportDuplicateDialog(
                context: context,
                duplicates: [_dup1, _dup2],
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.songImportDuplicateOverwriteAllAction));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.songImportDuplicateConfirmAction));
    await tester.pumpAndSettle();

    expect(result, hasLength(2));
    expect(result!.every((r) => r.resolution == DuplicateResolution.overwrite), isTrue);
  });

  testWidgets('per-item toggle changes individual resolution', (tester) async {
    List<ResolvedDuplicate>? result;

    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showImportDuplicateDialog(
                context: context,
                duplicates: [_dup1, _dup2],
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Toggle first item to overwrite
    final overwriteButtons = find.text(AppStrings.songImportDuplicateOverwriteAction);
    await tester.tap(overwriteButtons.first);
    await tester.pumpAndSettle();

    await tester.tap(find.text(AppStrings.songImportDuplicateConfirmAction));
    await tester.pumpAndSettle();

    expect(result, hasLength(2));
    expect(result![0].resolution, DuplicateResolution.overwrite);
    expect(result![1].resolution, DuplicateResolution.skip);
  });
}
```

- [ ] **Step 2: Run to confirm compile error**

```bash
cd apps/lyron_app && flutter test test/presentation/song_library/import_duplicate_dialog_test.dart --no-pub
```

Expected: compile error — `showImportDuplicateDialog` does not exist.

### 5b: Implement ImportDuplicateDialog

- [ ] **Step 3: Create the directory and widget file**

```bash
mkdir -p apps/lyron_app/lib/src/presentation/song_library/widgets
```

```dart
// apps/lyron_app/lib/src/presentation/song_library/widgets/import_duplicate_dialog.dart

import 'package:flutter/material.dart';
import 'package:lyron_app/src/application/song_library/chordpro_import_types.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

Future<List<ResolvedDuplicate>?> showImportDuplicateDialog({
  required BuildContext context,
  required List<ImportDuplicate> duplicates,
}) {
  return showDialog<List<ResolvedDuplicate>>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ImportDuplicateDialog(duplicates: duplicates),
  );
}

class _ImportDuplicateDialog extends StatefulWidget {
  const _ImportDuplicateDialog({required this.duplicates});

  final List<ImportDuplicate> duplicates;

  @override
  State<_ImportDuplicateDialog> createState() =>
      _ImportDuplicateDialogState();
}

class _ImportDuplicateDialogState extends State<_ImportDuplicateDialog> {
  late final List<DuplicateResolution> _resolutions;

  @override
  void initState() {
    super.initState();
    _resolutions = List.filled(
      widget.duplicates.length,
      DuplicateResolution.skip,
    );
  }

  void _applyAll(DuplicateResolution resolution) {
    setState(() {
      for (var i = 0; i < _resolutions.length; i++) {
        _resolutions[i] = resolution;
      }
    });
  }

  List<ResolvedDuplicate> _buildResult() {
    return [
      for (var i = 0; i < widget.duplicates.length; i++)
        ResolvedDuplicate(
          duplicate: widget.duplicates[i],
          resolution: _resolutions[i],
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(AppStrings.songImportDuplicateDialogTitle),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(AppStrings.songImportDuplicateDialogMessage),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton(
                  onPressed: () => _applyAll(DuplicateResolution.overwrite),
                  child: const Text(
                    AppStrings.songImportDuplicateOverwriteAllAction,
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => _applyAll(DuplicateResolution.skip),
                  child: const Text(
                    AppStrings.songImportDuplicateSkipAllAction,
                  ),
                ),
              ],
            ),
            const Divider(),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.duplicates.length,
                itemBuilder: (context, index) {
                  final dup = widget.duplicates[index];
                  final resolution = _resolutions[index];
                  return _DuplicateRow(
                    duplicate: dup,
                    resolution: resolution,
                    onChanged: (value) {
                      setState(() => _resolutions[index] = value);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(_buildResult()),
          child: const Text(AppStrings.songImportDuplicateConfirmAction),
        ),
      ],
    );
  }
}

class _DuplicateRow extends StatelessWidget {
  const _DuplicateRow({
    required this.duplicate,
    required this.resolution,
    required this.onChanged,
  });

  final ImportDuplicate duplicate;
  final DuplicateResolution resolution;
  final ValueChanged<DuplicateResolution> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(duplicate.incomingTitle)),
          SegmentedButton<DuplicateResolution>(
            segments: const [
              ButtonSegment(
                value: DuplicateResolution.overwrite,
                label: Text(AppStrings.songImportDuplicateOverwriteAction),
              ),
              ButtonSegment(
                value: DuplicateResolution.skip,
                label: Text(AppStrings.songImportDuplicateSkipAction),
              ),
            ],
            selected: {resolution},
            onSelectionChanged: (selection) {
              if (selection.isNotEmpty) {
                onChanged(selection.first);
              }
            },
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests**

```bash
cd apps/lyron_app && flutter test test/presentation/song_library/import_duplicate_dialog_test.dart --no-pub
```

Expected: all tests pass.

- [ ] **Step 5: Run full suite**

```bash
cd apps/lyron_app && flutter test --no-pub
```

Expected: `All tests passed!`

- [ ] **Step 6: Commit**

```bash
git add apps/lyron_app/lib/src/presentation/song_library/widgets/import_duplicate_dialog.dart \
        apps/lyron_app/test/presentation/song_library/import_duplicate_dialog_test.dart
git commit -m "feat: add ImportDuplicateDialog with TDD"
```

---

## Task 6: ImportSummaryDialog — tests first

**Files:**
- Create: `apps/lyron_app/test/presentation/song_library/import_summary_dialog_test.dart`
- Create: `apps/lyron_app/lib/src/presentation/song_library/widgets/import_summary_dialog.dart`

### 6a: Write failing widget test

- [ ] **Step 1: Create the test file**

```dart
// apps/lyron_app/test/presentation/song_library/import_summary_dialog_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/song_library/chordpro_import_types.dart';
import 'package:lyron_app/src/presentation/song_library/widgets/import_summary_dialog.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('shows correct imported count', (tester) async {
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showImportSummaryDialog(
              context: context,
              result: const ImportBatchResult(
                successes: [
                  ImportSuccess(title: 'Song A', source: ''),
                  ImportSuccess(title: 'Song B', source: ''),
                ],
                duplicates: [],
                errors: [],
              ),
              skippedCount: 0,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('2'), findsWidgets);
    expect(find.text(AppStrings.songImportSummaryImportedLabel), findsOneWidget);
  });

  testWidgets('shows skipped count', (tester) async {
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showImportSummaryDialog(
              context: context,
              result: const ImportBatchResult(
                successes: [],
                duplicates: [],
                errors: [],
              ),
              skippedCount: 3,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('3'), findsWidgets);
    expect(find.text(AppStrings.songImportSummarySkippedLabel), findsOneWidget);
  });

  testWidgets('shows error filenames when errors exist', (tester) async {
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showImportSummaryDialog(
              context: context,
              result: const ImportBatchResult(
                successes: [],
                duplicates: [],
                errors: [
                  ImportError(filename: 'bad.cho', reason: 'Üres fájl'),
                ],
              ),
              skippedCount: 0,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('bad.cho'), findsOneWidget);
    expect(find.text('Üres fájl'), findsOneWidget);
  });

  testWidgets('Kész button dismisses the dialog', (tester) async {
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showImportSummaryDialog(
              context: context,
              result: const ImportBatchResult(
                successes: [],
                duplicates: [],
                errors: [],
              ),
              skippedCount: 0,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.songImportSummaryDoneAction));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.songImportSummaryTitle), findsNothing);
  });
}
```

- [ ] **Step 2: Run to confirm compile error**

```bash
cd apps/lyron_app && flutter test test/presentation/song_library/import_summary_dialog_test.dart --no-pub
```

Expected: compile error — `showImportSummaryDialog` does not exist.

### 6b: Implement ImportSummaryDialog

- [ ] **Step 3: Create the widget file**

```dart
// apps/lyron_app/lib/src/presentation/song_library/widgets/import_summary_dialog.dart

import 'package:flutter/material.dart';
import 'package:lyron_app/src/application/song_library/chordpro_import_types.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

Future<void> showImportSummaryDialog({
  required BuildContext context,
  required ImportBatchResult result,
  required int skippedCount,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ImportSummaryDialog(
      result: result,
      skippedCount: skippedCount,
    ),
  );
}

class _ImportSummaryDialog extends StatelessWidget {
  const _ImportSummaryDialog({
    required this.result,
    required this.skippedCount,
  });

  final ImportBatchResult result;
  final int skippedCount;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(AppStrings.songImportSummaryTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CountRow(
            label: AppStrings.songImportSummaryImportedLabel,
            count: result.successes.length,
          ),
          _CountRow(
            label: AppStrings.songImportSummarySkippedLabel,
            count: skippedCount,
          ),
          _CountRow(
            label: AppStrings.songImportSummaryErrorsLabel,
            count: result.errors.length,
          ),
          if (result.errors.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(),
            ...result.errors.map(
              (e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.filename,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    Text(
                      e.reason,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(AppStrings.songImportSummaryDoneAction),
        ),
      ],
    );
  }
}

class _CountRow extends StatelessWidget {
  const _CountRow({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(label),
          const Spacer(),
          Text('$count'),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run dialog tests**

```bash
cd apps/lyron_app && flutter test test/presentation/song_library/import_summary_dialog_test.dart --no-pub
```

Expected: all tests pass.

- [ ] **Step 5: Run full suite**

```bash
cd apps/lyron_app && flutter test --no-pub
```

Expected: `All tests passed!`

- [ ] **Step 6: Commit**

```bash
git add apps/lyron_app/lib/src/presentation/song_library/widgets/import_summary_dialog.dart \
        apps/lyron_app/test/presentation/song_library/import_summary_dialog_test.dart
git commit -m "feat: add ImportSummaryDialog with TDD"
```

---

## Task 7: ChordProImportController + provider

**Files:**
- Create: `apps/lyron_app/lib/src/presentation/song_library/chordpro_import_controller.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_library/song_library_providers.dart`

- [ ] **Step 1: Create the controller**

```dart
// apps/lyron_app/lib/src/presentation/song_library/chordpro_import_controller.dart

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/application/song_library/active_catalog_context.dart';
import 'package:lyron_app/src/application/song_library/chordpro_import_service.dart';
import 'package:lyron_app/src/application/song_library/chordpro_import_types.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

sealed class ChordProImportState {
  const ChordProImportState();
}

class ImportIdle extends ChordProImportState {
  const ImportIdle();
}

class ImportPicking extends ChordProImportState {
  const ImportPicking();
}

class ImportAnalysing extends ChordProImportState {
  const ImportAnalysing();
}

class ImportAwaitingDuplicateResolution extends ChordProImportState {
  const ImportAwaitingDuplicateResolution(this.result, this.successes);

  final ImportBatchResult result;
  final List<ImportSuccess> successes;
}

class ImportCommitting extends ChordProImportState {
  const ImportCommitting({required this.progress, required this.total});

  final int progress;
  final int total;
}

class ImportDone extends ChordProImportState {
  const ImportDone({required this.result, required this.skippedCount});

  final ImportBatchResult result;
  final int skippedCount;
}

class ImportFailed extends ChordProImportState {
  const ImportFailed(this.message);

  final String message;
}

// ---------------------------------------------------------------------------
// Controller
// ---------------------------------------------------------------------------

class ChordProImportController extends StateNotifier<ChordProImportState> {
  ChordProImportController({
    required ChordProImportService importService,
    required ActiveCatalogContext? Function() contextReader,
  }) : _importService = importService,
       _contextReader = contextReader,
       super(const ImportIdle());

  final ChordProImportService _importService;
  final ActiveCatalogContext? Function() _contextReader;

  Future<void> startImport() async {
    final context = _contextReader();
    if (context == null) {
      state = const ImportFailed(AppStrings.songImportNoContextMessage);
      return;
    }

    state = const ImportPicking();

    FilePickerResult? picked;
    try {
      picked = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: kSupportedChordProExtensions.toList(),
        withData: true,
      );
    } catch (_) {
      state = const ImportIdle();
      return;
    }

    if (picked == null || picked.files.isEmpty) {
      state = const ImportIdle();
      return;
    }

    state = const ImportAnalysing();

    final fileInputs = <ImportFileInput>[];
    for (final platformFile in picked.files) {
      final source = await _readFile(platformFile);
      fileInputs.add(
        ImportFileInput(
          filename: platformFile.name,
          source: source ?? '',
        ),
      );
    }

    ImportBatchResult analysisResult;
    try {
      analysisResult = await _importService.analyse(
        context: context,
        files: fileInputs,
      );
    } catch (e) {
      state = ImportFailed(e.toString());
      return;
    }

    if (analysisResult.duplicates.isNotEmpty) {
      state = ImportAwaitingDuplicateResolution(
        analysisResult,
        analysisResult.successes,
      );
      return;
    }

    if (analysisResult.successes.isEmpty && analysisResult.duplicates.isEmpty) {
      state = ImportDone(result: analysisResult, skippedCount: 0);
      return;
    }

    await _commit(
      context: context,
      successes: analysisResult.successes,
      resolvedDuplicates: const [],
    );
  }

  Future<void> commitWithResolutions({
    required List<ImportSuccess> successes,
    required List<ResolvedDuplicate> resolvedDuplicates,
  }) async {
    final context = _contextReader();
    if (context == null) {
      state = const ImportFailed(AppStrings.songImportNoContextMessage);
      return;
    }
    await _commit(
      context: context,
      successes: successes,
      resolvedDuplicates: resolvedDuplicates,
    );
  }

  void reset() {
    state = const ImportIdle();
  }

  Future<void> _commit({
    required ActiveCatalogContext context,
    required List<ImportSuccess> successes,
    required List<ResolvedDuplicate> resolvedDuplicates,
  }) async {
    final total = successes.length +
        resolvedDuplicates
            .where((r) => r.resolution == DuplicateResolution.overwrite)
            .length;
    state = ImportCommitting(progress: 0, total: total);

    final skippedCount = resolvedDuplicates
        .where((r) => r.resolution == DuplicateResolution.skip)
        .length;

    ImportBatchResult finalResult;
    try {
      finalResult = await _importService.commitImport(
        context: context,
        successes: successes,
        resolvedDuplicates: resolvedDuplicates,
      );
    } catch (e) {
      state = ImportFailed(e.toString());
      return;
    }

    state = ImportDone(result: finalResult, skippedCount: skippedCount);
  }

  static Future<String?> _readFile(PlatformFile file) async {
    try {
      if (file.bytes != null) {
        return utf8.decode(file.bytes!, allowMalformed: false);
      }
      if (file.path != null) {
        return File(file.path!).readAsString();
      }
    } on FormatException {
      return null;
    } catch (_) {
      return null;
    }
    return null;
  }
}
```

- [ ] **Step 2: Wire the provider in `song_library_providers.dart`**

Add these imports at the top of `song_library_providers.dart` (after existing imports):

```dart
import 'package:lyron_app/src/application/song_library/chordpro_import_service.dart';
import 'package:lyron_app/src/presentation/song_library/chordpro_import_controller.dart';
```

Add at the end of `song_library_providers.dart` (before the file ends):

```dart
final chordProImportServiceProvider = Provider<ChordProImportService>((ref) {
  return ChordProImportService(
    songLibraryService: ref.watch(songLibraryServiceProvider),
    catalogReadRepository: ref.watch(songLibraryRepositoryProvider),
    normalizer: ChordproNormalizer(),
    parser: ChordproParser(),
  );
});

final chordProImportControllerProvider =
    StateNotifierProvider.autoDispose<ChordProImportController, ChordProImportState>(
  (ref) {
    return ChordProImportController(
      importService: ref.watch(chordProImportServiceProvider),
      contextReader: () => ref.read(activeCatalogContextProvider),
    );
  },
);
```

Also add the missing import for `ChordproNormalizer` at the top (it's not yet imported in `song_library_providers.dart`):

```dart
import 'package:lyron_app/src/infrastructure/song_library/chordpro/chordpro_normalizer.dart';
```

- [ ] **Step 3: Run full suite**

```bash
cd apps/lyron_app && flutter test --no-pub
```

Expected: `All tests passed!`

- [ ] **Step 4: Commit**

```bash
git add apps/lyron_app/lib/src/presentation/song_library/chordpro_import_controller.dart \
        apps/lyron_app/lib/src/presentation/song_library/song_library_providers.dart
git commit -m "feat: add ChordProImportController and wire provider"
```

---

## Task 8: Wire Import button in SongListScreen

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_library/song_list_screen.dart`

- [ ] **Step 1: Add imports to `song_list_screen.dart`**

At the top of `song_list_screen.dart`, add these imports after the existing ones:

```dart
import 'package:lyron_app/src/presentation/song_library/chordpro_import_controller.dart';
import 'package:lyron_app/src/presentation/song_library/widgets/import_duplicate_dialog.dart';
import 'package:lyron_app/src/presentation/song_library/widgets/import_summary_dialog.dart';
```

- [ ] **Step 2: Add `ref.listen` for import state in the `build` method**

Inside `_SongListScreenState.build()`, right after the existing `ref.listen(songLibraryBrowseControllerProvider.select(...))` block, add:

```dart
    ref.listen<ChordProImportState>(chordProImportControllerProvider, (
      previous,
      next,
    ) {
      if (!mounted) return;
      switch (next) {
        case ImportAwaitingDuplicateResolution(:final result, :final successes):
          unawaited(_resolveImportDuplicates(context, ref, result, successes));
        case ImportDone(:final result, :final skippedCount):
          unawaited(
            showImportSummaryDialog(
              context: context,
              result: result,
              skippedCount: skippedCount,
            ).then((_) {
              if (mounted) {
                ref.invalidate(songLibraryListProvider);
                ref.read(chordProImportControllerProvider.notifier).reset();
              }
            }),
          );
        case ImportFailed(:final message):
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );
          ref.read(chordProImportControllerProvider.notifier).reset();
        default:
          break;
      }
    });
```

- [ ] **Step 3: Add the Import `TextButton` in `AppBar.actions`**

In `SongListScreen`'s `AppBar`, add the Import button **before** the existing `TextButton` for `songCreateAction`. The `actions` list should read:

```dart
        actions: [
          const UnifiedSyncHeaderControl(),
          TextButton(
            onPressed: () {
              unawaited(
                ref.read(chordProImportControllerProvider.notifier).startImport(),
              );
            },
            child: const Text(AppStrings.songImportAction),
          ),
          TextButton(
            onPressed: () {
              unawaited(_createSong(context, ref));
            },
            child: const Text(AppStrings.songCreateAction),
          ),
          TextButton(
            onPressed: () {
              context.push(AppRoutes.planList.path);
            },
            child: const Text(AppStrings.planningEntryAction),
          ),
          TextButton(
            onPressed: () {
              unawaited(_signOut(context, ref));
            },
            child: const Text(AppStrings.signOutAction),
          ),
        ],
```

- [ ] **Step 4: Add `_resolveImportDuplicates` helper method** in `_SongListScreenState`:

```dart
  Future<void> _resolveImportDuplicates(
    BuildContext context,
    WidgetRef ref,
    ImportBatchResult result,
    List<ImportSuccess> successes,
  ) async {
    if (!mounted) return;
    final resolved = await showImportDuplicateDialog(
      context: context,
      duplicates: result.duplicates,
    );
    if (!mounted) return;
    if (resolved == null) {
      ref.read(chordProImportControllerProvider.notifier).reset();
      return;
    }
    await ref
        .read(chordProImportControllerProvider.notifier)
        .commitWithResolutions(
          successes: successes,
          resolvedDuplicates: resolved,
        );
  }
```

Also add the missing import for `ImportSuccess` and `ImportBatchResult` — these come from `chordpro_import_types.dart`, which is already transitively available via `chordpro_import_controller.dart`. Verify at compile time.

- [ ] **Step 5: Run full suite**

```bash
cd apps/lyron_app && flutter test --no-pub
```

Expected: `All tests passed!`

- [ ] **Step 6: Commit**

```bash
git add apps/lyron_app/lib/src/presentation/song_library/song_list_screen.dart
git commit -m "feat: add ChordPro import button to SongListScreen"
```

---

## Task 9: Final verification

- [ ] **Step 1: Run full test suite**

```bash
cd apps/lyron_app && flutter test --no-pub
```

Expected: `All tests passed!` with at least 20 more tests than baseline (586).

- [ ] **Step 2: Flutter analyze**

```bash
cd apps/lyron_app && flutter analyze --no-fatal-infos
```

Expected: `No issues found!`

- [ ] **Step 3: Update docs**

Update `docs/domain/domain-model.md` — add a note under the `songs` entity that ChordPro files can be bulk-imported from the local file system via the Import action in the song list.

- [ ] **Step 4: Final commit**

```bash
git add docs/domain/domain-model.md
git commit -m "docs: note ChordPro file import in domain model"
```

---

## Self-Review Checklist

- [x] **spec coverage: dependency** — Task 1 adds `file_picker ^8.0.0`
- [x] **spec coverage: types** — Task 2 creates all sealed types from spec
- [x] **spec coverage: analyse()** — Task 3 implements parse → duplicate-check
- [x] **spec coverage: commitImport()** — Task 3 implements create/update/skip
- [x] **spec coverage: readPlatformFile** — In `ChordProImportController._readFile` (Task 7), catches `FormatException` and returns null
- [x] **spec coverage: kSupportedChordProExtensions** — In types file, used by controller `pickFiles`
- [x] **spec coverage: empty file → error** — `analyse()` checks `source.trim().isEmpty`
- [x] **spec coverage: no title → filename stem** — `_stemOf()` in service
- [x] **spec coverage: duplicate dialog** — Task 5, shown from screen listener
- [x] **spec coverage: summary dialog** — Task 6, shown after `ImportDone`
- [x] **spec coverage: import button** — Task 8 adds `TextButton` in `AppBar`
- [x] **spec coverage: state machine** — `ImportIdle → Picking → Analysing → AwaitingDuplicateResolution | Committing → Done | Failed`
- [x] **spec coverage: all-errors skip duplicate dialog** — controller goes to `ImportDone` directly when no successes and no duplicates
- [x] **type consistency** — `ImportSuccess` carries `source` field (plan deviation from spec's `ImportFileInput`, rationale: avoids re-normalizing at commit time)
- [x] **no placeholders** — all steps have complete code
