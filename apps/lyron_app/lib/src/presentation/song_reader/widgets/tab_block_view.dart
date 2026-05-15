import 'package:flutter/material.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';

class TabBlockView extends StatelessWidget {
  const TabBlockView({
    super.key,
    required this.projection,
    required this.sharedFontScale,
  });

  final SongReaderTabProjection projection;
  final double sharedFontScale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: 13.0 * sharedFontScale,
      height: 1.5,
      color: theme.colorScheme.onSurface,
    );
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final rawLine in projection.rawLines)
              Text(rawLine, style: textStyle),
          ],
        ),
      ),
    );
  }
}
