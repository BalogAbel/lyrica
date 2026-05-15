import 'package:flutter/material.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';

class DirectiveLineView extends StatelessWidget {
  const DirectiveLineView({super.key, required this.projection});

  final SongReaderDirectiveProjection projection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = projection.value != null
        ? '{${projection.name}: ${projection.value}}'
        : '{${projection.name}}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.tertiary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
