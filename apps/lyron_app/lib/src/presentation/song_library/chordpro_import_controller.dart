import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/application/song_library/active_catalog_context.dart';
import 'package:lyron_app/src/application/song_library/chordpro_import_service.dart';
import 'package:lyron_app/src/application/song_library/chordpro_import_types.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

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

class ChordProImportController extends StateNotifier<ChordProImportState> {
  ChordProImportController({
    required ChordProImportService importService,
    required ActiveCatalogContext? Function() contextReader,
  })  : _importService = importService,
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
