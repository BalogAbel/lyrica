import 'package:flutter/material.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/comment_line_view.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/directive_line_view.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_line_view.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/tab_block_view.dart';

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
    final labelColor = section.isUnknown
        ? theme.colorScheme.tertiary
        : theme.colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label,
            style: theme.textTheme.titleLarge?.copyWith(color: labelColor),
          ),
          const SizedBox(height: 12),
        ],
        for (final item in section.lines) ...[
          switch (item) {
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
            SongReaderDirectiveProjection() =>
              DirectiveLineView(projection: item),
          },
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  String? _sectionLabel(SongReaderSectionProjection section) {
    final isUnlabeled = section.label == 'Unlabeled' && section.number == null;
    if (isUnlabeled) return null;
    if (section.number == null) return section.label;
    return '${section.label} ${section.number}';
  }
}
