import 'package:flutter/material.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_expanded_context_panel.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_expanded_tools_panel.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_section_grid.dart';

class SongReaderExpandedSurface extends StatelessWidget {
  const SongReaderExpandedSurface({
    super.key,
    required this.projection,
    required this.showContextPanel,
    required this.hasRecoverableWarnings,
    required this.warningCount,
    required this.contentColumnCount,
    required this.onToggleViewMode,
    required this.onTransposeDown,
    required this.onTransposeUp,
    this.onCapoDown,
    this.onCapoUp,
    required this.onDecreaseFontScale,
    required this.onIncreaseFontScale,
    this.previousTitle,
    this.nextTitle,
    this.onPreviousTap,
    this.onNextTap,
  });

  final SongReaderProjection projection;
  final bool showContextPanel;
  final String? previousTitle;
  final String? nextTitle;
  final VoidCallback? onPreviousTap;
  final VoidCallback? onNextTap;
  final bool hasRecoverableWarnings;
  final int warningCount;
  final int contentColumnCount;
  final VoidCallback onToggleViewMode;
  final VoidCallback onTransposeDown;
  final VoidCallback onTransposeUp;
  final VoidCallback? onCapoDown;
  final VoidCallback? onCapoUp;
  final VoidCallback onDecreaseFontScale;
  final VoidCallback onIncreaseFontScale;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 240,
          child: Align(
            alignment: Alignment.topLeft,
            child: showContextPanel
                ? SongReaderExpandedContextPanel(
                    previousTitle: previousTitle,
                    nextTitle: nextTitle,
                    onPreviousTap: onPreviousTap,
                    onNextTap: onNextTap,
                  )
                : const SizedBox.shrink(),
          ),
        ),
        const SizedBox(width: 24),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      child: SongReaderSectionGrid(
                        leadingDirectiveText: projection.capoDirectiveText,
                        sections: projection.sections,
                        viewMode: projection.viewMode,
                        sharedFontScale: projection.sharedFontScale,
                        columnCount: contentColumnCount,
                        availableHeight: constraints.maxHeight,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 24),
        SizedBox(
          width: 320,
          child: SongReaderExpandedToolsPanel(
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
      ],
    );
  }
}
