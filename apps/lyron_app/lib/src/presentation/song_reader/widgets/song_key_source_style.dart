import 'package:flutter/material.dart';
import 'package:lyron_app/src/domain/song/song_key_layers.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

/// The word that names the layer a key value comes from (PS25). Exhaustive:
/// a new [SongKeyLayerId] fails to compile here until it has a label.
String songKeySourceLabel(SongKeyLayerId id) => switch (id) {
  SongKeyLayerId.song => AppStrings.songReaderKeySourceSong,
  SongKeyLayerId.plan => AppStrings.songReaderKeySourcePlan,
  SongKeyLayerId.temporary => AppStrings.songReaderKeySourceTemporary,
};

/// The chip colors of a key source, always from the theme's [scheme] (PS25).
/// The word never relies on color alone; the colors tell the layers apart at a
/// glance.
({Color background, Color foreground}) songKeySourceColors(
  ColorScheme scheme,
  SongKeyLayerId id,
) => switch (id) {
  SongKeyLayerId.song => (
    background: scheme.surfaceContainerHighest,
    foreground: scheme.onSurface,
  ),
  SongKeyLayerId.plan => (
    background: scheme.primaryContainer,
    foreground: scheme.onPrimaryContainer,
  ),
  SongKeyLayerId.temporary => (
    background: scheme.tertiaryContainer,
    foreground: scheme.onTertiaryContainer,
  ),
};
