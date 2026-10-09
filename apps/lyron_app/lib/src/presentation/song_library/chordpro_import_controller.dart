import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_riverpod/misc.dart' show KeepAliveLink;
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

/// SO7 (docs/specs/2026-10-07-sign-out-pending-work-guard.md): an import run
/// writes pending work in the background with the context it captured.
bool isImportRunning(ChordProImportState state) => switch (state) {
  ImportPicking() ||
  ImportAnalysing() ||
  ImportAwaitingDuplicateResolution() ||
  ImportCommitting() => true,
  ImportIdle() || ImportDone() || ImportFailed() => false,
};

class ChordProImportController extends StateNotifier<ChordProImportState> {
  ChordProImportController({
    required this._importService,
    required this._contextReader,
    this._keepAlive,
  }) : super(const ImportIdle());

  final ChordProImportService _importService;
  final ActiveCatalogContext? Function() _contextReader;
  final KeepAliveLink Function()? _keepAlive;
  KeepAliveLink? _runLink;

  @override
  set state(ChordProImportState value) {
    super.state = value;
    // SO7: a run keeps the provider alive until it ends, so the state the
    // sign-out guard reads stays truthful even if the song list was replaced.
    if (isImportRunning(value)) {
      _runLink ??= _keepAlive?.call();
    } else {
      _runLink?.close();
      _runLink = null;
    }
  }

  Future<void> startImport() async {
    // SO7: a second run would overwrite the first run's state, and the first
    // run's end would then report a running import as finished.
    if (isImportRunning(state)) {
      return;
    }
    final context = _contextReader();
    if (context == null) {
      state = const ImportFailed(AppStrings.songImportNoContextMessage);
      return;
    }

    state = const ImportPicking();

    FilePickerResult? picked;
    try {
      // file_picker 11 moved these to static methods; there is no
      // FilePicker.platform instance any more.
      picked = await FilePicker.pickFiles(
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
    final readResults = await Future.wait(picked.files.map(_readFile));
    for (var i = 0; i < picked.files.length; i++) {
      final platformFile = picked.files[i];
      final (:source, :errorReason) = readResults[i];
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
