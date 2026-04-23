import 'package:flutter/material.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_header.dart';

class SongReaderCompactOverlay extends StatelessWidget {
  const SongReaderCompactOverlay({
    super.key,
    required this.isVisible,
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

  final bool isVisible;
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
    if (!isVisible) {
      return const SizedBox.shrink();
    }

    return Align(
      alignment: Alignment.topCenter,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SongReaderHeader(
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
        ),
      ),
    );
  }
}
