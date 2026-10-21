import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/domain/song/song_key_layers.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_key_source_style.dart';

void main() {
  test('every source has its own label', () {
    expect(songKeySourceLabel(SongKeyLayerId.song), 'Song');
    expect(songKeySourceLabel(SongKeyLayerId.plan), 'Plan');
    expect(songKeySourceLabel(SongKeyLayerId.temporary), 'Temporary');
  });

  test('every source takes its colors from the color scheme', () {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.teal);

    expect(songKeySourceColors(scheme, SongKeyLayerId.song), (
      background: scheme.surfaceContainerHighest,
      foreground: scheme.onSurface,
    ));
    expect(songKeySourceColors(scheme, SongKeyLayerId.plan), (
      background: scheme.primaryContainer,
      foreground: scheme.onPrimaryContainer,
    ));
    expect(songKeySourceColors(scheme, SongKeyLayerId.temporary), (
      background: scheme.tertiaryContainer,
      foreground: scheme.onTertiaryContainer,
    ));
  });

  test('the three sources are told apart by background', () {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.teal);

    final backgrounds = {
      for (final id in SongKeyLayerId.values)
        songKeySourceColors(scheme, id).background,
    };
    expect(backgrounds, hasLength(SongKeyLayerId.values.length));
  });
}
