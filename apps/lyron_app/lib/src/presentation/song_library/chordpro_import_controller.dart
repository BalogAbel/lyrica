import 'dart:convert';

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
  const ImportCommitting();
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
    final readErrors = <ImportError>[];
    for (final platformFile in picked.files) {
      final (:source, :errorReason) = await _readFile(platformFile);
      if (source == null) {
        readErrors.add(
          ImportError(filename: platformFile.name, reason: errorReason!),
        );
      } else {
        fileInputs.add(
          ImportFileInput(filename: platformFile.name, source: source),
        );
      }
    }

    ImportBatchResult analysisResult;
    try {
      final partial = await _importService.analyse(
        context: context,
        files: fileInputs,
      );
      analysisResult = readErrors.isEmpty
          ? partial
          : ImportBatchResult(
              successes: partial.successes,
              duplicates: partial.duplicates,
              errors: [...partial.errors, ...readErrors],
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
    state = const ImportCommitting();

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

  static Future<({String? source, String? errorReason})> _readFile(
    PlatformFile file,
  ) async {
    final bytes = file.bytes;
    if (bytes == null) {
      return (source: null, errorReason: AppStrings.songImportReadErrorReason);
    }
    try {
      return (
        source: utf8.decode(bytes, allowMalformed: false),
        errorReason: null,
      );
    } on FormatException {
      return (source: null, errorReason: AppStrings.songImportUtf8ErrorReason);
    } catch (_) {
      return (source: null, errorReason: AppStrings.songImportReadErrorReason);
    }
  }
}
