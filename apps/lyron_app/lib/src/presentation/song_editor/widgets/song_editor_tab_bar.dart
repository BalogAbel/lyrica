import 'package:flutter/material.dart';

enum SongEditorTab { overview, source, preview }

class SongEditorTabBar extends StatelessWidget {
  const SongEditorTabBar({
    super.key,
    required this.selectedTab,
    required this.onSelectedTab,
  });

  final SongEditorTab selectedTab;
  final ValueChanged<SongEditorTab> onSelectedTab;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final entry in {
          SongEditorTab.overview: 'Overview',
          SongEditorTab.source: 'Source',
          SongEditorTab.preview: 'Preview',
        }.entries)
          ChoiceChip(
            label: Text(entry.value),
            selected: selectedTab == entry.key,
            onSelected: (_) => onSelectedTab(entry.key),
          ),
      ],
    );
  }
}
