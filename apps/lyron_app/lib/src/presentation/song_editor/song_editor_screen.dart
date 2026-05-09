import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_types.dart';
import 'package:lyron_app/src/presentation/song_editor/song_editor_controller.dart';
import 'package:lyron_app/src/presentation/song_editor/song_editor_projection.dart';
import 'package:lyron_app/src/presentation/song_editor/song_editor_state.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_section_grid.dart';
import 'package:lyron_app/src/router/app_routes.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

enum _TabletTab { overview, source, preview }

class SongEditorScreen extends ConsumerStatefulWidget {
  const SongEditorScreen({
    super.key,
    required this.songId,
    required this.songSlug,
    this.initialSource,
  });

  final String songId;
  final String songSlug;
  final String? initialSource;

  @override
  ConsumerState<SongEditorScreen> createState() => _SongEditorScreenState();
}

class _SongEditorScreenState extends ConsumerState<SongEditorScreen> {
  static const _wideBreakpoint = 980.0;
  static const _contentMaxWidth = 1200.0;
  static const _editorMinHeight = 360.0;
  static const _sourceSample = SongEditorController.defaultSource;

  final SongEditorController _controller = SongEditorController();
  late final TextEditingController _sourceController;
  _TabletTab _tabletTab = _TabletTab.source;
  String _savedSource = _sourceSample;
  bool _isDirty = false;

  @override
  void initState() {
    super.initState();
    final seedSource = widget.initialSource ?? _sourceSample;
    _controller.setSource(seedSource);
    _sourceController = TextEditingController(text: seedSource);
    _savedSource = seedSource;
    _isDirty = false;
  }

  @override
  void didUpdateWidget(covariant SongEditorScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextSource = widget.initialSource;
    if (nextSource == null ||
        nextSource == oldWidget.initialSource ||
        _isDirty) {
      return;
    }

    if (nextSource != _controller.state.source) {
      _controller.setSource(nextSource);
      _sourceController.text = nextSource;
      _savedSource = nextSource;
      _isDirty = false;
    }
  }

  @override
  void dispose() {
    _sourceController.dispose();
    super.dispose();
  }

  void _setSource(String source) {
    setState(() {
      _controller.setSource(source);
      _isDirty = true;
    });
  }

  void _transposeDown() {
    setState(() {
      _controller.transposeDown();
      _sourceController.text = _controller.state.source;
      _isDirty = true;
    });
  }

  void _transposeUp() {
    setState(() {
      _controller.transposeUp();
      _sourceController.text = _controller.state.source;
      _isDirty = true;
    });
  }

  void _capoDown() {
    setState(() {
      _controller.capoDown();
      _sourceController.text = _controller.state.source;
      _isDirty = true;
    });
  }

  void _capoUp() {
    setState(() {
      _controller.capoUp();
      _sourceController.text = _controller.state.source;
      _isDirty = true;
    });
  }

  void _commitChanges() {
    setState(() {
      _savedSource = _controller.state.source;
      _isDirty = false;
    });
  }

  void _cancelChanges() {
    setState(() {
      _controller.setSource(_savedSource);
      _sourceController.text = _savedSource;
      _isDirty = false;
    });
  }

  String _songViewLocation() {
    return AppRoutes.songReader.path.replaceFirst(':songSlug', widget.songSlug);
  }

  void _returnToSongView(BuildContext context) {
    _cancelChanges();
    context.replace(_songViewLocation());
  }

  Future<void> _saveAndReturn(BuildContext context) async {
    final activeContext = ref.read(activeCatalogContextProvider);
    if (activeContext == null) {
      _returnToSongView(context);
      return;
    }

    final service = ref.read(songLibraryServiceProvider);
    final projection = SongEditorProjection(state: _controller.state);
    try {
      await service.updateSong(
        context: activeContext,
        songId: widget.songId,
        title: projection.summaryTitle,
        chordproSource: _controller.state.source,
      );
    } on SongConflictResolutionRequiredException {
      if (!context.mounted) {
        return;
      }
      await _showConflictResolutionRequiredDialog(context);
      return;
    }

    if (!mounted) {
      return;
    }

    ref.invalidate(songLibraryListProvider);
    ref.invalidate(songMutationEntriesProvider);
    ref.invalidate(songLibraryReaderProvider(widget.songId));
    _commitChanges();
    context.replace(_songViewLocation());
  }

  Future<void> _showConflictResolutionRequiredDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AppStrings.songConflictTitle),
        content: const Text(AppStrings.songConflictMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(AppStrings.songCancelAction),
          ),
        ],
      ),
    );
  }

  void _handleBack(BuildContext context) {
    if (context.canPop()) {
      context.pop();
      return;
    }

    context.replace(_songViewLocation());
  }

  void _setCanonicalView(SongEditorCanonicalViewMode mode) {
    setState(() {
      _controller.setCanonicalViewMode(mode);
      _tabletTab = switch (mode) {
        SongEditorCanonicalViewMode.source => _TabletTab.source,
        SongEditorCanonicalViewMode.preview => _TabletTab.preview,
      };
    });
  }

  void _setTabletTab(_TabletTab tab) {
    setState(() {
      _tabletTab = tab;
      if (tab == _TabletTab.source) {
        _controller.setCanonicalViewMode(SongEditorCanonicalViewMode.source);
      } else if (tab == _TabletTab.preview) {
        _controller.setCanonicalViewMode(SongEditorCanonicalViewMode.preview);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final projection = SongEditorProjection(state: _controller.state);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= _wideBreakpoint;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _TopBar(
                        songId: widget.songId,
                        onBack: () => _handleBack(context),
                        canCancel: _isDirty,
                        canSave: _isDirty,
                        onSave: () => _saveAndReturn(context),
                        onCancel: () => _returnToSongView(context),
                      ),
                      const SizedBox(height: 16),
                      _StatusBanner(
                        diagnosticCount:
                            projection.state.parsedSong.diagnostics.length,
                      ),
                      const SizedBox(height: 16),
                      if (isWide)
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 240,
                                child: _OverviewPanel(projection: projection),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                flex: 2,
                                child: _CanonicalPanel(
                                  projection: projection,
                                  sourceController: _sourceController,
                                  isEditable: true,
                                  onSourceChanged: _setSource,
                                  onTransposeDown: _transposeDown,
                                  onTransposeUp: _transposeUp,
                                  onCapoDown: _capoDown,
                                  onCapoUp: _capoUp,
                                  canonicalViewMode:
                                      _controller.state.canonicalViewMode,
                                  onCanonicalViewChanged: _setCanonicalView,
                                ),
                              ),
                            ],
                          ),
                        )
                      else ...[
                        _TabletTabBar(
                          selectedTab: _tabletTab,
                          onSelectedTab: _setTabletTab,
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: switch (_tabletTab) {
                            _TabletTab.overview => _OverviewPanel(
                              key: const ValueKey('song-editor-overview-panel'),
                              projection: projection,
                            ),
                            _TabletTab.source => _CanonicalPanel(
                              projection: projection,
                              sourceController: _sourceController,
                              isEditable: true,
                              onSourceChanged: _setSource,
                              onTransposeDown: _transposeDown,
                              onTransposeUp: _transposeUp,
                              onCapoDown: _capoDown,
                              onCapoUp: _capoUp,
                              canonicalViewMode:
                                  SongEditorCanonicalViewMode.source,
                              onCanonicalViewChanged: _setCanonicalView,
                              showToggle: false,
                            ),
                            _TabletTab.preview => _CanonicalPanel(
                              projection: projection,
                              sourceController: _sourceController,
                              isEditable: true,
                              onSourceChanged: _setSource,
                              onTransposeDown: _transposeDown,
                              onTransposeUp: _transposeUp,
                              onCapoDown: _capoDown,
                              onCapoUp: _capoUp,
                              canonicalViewMode:
                                  SongEditorCanonicalViewMode.preview,
                              onCanonicalViewChanged: _setCanonicalView,
                              showToggle: false,
                            ),
                          },
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.songId,
    required this.onBack,
    required this.canCancel,
    required this.canSave,
    required this.onSave,
    required this.onCancel,
  });

  final String songId;
  final VoidCallback onBack;
  final bool canCancel;
  final bool canSave;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 840;
        final titleColumn = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: const ValueKey('song-editor-back-button'),
                  onPressed: onBack,
                  icon: const BackButtonIcon(),
                  tooltip: 'Back',
                ),
                const SizedBox(width: 8),
                Text(
                  'Edit song',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ],
            ),
          ],
        );

        final actions = Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          children: [
            FilledButton.tonal(
              onPressed: canCancel ? onCancel : null,
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: canSave ? onSave : null,
              child: const Text('Save'),
            ),
          ],
        );

        if (isCompact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [titleColumn, const SizedBox(height: 12), actions],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: titleColumn),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [actions],
            ),
          ],
        );
      },
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.diagnosticCount});

  final int diagnosticCount;

  @override
  Widget build(BuildContext context) {
    if (diagnosticCount == 0) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Source parsed with $diagnosticCount recoverable warning(s).',
            ),
          ),
        ],
      ),
    );
  }
}

class _TabletTabBar extends StatelessWidget {
  const _TabletTabBar({required this.selectedTab, required this.onSelectedTab});

  final _TabletTab selectedTab;
  final ValueChanged<_TabletTab> onSelectedTab;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final entry in {
          _TabletTab.overview: 'Overview',
          _TabletTab.source: 'Source',
          _TabletTab.preview: 'Preview',
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

class _OverviewPanel extends StatelessWidget {
  const _OverviewPanel({super.key, required this.projection});

  final SongEditorProjection projection;

  @override
  Widget build(BuildContext context) {
    return _PanelShell(
      key: const ValueKey('song-editor-overview-shell'),
      title: 'Derived summary',
      expandChild: false,
      child: _SummaryList(projection: projection),
    );
  }
}

class _CanonicalPanel extends StatelessWidget {
  const _CanonicalPanel({
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

    return _PanelShell(
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
            ? _SourcePanel(
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
            : _PreviewPanel(
                key: const ValueKey('song-editor-preview-mode'),
                projection: projection,
              ),
      ),
    );
  }
}

class _SourcePanel extends StatelessWidget {
  const _SourcePanel({
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
              _Stepper(
                label: 'Transpose',
                value: projection.summaryTranspose,
                onDecrease: onTransposeDown,
                onIncrease: onTransposeUp,
                enabled: isEditable,
              ),
              _Stepper(
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

class _PreviewPanel extends StatelessWidget {
  const _PreviewPanel({super.key, required this.projection});

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

class _PanelShell extends StatelessWidget {
  const _PanelShell({
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
                if (trailing != null) trailing!,
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

class _SummaryList extends StatelessWidget {
  const _SummaryList({required this.projection});

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

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.onDecrease,
    required this.onIncrease,
    required this.enabled,
  });

  final String label;
  final String value;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        const SizedBox(width: 10),
        OutlinedButton(
          key: Key('${label.toLowerCase()}-decrease'),
          onPressed: enabled ? onDecrease : null,
          child: const Text('-'),
        ),
        const SizedBox(width: 8),
        Chip(label: Text(value)),
        const SizedBox(width: 8),
        OutlinedButton(
          key: Key('${label.toLowerCase()}-increase'),
          onPressed: enabled ? onIncrease : null,
          child: const Text('+'),
        ),
      ],
    );
  }
}
