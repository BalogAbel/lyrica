import 'package:lyron_app/src/domain/song/song_key_layers.dart';

enum SongReaderViewMode { chordsAndLyrics, lyricsOnly }

enum SongReaderControlPresentationMode { overlay, pinned }

enum SongReaderInstrumentDisplayMode { guitar, piano }

/// The reader's temporary key layer (PS5): absolute transpose/capo values
/// the `±` controls set, tied to the reader instance that set them. [ownerId]
/// names that instance (the screen builds it from the open item and the
/// reader visit), so a layer left in a state that outlives the screen never
/// shows on another song or a reopened reader.
class SongReaderTemporaryLayer {
  const SongReaderTemporaryLayer({
    required this.ownerId,
    this.transpose,
    this.capo,
  });

  final String ownerId;
  final int? transpose;
  final int? capo;

  int? valueOf(SongKeyField field) => switch (field) {
    SongKeyField.transpose => transpose,
    SongKeyField.capo => capo,
  };

  /// This layer with [field] set to [value] (null clears it), or null when
  /// both fields end up null.
  SongReaderTemporaryLayer? withValue(SongKeyField field, int? value) {
    final nextTranspose = field == SongKeyField.transpose ? value : transpose;
    final nextCapo = field == SongKeyField.capo ? value : capo;
    if (nextTranspose == null && nextCapo == null) {
      return null;
    }
    return SongReaderTemporaryLayer(
      ownerId: ownerId,
      transpose: nextTranspose,
      capo: nextCapo,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SongReaderTemporaryLayer &&
      other.ownerId == ownerId &&
      other.transpose == transpose &&
      other.capo == capo;

  @override
  int get hashCode => Object.hash(ownerId, transpose, capo);
}

class SongReaderState {
  static const minSharedFontScale = 0.25;
  static const maxSharedFontScale = 3.0;
  static const defaultSharedFontScale = 1.0;

  SongReaderState({
    this.viewMode = SongReaderViewMode.chordsAndLyrics,
    this.instrumentDisplayMode = SongReaderInstrumentDisplayMode.guitar,
    double sharedFontScale = 1.0,
    this.areCompactControlsVisible = false,
    this.controlPresentationMode = SongReaderControlPresentationMode.overlay,
    this.isAutoFitEnabled = true,
    this.temporaryLayer,
  }) : sharedFontScale = _normalizeSharedFontScale(sharedFontScale);

  final SongReaderViewMode viewMode;
  final SongReaderInstrumentDisplayMode instrumentDisplayMode;
  final double sharedFontScale;
  final bool areCompactControlsVisible;
  final SongReaderControlPresentationMode controlPresentationMode;
  final bool isAutoFitEnabled;
  final SongReaderTemporaryLayer? temporaryLayer;

  /// The temporary layer, only when [ownerId] set it.
  SongReaderTemporaryLayer? temporaryLayerFor(String ownerId) =>
      temporaryLayer?.ownerId == ownerId ? temporaryLayer : null;

  /// A copy with [layer] as the temporary layer; null clears it. [copyWith]
  /// cannot clear it (null means "keep" there), so this is the only way.
  SongReaderState withTemporaryLayer(SongReaderTemporaryLayer? layer) {
    return SongReaderState(
      viewMode: viewMode,
      instrumentDisplayMode: instrumentDisplayMode,
      sharedFontScale: sharedFontScale,
      areCompactControlsVisible: areCompactControlsVisible,
      controlPresentationMode: controlPresentationMode,
      isAutoFitEnabled: isAutoFitEnabled,
      temporaryLayer: layer,
    );
  }

  SongReaderState copyWith({
    SongReaderViewMode? viewMode,
    SongReaderInstrumentDisplayMode? instrumentDisplayMode,
    double? sharedFontScale,
    bool? areCompactControlsVisible,
    SongReaderControlPresentationMode? controlPresentationMode,
    bool? isAutoFitEnabled,
  }) {
    return SongReaderState(
      viewMode: viewMode ?? this.viewMode,
      instrumentDisplayMode:
          instrumentDisplayMode ?? this.instrumentDisplayMode,
      sharedFontScale: sharedFontScale ?? this.sharedFontScale,
      areCompactControlsVisible:
          areCompactControlsVisible ?? this.areCompactControlsVisible,
      controlPresentationMode:
          controlPresentationMode ?? this.controlPresentationMode,
      isAutoFitEnabled: isAutoFitEnabled ?? this.isAutoFitEnabled,
      temporaryLayer: temporaryLayer,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SongReaderState &&
        other.viewMode == viewMode &&
        other.instrumentDisplayMode == instrumentDisplayMode &&
        other.sharedFontScale == sharedFontScale &&
        other.areCompactControlsVisible == areCompactControlsVisible &&
        other.controlPresentationMode == controlPresentationMode &&
        other.isAutoFitEnabled == isAutoFitEnabled &&
        other.temporaryLayer == temporaryLayer;
  }

  @override
  int get hashCode => Object.hash(
    viewMode,
    instrumentDisplayMode,
    sharedFontScale,
    areCompactControlsVisible,
    controlPresentationMode,
    isAutoFitEnabled,
    temporaryLayer,
  );

  static double _normalizeSharedFontScale(double value) {
    if (!value.isFinite || value <= 0) {
      return defaultSharedFontScale;
    }

    if (value < minSharedFontScale) {
      return minSharedFontScale;
    }

    if (value > maxSharedFontScale) {
      return maxSharedFontScale;
    }

    return value;
  }
}
