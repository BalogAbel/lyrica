import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_riverpod/misc.dart' show KeepAliveLink;
import 'package:lyron_app/src/application/song_library/active_catalog_context.dart';
import 'package:lyron_app/src/application/song_library/chordpro_import_service.dart';
import 'package:lyron_app/src/application/song_library/chordpro_import_types.dart';
import 'package:lyron_app/src/application/song_library/import_run_tracker.dart';
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
  const ImportAwaitingDuplicateResolution(
    this.result,
    this.successes, {
    required this.context,
  });

  final ImportBatchResult result;
  final List<ImportSuccess> successes;

  /// IR1 (docs/specs/2026-10-11-import-run-ownership.md): the catalog
  /// context the run analysed these files against. The commit that resumes
  /// the run is given this context and writes into it and nothing else.
  final ActiveCatalogContext context;
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

/// SO7 (docs/specs/2026-10-07-sign-out-pending-work-guard.md): whether an
/// import run is in a phase that writes pending work in the background with
/// the context it captured, or that ends on its own without further user
/// input. [ImportAwaitingDuplicateResolution] is not one: nothing is written
/// until the user resolves the duplicates in the modal dialog, and with no
/// dialog (the song list was replaced) nothing can resolve them, so it must
/// not block anything forever.
bool isImportRunning(ChordProImportState state) => switch (state) {
  ImportPicking() || ImportAnalysing() || ImportCommitting() => true,
  ImportIdle() ||
  ImportAwaitingDuplicateResolution() ||
  ImportDone() ||
  ImportFailed() => false,
};

class ChordProImportController extends StateNotifier<ChordProImportState> {
  ChordProImportController({
    required this._importService,
    required this._contextReader,
    this._keepAlive,
    this._runTracker,
  }) : super(const ImportIdle());

  final ChordProImportService _importService;
  final ActiveCatalogContext? Function() _contextReader;
  final KeepAliveLink Function()? _keepAlive;
  final ImportRunTracker? _runTracker;
  KeepAliveLink? _runLink;

  /// RW3: the user of the catalog context the current run captured.
  String? _runUserId;

  @override
  set state(ChordProImportState value) {
    // SO7: a run keeps the provider alive until it ends, so the state the
    // sign-out guard reads stays truthful even if the song list was replaced.
    // The link is settled before the listeners run: StateNotifier notifies
    // them synchronously and rethrows a listener's error afterwards, which
    // must not skip the release.
    // RW3: the tracker follows the same transitions, settled before the
    // listeners run for the same reason, and a disposed instance never
    // reports running again.
    final running = isImportRunning(value);
    if (running) {
      _runLink ??= _keepAlive?.call();
    } else {
      _runLink?.close();
      _runLink = null;
    }
    _runTracker?.report(this, userId: _runUserId, running: running && mounted);
    super.state = value;
  }

  @override
  void dispose() {
    _runTracker?.report(this, userId: null, running: false);
    super.dispose();
  }

  Future<void> startImport() async {
    // SO7: a second run would overwrite the first run's state, and the first
    // run's end would then report a running import as finished.
    if (isImportRunning(state)) {
      return;
    }
    try {
      await _runImport();
    } finally {
      _endRun();
    }
  }

  Future<void> _runImport() async {
    final context = _contextReader();
    if (context == null) {
      state = const ImportFailed(AppStrings.songImportNoContextMessage);
      return;
    }

    _runUserId = context.userId;
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

    // IR2 (docs/specs/2026-10-11-import-run-ownership.md): a run parks at the
    // dialog, or ends in the summary, only while it is still in the catalog it
    // analysed against. The picker or the analysis may have straddled a user
    // switch, and the dialog would list this run's titles to whoever is
    // current now. Nothing is written; _commit checks again before it writes.
    if (_contextReader() != context) {
      state = const ImportFailed(AppStrings.songImportContextChangedMessage);
      return;
    }

    if (analysisResult.duplicates.isNotEmpty) {
      state = ImportAwaitingDuplicateResolution(
        analysisResult,
        analysisResult.successes,
        context: context,
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

  /// IR1: [context] is the context of the run whose duplicates were
  /// resolved (the awaiting state's), never read from the live provider
  /// here; the live context is only compared against it, in [_commit].
  Future<void> commitWithResolutions({
    required ActiveCatalogContext context,
    required List<ImportSuccess> successes,
    required List<ResolvedDuplicate> resolvedDuplicates,
  }) async {
    // One run at a time, as startImport.
    if (isImportRunning(state)) {
      return;
    }
    try {
      _runUserId = context.userId;
      await _commit(
        context: context,
        successes: successes,
        resolvedDuplicates: resolvedDuplicates,
      );
    } finally {
      _endRun();
    }
  }

  /// RW3: whatever ended the run -- a normal end, a caught failure, a
  /// picker cancel, a throw nothing caught, or a dispose -- leaves no
  /// running phase behind, so neither SO7's sign-out refusal nor the
  /// different-user wipe's refusal can stay engaged after the run.
  void _endRun() {
    if (!mounted) {
      _runTracker?.report(this, userId: null, running: false);
      return;
    }
    if (isImportRunning(state)) {
      state = const ImportFailed(AppStrings.songImportInterruptedMessage);
    }
  }

  void reset() {
    // SO7: a reset cannot stop a run that is writing; it would only hide it
    // from the sign-out guard. A run ends on its own.
    if (isImportRunning(state)) {
      return;
    }
    state = const ImportIdle();
  }

  Future<void> _commit({
    required ActiveCatalogContext context,
    required List<ImportSuccess> successes,
    required List<ResolvedDuplicate> resolvedDuplicates,
  }) async {
    // IR2 (docs/specs/2026-10-11-import-run-ownership.md): the run writes
    // only into the catalog it analysed against, and only while that is
    // still the active one. The user, the organization or the context
    // itself may have changed while the dialog or the picker was open
    // (R17, R16). Nothing is written; the state becomes ImportFailed, so
    // a run that was in a running phase releases the tracker and SO7's
    // link through the state setter as for any other end.
    if (_contextReader() != context) {
      state = const ImportFailed(AppStrings.songImportContextChangedMessage);
      return;
    }
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
