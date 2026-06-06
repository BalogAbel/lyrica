import 'package:flutter/material.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_expanded_context_panel.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_expanded_tools_panel.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_section_grid.dart';

class SongReaderExpandedSurface extends StatefulWidget {
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
    required this.contentPadding,
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
  /// Padding applied around the song content grid inside the scroll view.
  final EdgeInsetsGeometry contentPadding;

  @override
  State<SongReaderExpandedSurface> createState() =>
      _SongReaderExpandedSurfaceState();
}

class _SongReaderExpandedSurfaceState
    extends State<SongReaderExpandedSurface> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 240,
          child: Align(
            alignment: Alignment.topLeft,
            child: widget.showContextPanel
                ? SongReaderExpandedContextPanel(
                    previousTitle: widget.previousTitle,
                    nextTitle: widget.nextTitle,
                    onPreviousTap: widget.onPreviousTap,
                    onNextTap: widget.onNextTap,
                  )
                : const SizedBox.shrink(),
          ),
        ),
        const SizedBox(width: 24),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final availableHeight = constraints.maxHeight;
              return Scrollbar(
                controller: _scrollController,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  // The outer Row governs this column's width; no ConstrainedBox
                  // needed. Padding lives inside so the scrollbar thumb reaches
                  // the physical edge.
                  child: Padding(
                    padding: widget.contentPadding,
                    child: SongReaderSectionGrid(
                      leadingDirectiveText:
                          widget.projection.capoDirectiveText,
                      sections: widget.projection.sections,
                      viewMode: widget.projection.viewMode,
                      sharedFontScale: widget.projection.sharedFontScale,
                      columnCount: widget.contentColumnCount,
                      availableHeight: availableHeight,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 24),
        SizedBox(
          width: 320,
          child: SongReaderExpandedToolsPanel(
            projection: widget.projection,
            hasRecoverableWarnings: widget.hasRecoverableWarnings,
            warningCount: widget.warningCount,
            onToggleViewMode: widget.onToggleViewMode,
            onTransposeDown: widget.onTransposeDown,
            onTransposeUp: widget.onTransposeUp,
            onCapoDown: widget.onCapoDown,
            onCapoUp: widget.onCapoUp,
            onDecreaseFontScale: widget.onDecreaseFontScale,
            onIncreaseFontScale: widget.onIncreaseFontScale,
          ),
        ),
      ],
    );
  }
}
