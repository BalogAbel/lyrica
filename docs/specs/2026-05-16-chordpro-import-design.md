# ChordPro File Import — Design Spec

**Date:** 2026-05-16  
**Status:** Approved  
**Scope:** Single and bulk ChordPro file import via file picker (Android, iOS, Web)

---

## Problem

Songs can only enter the library through manual ChordPro text entry in the song editor. There is no way to import existing `.cho` / `.chordpro` / `.chopro` files from the device file system or the web. Users with existing ChordPro collections must re-type every song.

---

## Goals

- Import one or multiple ChordPro files from the device file system (Android, iOS) or browser file input (Web).
- Detect duplicates and ask the user how to resolve them.
- Show a final summary (imported / skipped / errors) after bulk import.
- Keep the extension list easily extensible without code changes in multiple places.
- Share / Open-in intent support is **deferred** to a future slice.

---

## Non-Goals

- Share / Open-in intent (Android intent filter, iOS URL scheme) — deferred.
- Fuzzy duplicate matching — MVP uses exact title-only match (case-insensitive).
- ZIP or folder import.
- Format conversion from non-ChordPro formats.

---

## Architecture

### New files

```
apps/lyron_app/lib/src/application/song_library/
  chordpro_import_service.dart
  chordpro_import_types.dart

apps/lyron_app/lib/src/presentation/song_library/
  chordpro_import_controller.dart
  widgets/import_duplicate_dialog.dart
  widgets/import_summary_dialog.dart

apps/lyron_app/test/application/song_library/
  chordpro_import_service_test.dart

apps/lyron_app/test/presentation/song_library/
  import_duplicate_dialog_test.dart
  import_summary_dialog_test.dart
```

### Modified files

```
apps/lyron_app/pubspec.yaml                          — add file_picker dependency
apps/lyron_app/lib/src/presentation/song_library/song_list_screen.dart
                                                     — add Import action
apps/lyron_app/lib/src/application/providers.dart    — wire ChordProImportService
```

### Unchanged / reused

- `ChordproNormalizer`, `ChordproParser` — no changes needed.
- `SongLibraryService.createSong()` / `updateSong()` — called by import service.
- `SongCatalogReadRepository` — used for duplicate lookup.

---

## Domain types

```dart
// chordpro_import_types.dart

/// Supported file extensions. Extend this set to add new formats.
const Set<String> kSupportedChordProExtensions = {
  'cho',
  'chordpro',
  'chopro',
};

sealed class ImportFileResult {
  const ImportFileResult();
}

class ImportSuccess extends ImportFileResult {
  const ImportSuccess({required this.title});
  final String title;
}

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

---

## Application layer: ChordProImportService

```dart
class ChordProImportService {
  const ChordProImportService({
    required SongLibraryService songLibraryService,
    required SongCatalogReadRepository catalogReadRepository,
    required ChordproNormalizer normalizer,
    required ChordproParser parser,
  });

  /// Parse files and categorise each as success / duplicate / error.
  /// Does NOT write to the database yet — caller resolves duplicates first.
  Future<ImportBatchResult> analyse(List<ImportFileInput> files);

