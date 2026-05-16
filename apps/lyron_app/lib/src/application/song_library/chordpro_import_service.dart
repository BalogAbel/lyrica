import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:lyron_app/src/application/song_library/active_catalog_context.dart';
import 'package:lyron_app/src/application/song_library/chordpro_import_types.dart';
import 'package:lyron_app/src/application/song_library/song_catalog_read_repository.dart';
import 'package:lyron_app/src/application/song_library/song_library_service.dart';
import 'package:lyron_app/src/infrastructure/song_library/chordpro/chordpro_normalizer.dart';
import 'package:lyron_app/src/infrastructure/song_library/chordpro/chordpro_parser.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

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

  /// Read a [PlatformFile] as UTF-8 text. Returns null on any failure — never throws.
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
        errors.add(ImportError(filename: file.filename, reason: AppStrings.songImportEmptyFileReason));
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
        errors.add(ImportError(filename: success.title, reason: e.toString()));
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
    final name = filename.contains('/') ? filename.split('/').last : filename;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }
}
