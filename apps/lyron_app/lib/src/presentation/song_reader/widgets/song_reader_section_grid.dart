import 'package:flutter/material.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_fit.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_section_view.dart';

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
  static const _columnHeightToleranceFactor = 1.15;

  @override
  Widget build(BuildContext context) {
    final normalizedSections = sections;
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
        final leadingDirectiveHeight = leadingDirectiveText == null
            ? 0.0
            : directiveLineHeight;
        final shouldUseMultipleColumns =
            normalizedColumns > 1 &&
            _singleColumnHeightEstimate(
                      sourceSections: normalizedSections,
                      maxColumnWidth: availableWidth,
                    ) +
                    leadingDirectiveHeight >
                effectiveHeight;
        var effectiveColumns = shouldUseMultipleColumns ? normalizedColumns : 1;

        if (effectiveColumns == 1) {
          return _buildSingleColumn(normalizedSections);
        }

        const spacing = sectionGap;
        final tileWidth =
            (availableWidth - (effectiveColumns - 1) * spacing) /
            effectiveColumns;
        final columns = _buildColumnMajorSections(
          sections: normalizedSections,
          columnCount: effectiveColumns,
          maxColumnWidth: tileWidth,
        );
        final estimatedColumnHeights = columns
            .map((column) => _columnHeightEstimate(column, tileWidth))
            .toList(growable: false);
        if (leadingDirectiveHeight > 0 && estimatedColumnHeights.isNotEmpty) {
          estimatedColumnHeights[0] += leadingDirectiveHeight;
        }
        final tallestColumn = estimatedColumnHeights.fold<double>(
          0,
          (maxHeight, height) => height > maxHeight ? height : maxHeight,
        );
        if (tallestColumn > effectiveHeight * _columnHeightToleranceFactor) {
          effectiveColumns = 1;
          return _buildSingleColumn(normalizedSections);
        }

        return Row(
          key: Key('song-reader-section-grid-columns-$effectiveColumns'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < columns.length; index++) ...[
              SizedBox(
                width: tileWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (index == 0 && leadingDirectiveText != null) ...[
                      _DirectiveLine(text: leadingDirectiveText!),
                      const SizedBox(height: spacing),
                    ],
                    for (final section in columns[index]) ...[
                      SongSectionView(
                        section: section,
                        viewMode: viewMode,
                        sharedFontScale: sharedFontScale,
                      ),
                      const SizedBox(height: spacing),
                    ],
                  ],
                ),
              ),
              if (index < columns.length - 1) const SizedBox(width: spacing),
            ],
          ],
        );
      },
    );
  }

  double _singleColumnHeightEstimate({
    required List<SongReaderSectionProjection> sourceSections,
    required double maxColumnWidth,
  }) {
    return estimateSongContentHeight(
      sections: sourceSections,
      viewMode: viewMode,
      availableWidth: maxColumnWidth,
      fontScale: sharedFontScale,
    );
  }

  Widget _buildSingleColumn(List<SongReaderSectionProjection> sections) {
    return Column(
      key: const Key('song-reader-section-grid-columns-1'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (leadingDirectiveText != null) ...[
          _DirectiveLine(text: leadingDirectiveText!),
          const SizedBox(height: sectionGap),
        ],
        for (final section in sections) ...[
          SongSectionView(
            section: section,
            viewMode: viewMode,
            sharedFontScale: sharedFontScale,
          ),
          const SizedBox(height: sectionGap),
        ],
      ],
    );
  }

  double _columnHeightEstimate(
    List<SongReaderSectionProjection> sections,
    double maxColumnWidth,
  ) {
    return estimateSongContentHeight(
      sections: sections,
      viewMode: viewMode,
      availableWidth: maxColumnWidth,
      fontScale: sharedFontScale,
    );
  }

  List<List<SongReaderSectionProjection>> _buildColumnMajorSections({
    required List<SongReaderSectionProjection> sections,
    required int columnCount,
    required double maxColumnWidth,
  }) {
    if (columnCount == 2) {
      final splitIndex = _bestTwoColumnSplitIndex(
        sections,
        maxColumnWidth: maxColumnWidth,
      );
      return [
        sections.sublist(0, splitIndex),
        sections.sublist(splitIndex),
      ].where((column) => column.isNotEmpty).toList(growable: false);
    }

    final columns = List.generate(
      columnCount,
      (_) => <SongReaderSectionProjection>[],
    );
    var start = 0;
    for (var columnIndex = 0; columnIndex < columnCount; columnIndex += 1) {
      final columnsLeft = columnCount - columnIndex;
      final chunkSize = ((sections.length - start) / columnsLeft).ceil();
      final end = (start + chunkSize).clamp(start, sections.length);
      columns[columnIndex].addAll(sections.sublist(start, end));
      start = end;
      if (start >= sections.length) {
        break;
      }
    }

    return columns.where((column) => column.isNotEmpty).toList(growable: false);
  }

  int _bestTwoColumnSplitIndex(
    List<SongReaderSectionProjection> sections, {
    required double maxColumnWidth,
  }) {
    if (sections.length <= 1) {
      return sections.length;
    }

    final sectionHeights = sections
        .map(
          (section) => estimateSectionHeight(
            section: section,
            viewMode: viewMode,
            maxWidth: maxColumnWidth,
            fontScale: sharedFontScale,
          ),
        )
        .toList(growable: false);
    final totalHeight = sectionHeights.fold<double>(
      0,
      (sum, value) => sum + value,
    );

    var runningLeft = 0.0;
    var bestIndex = 1;
    var bestDiff = double.infinity;

    for (var split = 1; split < sections.length; split += 1) {
      runningLeft += sectionHeights[split - 1];
      final right = totalHeight - runningLeft;
      if (runningLeft < right) {
        continue;
      }
      final diff = runningLeft - right;
      if (diff < bestDiff) {
        bestDiff = diff;
        bestIndex = split;
      }
    }

    return bestIndex;
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
