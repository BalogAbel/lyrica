import 'package:flutter/material.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_fit.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/comment_line_view.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/directive_line_view.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_line_view.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/tab_block_view.dart';

class SongReaderSectionGrid extends StatelessWidget {
  const SongReaderSectionGrid({
    super.key,
    this.leadingDirectiveText,
    required this.sections,
    required this.viewMode,
    required this.sharedFontScale,
    required this.columnCount,
    required this.availableHeight,
  });

  final String? leadingDirectiveText;
  final List<SongReaderSectionProjection> sections;
  final SongReaderViewMode viewMode;
  final double sharedFontScale;
  final int columnCount;
  final double availableHeight;

  @override
  Widget build(BuildContext context) {
    final normalizedColumns = columnCount < 1 ? 1 : columnCount;
    return LayoutBuilder(
      builder: (context, constraints) {
        final fallbackWidth = MediaQuery.sizeOf(context).width;
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : fallbackWidth;
        final effectiveHeight = availableHeight.isFinite
            ? availableHeight
            : MediaQuery.sizeOf(context).height;

        final hasLeadingDirective = leadingDirectiveText != null;

        // Build flow blocks once — both the column decision and the renderer
        // walk the same block list so height estimates and rendering always agree.
        final blocks = buildFlowBlocks(
          sections: sections,
          hasLeadingDirective: hasLeadingDirective,
        );

        // Use [resolveFlowLayoutForSections] so the grid's column decision uses
        // the same logic as [estimateRenderedLayout] / [resolveFitFontScale].
        // This is the single source of truth: the fit calculator and the grid
        // both call the same resolver with the same tile width.
        final tileWidth = (availableWidth - sectionGap) / 2;
        final layout = resolveFlowLayoutForSections(
          sections: sections,
          viewMode: viewMode,
          tileWidth: tileWidth,
          availableHeight: effectiveHeight,
          fontScale: sharedFontScale,
          allowTwoColumns: normalizedColumns > 1,
          hasLeadingDirective: hasLeadingDirective,
        );
        final effectiveColumns = layout.columnCount;

        if (effectiveColumns == 1) {
          return Column(
            key: const Key('song-reader-section-grid-columns-1'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _buildBlockWidgets(
              blocks: blocks,
              startIndex: 0,
              endIndex: blocks.length,
              context: context,
            ),
          );
        }

        // Two-column layout: left = blocks[0:splitIndex], right = blocks[splitIndex:].
        final splitIndex = layout.splitIndex;
        return Row(
          key: Key('song-reader-section-grid-columns-$effectiveColumns'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: tileWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _buildBlockWidgets(
                  blocks: blocks,
                  startIndex: 0,
                  endIndex: splitIndex,
                  context: context,
                ),
              ),
            ),
            const SizedBox(width: sectionGap),
            SizedBox(
              width: tileWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _buildBlockWidgets(
                  blocks: blocks,
                  startIndex: splitIndex,
                  endIndex: blocks.length,
                  context: context,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Builds the widget list for blocks[startIndex:endIndex].
  ///
  /// Gap strategy (mirrors block-height accounting in [flowBlockHeight]):
  ///   - [FlowBlockKind.leadingDirective]: widget + SizedBox(sectionGap)
  ///   - [FlowBlockKind.sectionHeader]: widget + SizedBox(12) then lines follow
  ///   - [FlowBlockKind.line]: widget + SizedBox(lineGap=10)
  ///   - Between sections (wherever isSectionStart=true and the previous block was
  ///     a line), no extra gap is needed because sectionGap is already baked into
  ///     the first block of each section in the height estimate.  However, for the
  ///     RENDER we do not use height-budgeted SizedBoxes — we use the same visual
  ///     spacing that SongSectionView used: 12 after the header, 10 after each
  ///     line, and sectionGap between sections.
  ///
  /// The render inserts sectionGap before each section's first block (except for
  /// the very first block in a column) and uses the standard 12/10 px gaps within
  /// a section.  This matches the single-column behavior of the original
  /// _buildSingleColumn / SongSectionView.
  List<Widget> _buildBlockWidgets({
    required List<FlowBlock> blocks,
    required int startIndex,
    required int endIndex,
    required BuildContext context,
  }) {
    final widgets = <Widget>[];
    var isFirstInColumn = true;

    for (var i = startIndex; i < endIndex; i++) {
      final block = blocks[i];

      // Insert sectionGap before the start of each section (except the very
      // first block in this column).
      if (block.isSectionStart && !isFirstInColumn) {
        widgets.add(const SizedBox(height: sectionGap));
      }
      isFirstInColumn = false;

      switch (block.kind) {
        case FlowBlockKind.leadingDirective:
          widgets.add(_DirectiveLine(text: leadingDirectiveText!));
          // sectionGap follows the leading directive (same as before).
          widgets.add(const SizedBox(height: sectionGap));
          // Mark as consumed — next block won't insert an extra sectionGap.
          isFirstInColumn = true; // suppress gap before the next block
          break;

        case FlowBlockKind.sectionHeader:
          widgets.add(_buildHeaderWidget(block, context));
          widgets.add(const SizedBox(height: 12));
          break;

        case FlowBlockKind.line:
          widgets.add(_buildLineWidget(block, context));
          widgets.add(const SizedBox(height: 10));
          break;
      }
    }

    return widgets;
  }

  Widget _buildHeaderWidget(FlowBlock block, BuildContext context) {
    final theme = Theme.of(context);
    final section = sections[block.sectionIndex];
    final label = _sectionLabel(section)!;
    final labelColor = section.isUnknown
        ? theme.colorScheme.tertiary
        : theme.colorScheme.primary;
    return Text(
      label,
      style: theme.textTheme.titleLarge?.copyWith(color: labelColor),
    );
  }

  Widget _buildLineWidget(FlowBlock block, BuildContext context) {
    final item = block.line!;
    return switch (item) {
      SongReaderLyricLineProjection() => SongLineView(
        line: item,
        viewMode: viewMode,
        sharedFontScale: sharedFontScale,
      ),
      SongReaderCommentProjection() => CommentLineView(
        projection: item,
        sharedFontScale: sharedFontScale,
      ),
      SongReaderTabProjection() => TabBlockView(
        projection: item,
        sharedFontScale: sharedFontScale,
      ),
      SongReaderDirectiveProjection() => DirectiveLineView(projection: item),
    };
  }

  /// Returns a display label for [section], or null if the section is unlabeled.
  /// Mirrors the [_sectionLabel] logic from [SongSectionView].
  static String? _sectionLabel(SongReaderSectionProjection section) {
    final isUnlabeled = section.label == 'Unlabeled' && section.number == null;
    if (isUnlabeled) return null;
    if (section.number == null) return section.label;
    return '${section.label} ${section.number}';
  }
}

class _DirectiveLine extends StatelessWidget {
  const _DirectiveLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        key: const Key('song-reader-capo-directive-line'),
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.02,
        ),
      ),
    );
  }
}
