import 'package:flutter/material.dart';
import 'package:lyron_app/src/app/reader_theme.dart';
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
    final style = ReaderTheme.of(context).commentStyle;
    return Text(
      projection.text,
      style: style.copyWith(
        fontSize: (style.fontSize ?? 14) * sharedFontScale,
      ),
    );
  }
}
