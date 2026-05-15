import 'package:flutter/material.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';

class CommentLineView extends StatelessWidget {
  const CommentLineView({
    super.key,
    required this.projection,
    required this.sharedFontScale,
  });

  final SongReaderCommentProjection projection;
  final double sharedFontScale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      projection.text,
      style: theme.textTheme.bodyMedium?.copyWith(
        fontSize:
            (theme.textTheme.bodyMedium?.fontSize ?? 14) * sharedFontScale,
        fontStyle: FontStyle.italic,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
        height: 1.4,
      ),
    );
  }
}
