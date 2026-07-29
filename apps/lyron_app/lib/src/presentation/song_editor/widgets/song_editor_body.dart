import 'package:flutter/material.dart';
import 'package:lyron_app/src/presentation/song_editor/song_editor_projection.dart';
import 'package:lyron_app/src/presentation/song_editor/song_editor_state.dart';
import 'package:lyron_app/src/presentation/song_editor/widgets/song_editor_panels.dart';
import 'package:lyron_app/src/presentation/song_editor/widgets/song_editor_tab_bar.dart';
import 'package:lyron_app/src/presentation/song_editor/widgets/song_editor_top_bar.dart';

/// Wide-vs-tablet layout for the song editor: the top bar, status banner,
/// and the overview/canonical/preview panel composition. Sits below the
/// capability gate in `SongEditorScreen` and holds no state of its own —
/// every value and callback is threaded in from the screen.
class SongEditorBody extends StatelessWidget {
  const SongEditorBody({
    super.key,
    required this.title,
    required this.isDirty,
    required this.organizationId,
    required this.projection,
    required this.sourceController,
    required this.canonicalViewMode,
    required this.selectedTab,
    required this.onPopInvokedWithResult,
    required this.onBack,
    required this.onSave,
    required this.onCancel,
    required this.onSourceChanged,
    required this.onTransposeDown,
    required this.onTransposeUp,
    required this.onCapoDown,
    required this.onCapoUp,
    required this.onCanonicalViewChanged,
    required this.onSelectedTab,
  });

  static const _wideBreakpoint = 980.0;
  static const _contentMaxWidth = 1200.0;

  final String title;
  final bool isDirty;
  final String? organizationId;
  final SongEditorProjection projection;
  final TextEditingController sourceController;
  final SongEditorCanonicalViewMode canonicalViewMode;
  final SongEditorTab selectedTab;
  final PopInvokedWithResultCallback<void> onPopInvokedWithResult;
  final VoidCallback onBack;
  final VoidCallback onSave;
  final VoidCallback onCancel;
  final ValueChanged<String> onSourceChanged;
  final VoidCallback onTransposeDown;
  final VoidCallback onTransposeUp;
  final VoidCallback onCapoDown;
  final VoidCallback onCapoUp;
  final ValueChanged<SongEditorCanonicalViewMode> onCanonicalViewChanged;
  final ValueChanged<SongEditorTab> onSelectedTab;

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: !isDirty,
      onPopInvokedWithResult: onPopInvokedWithResult,
      child: Scaffold(
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
                        SongEditorTopBar(
                          title: title,
                          onBack: onBack,
                          canCancel: true,
                          canSave: isDirty,
                          onSave: onSave,
                          onCancel: onCancel,
                          organizationId: organizationId,
                        ),
                        const SizedBox(height: 16),
                        SongEditorStatusBanner(
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
                                  child: SongEditorOverviewPanel(
                                    projection: projection,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  flex: 2,
                                  child: SongEditorCanonicalPanel(
                                    projection: projection,
                                    sourceController: sourceController,
                                    isEditable: true,
                                    onSourceChanged: onSourceChanged,
                                    onTransposeDown: onTransposeDown,
                                    onTransposeUp: onTransposeUp,
                                    onCapoDown: onCapoDown,
                                    onCapoUp: onCapoUp,
                                    canonicalViewMode: canonicalViewMode,
                                    onCanonicalViewChanged:
                                        onCanonicalViewChanged,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else ...[
                          SongEditorTabBar(
                            selectedTab: selectedTab,
                            onSelectedTab: onSelectedTab,
                          ),
                          const SizedBox(height: 16),
                          Expanded(
                            child: switch (selectedTab) {
                              SongEditorTab.overview => SongEditorOverviewPanel(
                                key: const ValueKey(
                                  'song-editor-overview-panel',
                                ),
                                projection: projection,
                              ),
                              SongEditorTab.source => SongEditorCanonicalPanel(
                                projection: projection,
                                sourceController: sourceController,
                                isEditable: true,
                                onSourceChanged: onSourceChanged,
                                onTransposeDown: onTransposeDown,
                                onTransposeUp: onTransposeUp,
                                onCapoDown: onCapoDown,
                                onCapoUp: onCapoUp,
                                canonicalViewMode:
                                    SongEditorCanonicalViewMode.source,
                                onCanonicalViewChanged: onCanonicalViewChanged,
                                showToggle: false,
                              ),
                              SongEditorTab.preview => SongEditorCanonicalPanel(
                                projection: projection,
                                sourceController: sourceController,
                                isEditable: true,
                                onSourceChanged: onSourceChanged,
                                onTransposeDown: onTransposeDown,
                                onTransposeUp: onTransposeUp,
                                onCapoDown: onCapoDown,
                                onCapoUp: onCapoUp,
                                canonicalViewMode:
                                    SongEditorCanonicalViewMode.preview,
                                onCanonicalViewChanged: onCanonicalViewChanged,
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
      ),
    );
  }
}
