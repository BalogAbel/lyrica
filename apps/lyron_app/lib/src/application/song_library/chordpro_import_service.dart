import 'package:lyron_app/src/application/song_library/active_catalog_context.dart';
import 'package:lyron_app/src/application/song_library/chordpro_import_types.dart';
import 'package:lyron_app/src/application/song_library/song_catalog_read_repository.dart';
import 'package:lyron_app/src/application/song_library/song_library_service.dart';
import 'package:lyron_app/src/infrastructure/song_library/chordpro/chordpro_normalizer.dart';
import 'package:lyron_app/src/infrastructure/song_library/chordpro/chordpro_parser.dart';
import 'package:lyron_app/src/shared/app_strings.dart';
import 'package:path/path.dart' as p;

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
        errors.add(ImportError(filename: file.filename, reason: AppStrings.songImportEmptyFileReason));
        continue;
      }

      String normalizedSource;
      String title;
      try {
        normalizedSource = _normalizer.normalize(file.source);
        final parsed = _parser.parse(normalizedSource);
        final rawTitle = parsed.title.trim();
        title = rawTitle.isNotEmpty ? rawTitle : _stemOf(file.filename);
      } catch (_) {
        errors.add(
          ImportError(
            filename: file.filename,
            reason: AppStrings.songImportReadErrorReason,
          ),
        );
        continue;
      }

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
        successes.add(ImportSuccess(title: title, source: normalizedSource, filename: file.filename));
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
        errors.add(ImportError(filename: success.filename, reason: e.toString()));
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
            filename: resolved.duplicate.filename,
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

  static String _stemOf(String filename) => p.basenameWithoutExtension(filename);
}
