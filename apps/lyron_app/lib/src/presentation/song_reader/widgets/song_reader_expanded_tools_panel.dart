import 'package:flutter/material.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_header.dart';

class SongReaderExpandedToolsPanel extends StatelessWidget {
  const SongReaderExpandedToolsPanel({
    super.key,
    required this.projection,
    required this.hasRecoverableWarnings,
    required this.warningCount,
    required this.onToggleViewMode,
    required this.onTransposeDown,
    required this.onTransposeUp,
    this.onCapoDown,
    this.onCapoUp,
    required this.onDecreaseFontScale,
    required this.onIncreaseFontScale,
  });

  final SongReaderProjection projection;
  final bool hasRecoverableWarnings;
  final int warningCount;
  final VoidCallback onToggleViewMode;
  final VoidCallback onTransposeDown;
  final VoidCallback onTransposeUp;
  final VoidCallback? onCapoDown;
  final VoidCallback? onCapoUp;
  final VoidCallback onDecreaseFontScale;
  final VoidCallback onIncreaseFontScale;

  @override
  Widget build(BuildContext context) {
    return SongReaderHeader(
      projection: projection,
      hasRecoverableWarnings: hasRecoverableWarnings,
      warningCount: warningCount,
      onToggleViewMode: onToggleViewMode,
      onTransposeDown: onTransposeDown,
      onTransposeUp: onTransposeUp,
      onCapoDown: onCapoDown,
      onCapoUp: onCapoUp,
      onDecreaseFontScale: onDecreaseFontScale,
      onIncreaseFontScale: onIncreaseFontScale,
    );
  }
}
