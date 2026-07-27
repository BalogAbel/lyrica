import 'package:flutter/material.dart';
import 'package:lyron_app/src/presentation/song_editor/song_editor_projection.dart';

class SongEditorSummaryList extends StatelessWidget {
  const SongEditorSummaryList({super.key, required this.projection});

  final SongEditorProjection projection;

  @override
  Widget build(BuildContext context) {
    final rows = [
      ('Title', projection.summaryTitle),
      ('Artist', projection.summaryArtist),
      ('Key', projection.summaryKey),
      ('Tempo', projection.summaryTempo),
      ('Tags', projection.summaryTags),
      (
        'Settings',
        'Transpose ${projection.summaryTranspose} · Capo ${projection.summaryCapo}',
      ),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in rows) ...[
          _SummaryRow(label: row.$1, value: row.$2),
          if (row != rows.last) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.45,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 56,
              child: Text(
                label,
                style: theme.textTheme.labelSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                value,
                style: theme.textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
