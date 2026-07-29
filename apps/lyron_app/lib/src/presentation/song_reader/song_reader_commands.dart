import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/presentation/song_reader/session_scoped_reader_runtime_controller.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_controller.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_immersive_mode.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';

/// Reader command dispatch: routes view-mode/transpose/capo/font-scale/
/// compact-controls commands to either the scoped session runtime controller
/// (multi-song plan sessions) or the screen's local [SongReaderController],
/// depending on `isScopedMode`.
///
/// Takes a `WidgetRef` directly (like `SongReaderSongActions`) rather than
/// being a widget — it is not part of the widget tree. It never calls
/// `setState` and never holds the `State` object: [onChanged] is the
/// screen's `() => setState(() {})`, invoked after mutating [controller] so
/// the observable sequence (mutate, then rebuild) matches the original
/// `_updateState` exactly.
class SongReaderCommands {
  const SongReaderCommands({required this.controller, required this.onChanged});

  final SongReaderController controller;
  final VoidCallback onChanged;

  void _updateState(void Function(SongReaderController controller) update) {
    update(controller);
    onChanged();
  }

  void toggleViewMode({
    required WidgetRef ref,
    required bool isScopedMode,
    required String sessionKey,
  }) {
    if (isScopedMode) {
      ref
          .read(sessionScopedReaderRuntimeControllerProvider(sessionKey))
          .toggleViewMode();
      return;
    }

    _updateState((controller) => controller.toggleViewMode());
  }

  void transposeDown({
    required WidgetRef ref,
    required bool isScopedMode,
    required String sessionKey,
  }) {
    if (isScopedMode) {
      ref
          .read(sessionScopedReaderRuntimeControllerProvider(sessionKey))
          .transposeDown();
      return;
    }

    _updateState((controller) => controller.transposeDown());
  }

  void transposeUp({
    required WidgetRef ref,
    required bool isScopedMode,
    required String sessionKey,
  }) {
    if (isScopedMode) {
      ref
          .read(sessionScopedReaderRuntimeControllerProvider(sessionKey))
          .transposeUp();
      return;
    }

    _updateState((controller) => controller.transposeUp());
  }

  void capoDown({
    required WidgetRef ref,
    required bool isScopedMode,
    required String sessionKey,
  }) {
    if (isScopedMode) {
      ref
          .read(sessionScopedReaderRuntimeControllerProvider(sessionKey))
          .capoDown();
      return;
    }

    _updateState((controller) => controller.capoDown());
  }

  void capoUp({
    required WidgetRef ref,
    required bool isScopedMode,
    required String sessionKey,
  }) {
    if (isScopedMode) {
      ref
          .read(sessionScopedReaderRuntimeControllerProvider(sessionKey))
          .capoUp();
      return;
    }

    _updateState((controller) => controller.capoUp());
  }

  void setInstrumentDisplayMode(
    SongReaderInstrumentDisplayMode mode, {
    required WidgetRef ref,
    required bool isScopedMode,
    required String sessionKey,
  }) {
    if (isScopedMode) {
      ref
          .read(sessionScopedReaderRuntimeControllerProvider(sessionKey))
          .setInstrumentDisplayMode(mode);
      return;
    }

    _updateState((controller) => controller.setInstrumentDisplayMode(mode));
  }

  void adjustSharedFontScale(
    double delta, {
    required WidgetRef ref,
    required bool isScopedMode,
    required String sessionKey,
    required VoidCallback persistFontScale,
  }) {
    if (isScopedMode) {
      final runtimeController = ref.read(
        sessionScopedReaderRuntimeControllerProvider(sessionKey),
      );
      runtimeController.setSharedFontScale(
        runtimeController.state.readerState.sharedFontScale + delta,
      );
      persistFontScale();
      return;
    }

    _updateState((controller) {
      controller.setSharedFontScale(controller.state.sharedFontScale + delta);
    });
    persistFontScale();
  }

  void setSharedFontScale(
    double scale, {
    required WidgetRef ref,
    required bool isScopedMode,
    required String sessionKey,
  }) {
    if (isScopedMode) {
      final runtimeController = ref.read(
        sessionScopedReaderRuntimeControllerProvider(sessionKey),
      );
      runtimeController.setSharedFontScale(scale);
      return;
    }

    _updateState((controller) {
      controller.setSharedFontScale(scale);
    });
  }

  void toggleCompactControls({
    required WidgetRef ref,
    required bool isScopedMode,
    required String sessionKey,
    required SongReaderImmersiveMode immersiveMode,
  }) {
    if (isScopedMode) {
      final runtimeController = ref.read(
        sessionScopedReaderRuntimeControllerProvider(sessionKey),
      );
      runtimeController.toggleCompactControls();
      immersiveMode.apply(
        runtimeController.state.readerState.areCompactControlsVisible,
      );
      return;
    }

    _updateState((controller) => controller.toggleCompactControls());
    immersiveMode.apply(controller.state.areCompactControlsVisible);
  }
}
