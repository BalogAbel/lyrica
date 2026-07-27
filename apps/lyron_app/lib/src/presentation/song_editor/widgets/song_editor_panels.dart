import 'package:flutter/material.dart';
import 'package:lyron_app/src/presentation/song_editor/song_editor_projection.dart';
import 'package:lyron_app/src/presentation/song_editor/song_editor_state.dart';
import 'package:lyron_app/src/presentation/song_editor/widgets/song_editor_stepper.dart';
import 'package:lyron_app/src/presentation/song_editor/widgets/song_editor_summary_list.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_section_grid.dart';

class SongEditorOverviewPanel extends StatelessWidget {
  const SongEditorOverviewPanel({super.key, required this.projection});

  final SongEditorProjection projection;

  @override
  Widget build(BuildContext context) {
    return SongEditorPanelShell(
      key: const ValueKey('song-editor-overview-shell'),
      title: 'Derived summary',
      expandChild: false,
      child: SongEditorSummaryList(projection: projection),
    );
  }
}

class SongEditorCanonicalPanel extends StatelessWidget {
  const SongEditorCanonicalPanel({
    super.key,
    required this.projection,
    required this.sourceController,
    required this.isEditable,
    required this.onSourceChanged,
    required this.onTransposeDown,
    required this.onTransposeUp,
    required this.onCapoDown,
    required this.onCapoUp,
    required this.canonicalViewMode,
    required this.onCanonicalViewChanged,
    this.showToggle = true,
  });

  final SongEditorProjection projection;
  final TextEditingController sourceController;
  final bool isEditable;
  final ValueChanged<String> onSourceChanged;
  final VoidCallback onTransposeDown;
  final VoidCallback onTransposeUp;
  final VoidCallback onCapoDown;
  final VoidCallback onCapoUp;
  final SongEditorCanonicalViewMode canonicalViewMode;
  final ValueChanged<SongEditorCanonicalViewMode> onCanonicalViewChanged;
  final bool showToggle;

  @override
  Widget build(BuildContext context) {
    final showSource = canonicalViewMode == SongEditorCanonicalViewMode.source;

    return SongEditorPanelShell(
      title: 'Canonical source',
      trailing: showToggle
          ? TextButton(
              onPressed: () => onCanonicalViewChanged(
                showSource
                    ? SongEditorCanonicalViewMode.preview
                    : SongEditorCanonicalViewMode.source,
              ),
              child: Text(showSource ? 'Preview' : 'Source'),
            )
          : null,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 160),
        child: showSource
            ? SongEditorSourcePanel(
                key: const ValueKey('song-editor-source-mode'),
                projection: projection,
                controller: sourceController,
                isEditable: isEditable,
                onSourceChanged: onSourceChanged,
                onTransposeDown: onTransposeDown,
                onTransposeUp: onTransposeUp,
                onCapoDown: onCapoDown,
                onCapoUp: onCapoUp,
              )
            : SongEditorPreviewPanel(
                key: const ValueKey('song-editor-preview-mode'),
                projection: projection,
              ),
      ),
    );
  }
}

class SongEditorSourcePanel extends StatelessWidget {
  const SongEditorSourcePanel({
    super.key,
    required this.projection,
    required this.controller,
    required this.isEditable,
    required this.onSourceChanged,
    required this.onTransposeDown,
    required this.onTransposeUp,
    required this.onCapoDown,
    required this.onCapoUp,
  });

  final SongEditorProjection projection;
  final TextEditingController controller;
  final bool isEditable;
  final ValueChanged<String> onSourceChanged;
  final VoidCallback onTransposeDown;
  final VoidCallback onTransposeUp;
  final VoidCallback onCapoDown;
  final VoidCallback onCapoUp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      key: const ValueKey('song-editor-source-panel'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SongEditorStepper(
                label: 'Transpose',
                value: projection.summaryTranspose,
                onDecrease: onTransposeDown,
                onIncrease: onTransposeUp,
                enabled: isEditable,
              ),
              SongEditorStepper(
                label: 'Capo',
                value: projection.summaryCapo,
                onDecrease: onCapoDown,
                onIncrease: onCapoUp,
                enabled: isEditable,
              ),
            ],
          ),
          const SizedBox(height: 16),
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: controller,
                enabled: isEditable,
                minLines: 16,
                maxLines: null,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14,
                  height: 1.45,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isCollapsed: true,
                ),
                onChanged: onSourceChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SongEditorPreviewPanel extends StatelessWidget {
  const SongEditorPreviewPanel({super.key, required this.projection});

  final SongEditorProjection projection;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const ValueKey('song-editor-preview-panel'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            projection.summaryTitle,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            projection.previewSubtitle,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          SongReaderSectionGrid(
            leadingDirectiveText: projection.preview.capoDirectiveText,
            sections: projection.preview.sections,
            viewMode: SongReaderViewMode.chordsAndLyrics,
            sharedFontScale: projection.preview.sharedFontScale,
            columnCount: 1,
            availableHeight: 0,
          ),
        ],
      ),
    );
  }
}

class SongEditorPanelShell extends StatelessWidget {
  const SongEditorPanelShell({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.expandChild = true,
  });

  final String title;
  final Widget child;
  final Widget? trailing;
  final bool expandChild;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: EdgeInsets.all(expandChild ? 20 : 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: expandChild ? MainAxisSize.max : MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: expandChild
                        ? Theme.of(context).textTheme.headlineSmall
                        : Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                ...?trailing == null ? null : [trailing!],
              ],
            ),
            const SizedBox(height: 16),
            if (expandChild) Expanded(child: child) else child,
          ],
        ),
      ),
    );
  }
}