  /// Execute import after duplicate resolution is known.
  Future<void> commitImport({
    required List<ImportFileInput> successes,
    required List<ResolvedDuplicate> resolvedDuplicates,
  });
}
```

### ImportFileInput

```dart
class ImportFileInput {
  const ImportFileInput({required this.filename, required this.source});
  final String filename;
  final String source; // raw UTF-8 ChordPro text
}
```

### Duplicate detection

1. For each file: `ChordproNormalizer.normalize(source)` → `ChordproParser.parse()`.
2. Extract `title` from `ParsedSong.title` (falls back to filename stem if absent).
3. Load existing summaries from `SongCatalogReadRepository.listSongs()`.
4. Match: `title.trim().toLowerCase() == existingSummary.title.trim().toLowerCase()` (title-only; `SongSummary` does not carry artist).
5. Exact title match → `ImportDuplicate`. No match → proceed to `ImportSuccess`.

Note: Artist-based disambiguation is deferred to a future slice when `SongSummary` gains an artist field.

---

## Presentation layer

### ChordProImportController (Riverpod AsyncNotifier)

States:

```
idle
→ picking (file_picker open)
→ analysing (parsing files)
→ awaitingDuplicateResolution(ImportBatchResult)
→ committing(progress: int, total: int)
→ done(ImportBatchResult finalResult)
→ error(String message)
```

Transitions:

1. `startImport()` → invoke `file_picker` with `allowMultiple: true`, extensions from `kSupportedChordProExtensions`.
2. Read each `PlatformFile`: web uses `.bytes`, mobile reads from `.path`. UTF-8 decode errors are caught inside the reader and returned as `ImportError`; they do not bubble as exceptions.
3. Call `ChordProImportService.analyse()` → `analysing`.
4. If `result.duplicates.isNotEmpty` → `awaitingDuplicateResolution`.
   If `result.duplicates.isEmpty` (all successes and/or errors) → skip to `committing` immediately.
   If every file resulted in an error (no successes, no duplicates) → transition directly to `done`.
5. `commitImport({successes, resolvedDuplicates})` → `committing` → `done`.

### ImportDuplicateDialog

- Lists each duplicate: incoming title vs existing title.
- Per-item toggle: **Felülírja** / **Kihagyja**.
- "Mindent felülír" / "Mindent kihagy" bulk action.
- Confirm button → returns `List<ResolvedDuplicate>`.

### ImportSummaryDialog

- Shows counts: `N dal importálva`, `M kihagyva`, `K hiba`.
- Error section (collapsible) lists filenames + reasons.
- Single "Kész" button to dismiss.

### UI entry point

`SongListScreen` — add an **Import** `IconButton` (or menu item) next to the existing create-song action. Tapping it calls `ChordProImportController.startImport()`.

---

## File reading strategy

```dart
Future<String?> readPlatformFile(PlatformFile file) async {
  try {
    // Web: bytes are already in memory
    if (file.bytes != null) {
      return utf8.decode(file.bytes!, allowMalformed: false);
    }
    // Mobile/desktop: read from path
    if (file.path != null) {
      return File(file.path!).readAsString();
    }
  } on FormatException {
    return null; // caller maps null → ImportError("Nem UTF-8 fájl")
  } catch (_) {
    return null; // caller maps null → ImportError("Nem olvasható")
  }
  return null; // no bytes and no path → ImportError
}
```

`readPlatformFile` never throws. It returns `null` on any read or decode failure; the caller converts `null` to the appropriate `ImportError`.

---

## Error cases

| Situation | Result |
|---|---|
| File unreadable / no path + no bytes | `ImportError("Nem olvasható")` |
| Malformed UTF-8 | `ImportError("Nem UTF-8 fájl")` |
| Empty file | `ImportError("Üres fájl")` |
| Parse yields no sections | `ImportSuccess` — valid ChordPro without section markers; raw source is stored and re-parsed correctly by the reader |
| No `{title:}` directive | Filename stem used as title |
| Network error on save | `ImportError(songLibraryService error message)` |

---

## Tests

### Unit: `ChordProImportServiceTest`

- Single valid file → `ImportSuccess`
- File with `{title:}` matching existing song → `ImportDuplicate`
- Empty file → `ImportError`
- Malformed UTF-8 bytes → `ImportError`
- Bulk: 3 files, 1 success + 1 duplicate + 1 error → correct counts
- `commitImport` with overwrite resolution → calls `updateSong`
- `commitImport` with skip resolution → does NOT call `updateSong`

### Widget: `ImportDuplicateDialogTest`

- Renders all duplicate rows
- Toggle per-item resolution
- "Mindent felülír" applies to all rows
- Returns correct `List<ResolvedDuplicate>` on confirm

### Widget: `ImportSummaryDialogTest`

- Shows correct counts
- Error section shows filenames

---

## Dependency

Add to `pubspec.yaml`:

```yaml
file_picker: ^8.0.0
```

`file_picker` supports Android, iOS, macOS, Windows, Linux, Web without additional platform configuration for basic file picking.

---

## Future slices (deferred)

- **Share / Open-in intent** — Android intent filter + iOS CFBundleDocumentTypes/LSItemContentTypes setup.
- **Artist-based duplicate matching** — requires `SongSummary` to carry artist field.
- **Fuzzy duplicate matching** — Levenshtein or phonetic on title.
- **ZIP import** — unzip + batch import all ChordPro files inside.
