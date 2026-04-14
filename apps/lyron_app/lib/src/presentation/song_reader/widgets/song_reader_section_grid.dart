import 'package:flutter/material.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_section_view.dart';

class SongReaderSectionGrid extends StatelessWidget {
  const SongReaderSectionGrid({
    super.key,
    required this.sections,
    required this.viewMode,
    required this.sharedFontScale,
    required this.columnCount,
    required this.availableHeight,
  });

  final List<SongReaderSectionProjection> sections;
  final SongReaderViewMode viewMode;
  final double sharedFontScale;
  final int columnCount;
  final double availableHeight;

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
        final shouldUseMultipleColumns =
            normalizedColumns > 1 &&
            _singleColumnHeightEstimate(
                  sourceSections: normalizedSections,
                  maxColumnWidth: availableWidth,
                ) >
                effectiveHeight;
        final effectiveColumns = shouldUseMultipleColumns
            ? normalizedColumns
            : 1;

        if (effectiveColumns == 1) {
          return Column(
            key: const Key('song-reader-section-grid-columns-1'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final section in normalizedSections) ...[
                SongSectionView(
                  section: section,
                  viewMode: viewMode,
                  sharedFontScale: sharedFontScale,
                ),
                const SizedBox(height: 20),
              ],
            ],
          );
        }

        const spacing = 20.0;
        final tileWidth =
            (availableWidth - (effectiveColumns - 1) * spacing) /
            effectiveColumns;
        final columns = _buildColumnMajorSections(
          sections: normalizedSections,
          columnCount: effectiveColumns,
          maxColumnWidth: tileWidth,
        );

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
    var total = 0.0;
    for (final section in sourceSections) {
      total += _estimatedSectionHeight(section, maxColumnWidth);
    }
    return total;
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
        .map((section) => _estimatedSectionHeight(section, maxColumnWidth))
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

  double _estimatedSectionHeight(
    SongReaderSectionProjection section,
    double maxWidth,
  ) {
    final hasHeader = !(section.label == 'Unlabeled' && section.number == null);
    final headerHeight = hasHeader ? 40.0 : 0.0;
    final effectiveLineWidth = (maxWidth - 24).clamp(120.0, 1200.0);
    final charsPerLine = (effectiveLineWidth / (10.0 * sharedFontScale))
        .floor()
        .clamp(12, 140);
    var linesHeight = 0.0;
    for (final line in section.lines) {
      final text = line.segments.map((segment) => segment.text).join();
      final lyricLength = text.trimRight().length;
      final hasChord =
          viewMode == SongReaderViewMode.chordsAndLyrics &&
          line.segments.any((segment) => segment.displayChord != null);
      final wrapCount = lyricLength == 0
          ? 1
          : (lyricLength / charsPerLine).ceil().clamp(1, 14);
      final chordRowHeight = hasChord ? (20 * sharedFontScale) : 0.0;
      final lyricRowsHeight = wrapCount * (24 * sharedFontScale);
      linesHeight += chordRowHeight + lyricRowsHeight + 10;
    }
    return headerHeight + linesHeight + 20;
  }
}
