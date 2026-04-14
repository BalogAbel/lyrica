import 'package:flutter/material.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_line_view.dart';

class SongSectionView extends StatelessWidget {
  const SongSectionView({
    super.key,
    required this.section,
    required this.viewMode,
    required this.sharedFontScale,
  });

  final SongReaderSectionProjection section;
  final SongReaderViewMode viewMode;
  final double sharedFontScale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = _sectionLabel(section);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[Text(label, style: theme.textTheme.titleLarge)],
        for (final line in section.lines) ...[
          SongLineView(
            line: line,
            viewMode: viewMode,
            sharedFontScale: sharedFontScale,
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  String? _sectionLabel(SongReaderSectionProjection section) {
    final isUnlabeled = section.label == 'Unlabeled' && section.number == null;
    if (isUnlabeled) {
      return null;
    }

    if (section.number == null) {
      return section.label;
    }

    return '${section.label} ${section.number}';
  }
}
