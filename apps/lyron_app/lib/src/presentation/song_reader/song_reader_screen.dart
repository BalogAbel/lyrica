import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/song_library/catalog_connection_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_refresh_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_snapshot_state.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_types.dart';
import 'package:lyron_app/src/application/song_library/song_reader_result.dart';
import 'package:lyron_app/src/domain/planning/plan_detail.dart';
import 'package:lyron_app/src/domain/song/parse_diagnostic.dart';
import 'package:lyron_app/src/domain/song/song_access_denied_exception.dart';
import 'package:lyron_app/src/domain/song/song_not_found_exception.dart';
import 'package:lyron_app/src/presentation/planning/planning_routes.dart';
import 'package:lyron_app/src/presentation/song_reader/session_scoped_reader_context.dart';
import 'package:lyron_app/src/presentation/song_reader/session_scoped_reader_context_provider.dart';
import 'package:lyron_app/src/presentation/song_reader/session_scoped_reader_runtime_controller.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_controller.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_layout.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_compact_surface.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_expanded_surface.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_title_bar.dart';
import 'package:lyron_app/src/router/app_routes.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

class SongReaderScreen extends ConsumerStatefulWidget {
  const SongReaderScreen({
    super.key,
    required this.songId,
    this.planId,
    this.sessionId,
    this.sessionItemId,
    this.warmPlanDetail,
  });

  final String songId;
  final String? planId;
  final String? sessionId;
  final String? sessionItemId;
  final PlanDetail? warmPlanDetail;

  @override
  ConsumerState<SongReaderScreen> createState() => _SongReaderScreenState();
}

class _SongReaderScreenState extends ConsumerState<SongReaderScreen> {
  static const _contentWidth = 960.0;
  static const _expandedContentWidth = 1440.0;
  static const _expandedContextPanelWidth = 240.0;
  static const _expandedToolsPanelWidth = 320.0;
  static const _expandedPanelGap = 24.0;
  static const _contentPadding = EdgeInsets.all(24);
  static const _compactOverlayInactivity = Duration(seconds: 3);

  late final SongReaderController _controller = SongReaderController();
  Timer? _compactOverlayHideTimer;

  bool get _isScopedMode =>
      widget.planId != null &&
      widget.sessionId != null &&
      widget.sessionItemId != null;

  String get _sessionKey => '${widget.planId}:${widget.sessionId}';

  @override
  void initState() {
    super.initState();
    _syncScopedRuntimeState();
  }

  @override
  void didUpdateWidget(covariant SongReaderScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.songId != widget.songId ||
        oldWidget.planId != widget.planId ||
        oldWidget.sessionId != widget.sessionId) {
      _syncScopedRuntimeState();
    }
  }

  @override
  void dispose() {
    _compactOverlayHideTimer?.cancel();
    super.dispose();
  }

  void _updateState(void Function(SongReaderController controller) update) {
    setState(() {
      update(_controller);
    });
  }

  void _toggleViewMode() {
    if (_isScopedMode) {
      ref
          .read(sessionScopedReaderRuntimeControllerProvider(_sessionKey))
          .toggleViewMode();
      return;
    }

    _updateState((controller) => controller.toggleViewMode());
  }

  void _transposeDown() {
    if (_isScopedMode) {
      ref
          .read(sessionScopedReaderRuntimeControllerProvider(_sessionKey))
          .transposeDown();
      return;
    }

    _updateState((controller) => controller.transposeDown());
  }

  void _transposeUp() {
    if (_isScopedMode) {
      ref
          .read(sessionScopedReaderRuntimeControllerProvider(_sessionKey))
          .transposeUp();
      return;
    }

    _updateState((controller) => controller.transposeUp());
  }

  void _adjustSharedFontScale(double delta) {
    if (_isScopedMode) {
      final runtimeController = ref.read(
        sessionScopedReaderRuntimeControllerProvider(_sessionKey),
      );
      runtimeController.setSharedFontScale(
        runtimeController.state.readerState.sharedFontScale + delta,
      );
      return;
    }

    _updateState((controller) {
      controller.setSharedFontScale(controller.state.sharedFontScale + delta);
    });
  }

  void _toggleCompactControls() {
    if (_isScopedMode) {
      final runtimeController = ref.read(
        sessionScopedReaderRuntimeControllerProvider(_sessionKey),
      );
      runtimeController.toggleCompactControls();
      _handleCompactOverlayVisibilityChanged(
        runtimeController.state.readerState.areCompactControlsVisible,
      );
      return;
    }

    _updateState((controller) => controller.toggleCompactControls());
    _handleCompactOverlayVisibilityChanged(
      _controller.state.areCompactControlsVisible,
    );
  }

  void _toggleAutoFit() {
    if (_isScopedMode) {
      ref
          .read(sessionScopedReaderRuntimeControllerProvider(_sessionKey))
          .toggleAutoFit();
      return;
    }

    _updateState((controller) => controller.toggleAutoFit());
  }

  void _handleCompactOverlayVisibilityChanged(bool isVisible) {
    _compactOverlayHideTimer?.cancel();
    if (!isVisible) {
      return;
    }

    _compactOverlayHideTimer = Timer(_compactOverlayInactivity, () {
      if (!mounted) {
        return;
      }

      if (_isScopedMode) {
        final runtimeController = ref.read(
          sessionScopedReaderRuntimeControllerProvider(_sessionKey),
        );
        if (runtimeController.state.readerState.areCompactControlsVisible) {
          runtimeController.hideCompactControls();
        }
        return;
      }

      if (_controller.state.areCompactControlsVisible) {
        setState(() {
          _controller.hideCompactControls();
        });
      }
    });
  }

  void _handleBack(BuildContext context) {
    if (context.canPop()) {
      context.pop();
      return;
    }

    if (_isScopedMode) {
      final planSlug = widget.warmPlanDetail?.plan.slug ?? widget.planId!;
      context.replace(PlanningRoutes.planDetailLocation(planSlug));
      return;
    }

    context.replace(AppRoutes.home.path);
  }

  void _syncScopedRuntimeState() {
    if (!_isScopedMode) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      ref
          .read(sessionScopedReaderRuntimeControllerProvider(_sessionKey))
          .startSession(
            planId: widget.planId!,
            sessionId: widget.sessionId!,
            songId: widget.songId,
          );
    });
  }

  String _resolveCurrentTitle({
    required SessionScopedReaderContext? scopedContext,
    required SongReaderProjection projection,
  }) {
    final scopedTitle = scopedContext?.selectedItem.title.trim() ?? '';
    if (scopedTitle.isNotEmpty) {
      return scopedTitle;
    }
    return projection.title;
  }

  String? _resolveNeighborTitle(String? title) {
    final trimmed = title?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  Future<void> _editSong(BuildContext context, SongReaderResult result) async {
    final activeContext = ref.read(activeCatalogContextProvider);
    if (activeContext == null) {
      return;
    }
    final currentSource = await ref
        .read(songLibraryServiceProvider)
        .getSongSource(context: activeContext, songId: widget.songId);
    if (!context.mounted) {
      return;
    }

    final draft = await showDialog<(String, String)>(
      context: context,
      builder: (context) => _SongEditDialog(
        initialTitle: result.song.title,
        initialSource: currentSource.source,
      ),
    );

    if (draft == null) {
      return;
    }

    try {
      await ref
          .read(songLibraryServiceProvider)
          .updateSong(
            context: activeContext,
            songId: widget.songId,
            title: draft.$1,
            chordproSource: draft.$2,
          );
      ref.invalidate(songMutationEntriesProvider);
      ref.invalidate(songLibraryListProvider);
      ref.invalidate(songLibraryReaderProvider(widget.songId));
    } on SongConflictResolutionRequiredException {
      if (!context.mounted) {
        return;
      }
      await _showConflictResolutionRequiredDialog(context);
    }
  }

  Future<void> _deleteSong(BuildContext context) async {
    final activeContext = ref.read(activeCatalogContextProvider);
    if (activeContext == null) {
      return;
    }

    try {
      await ref
          .read(songLibraryServiceProvider)
          .deleteSong(context: activeContext, songId: widget.songId);
      ref.invalidate(songMutationEntriesProvider);
      ref.invalidate(songLibraryListProvider);
      if (context.mounted) {
        _handleBack(context);
      }
    } on SongDeleteBlockedException {
      if (!context.mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          content: const Text(AppStrings.songDeleteBlockedMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(AppStrings.songCancelAction),
            ),
          ],
        ),
      );
    } on SongConflictResolutionRequiredException {
      if (!context.mounted) {
        return;
      }
      await _showConflictResolutionRequiredDialog(context);
    }
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

  @override
  Widget build(BuildContext context) {
    final readerAsync = ref.watch(songLibraryReaderProvider(widget.songId));
    final catalogState = ref.watch(catalogSnapshotStateProvider);
    final isResolvingCatalogContext =
        catalogState.context == null &&
        catalogState.refreshStatus == CatalogRefreshStatus.refreshing;
    final scopedContextAsync = _isScopedMode
        ? ref.watch(
            sessionScopedReaderContextProvider(
              SessionScopedReaderContextRequest(
                planId: widget.planId!,
                planSlug: widget.warmPlanDetail?.plan.slug ?? widget.planId!,
                sessionId: widget.sessionId!,
                sessionSlug: _sessionSlugFor(
                  widget.warmPlanDetail,
                  widget.sessionId!,
                ),
                sessionItemId: widget.sessionItemId!,
                songId: widget.songId,
                warmPlanDetail: widget.warmPlanDetail,
              ),
            ),
          )
        : null;
    final scopedRuntimeController = _isScopedMode
        ? ref.watch(sessionScopedReaderRuntimeControllerProvider(_sessionKey))
        : null;
    final readerState = _isScopedMode
        ? scopedRuntimeController!.state.readerState
        : _controller.state;

    if (_isScopedMode && scopedContextAsync != null) {
      final scopedValue = scopedContextAsync.valueOrNull;
      if (scopedValue is SessionScopedReaderContextFailureResult) {
        return Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            leading: IconButton(
              tooltip: AppStrings.songReaderBackAction,
              onPressed: () => _handleBack(context),
              icon: const BackButtonIcon(),
            ),
            title: const Text('Song reader'),
          ),
          body: SafeArea(
            child: Center(
              child: Text(
                AppStrings.scopedReaderContextUnavailableMessage,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
      }
    }

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: AppStrings.songReaderBackAction,
          onPressed: () => _handleBack(context),
          icon: const BackButtonIcon(),
        ),
        title: const Text('Song reader'),
      ),
      body: PopScope<void>(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) {
            return;
          }

          _handleBack(context);
        },
        child: SafeArea(
          child: isResolvingCatalogContext
              ? const Center(child: Text(AppStrings.songReaderLoadingMessage))
              : readerAsync.when(
                  loading: () => const Center(
                    child: Text(AppStrings.songReaderLoadingMessage),
                  ),
                  error: (error, stackTrace) {
                    if (_isScopedMode) {
                      return const Center(
                        child: Text(
                          AppStrings.scopedReaderContextUnavailableMessage,
                          textAlign: TextAlign.center,
                        ),
                      );
                    }

                    if (error is SongAccessDeniedException) {
                      return const Center(
                        child: Text(AppStrings.songReaderAccessDeniedMessage),
                      );
                    }

                    if (error is SongNotFoundException) {
                      return const Center(
                        child: Text(AppStrings.songReaderUnavailableMessage),
                      );
                    }

                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            AppStrings.songReaderLoadFailureMessage,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: () {
                              ref.invalidate(
                                songLibraryReaderProvider(widget.songId),
                              );
                            },
                            child: const Text(AppStrings.retryAction),
                          ),
                        ],
                      ),
                    );
                  },
                  data: (SongReaderResult result) {
                    final projection = SongReaderProjection(
                      song: result.song,
                      state: readerState,
                    );
                    final recoverableWarningCount = result.song.diagnostics
                        .where(
                          (diagnostic) =>
                              diagnostic.severity ==
                              ParseDiagnosticSeverity.warning,
                        )
                        .length;

                    final resolvedScopedContext =
                        scopedContextAsync?.valueOrNull
                            is ResolvedSessionScopedReaderContextResult
                        ? (scopedContextAsync!.valueOrNull
                                  as ResolvedSessionScopedReaderContextResult)
                              .context
                        : null;
                    final currentTitle = _resolveCurrentTitle(
                      scopedContext: resolvedScopedContext,
                      projection: projection,
                    );
                    final previousTitle = _resolveNeighborTitle(
                      resolvedScopedContext?.previousItem?.title,
                    );
                    final nextTitle = _resolveNeighborTitle(
                      resolvedScopedContext?.nextItem?.title,
                    );

                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final layout = resolveSongReaderLayout(
                          viewportWidth: constraints.maxWidth,
                          sharedFontScale: projection.sharedFontScale,
                          isAutoFitEnabled: readerState.isAutoFitEnabled,
                        );

                        final readerSurface =
                            layout.shell == SongReaderShell.expanded
                            ? SongReaderExpandedSurface(
                                projection: projection,
                                previousTitle: previousTitle,
                                nextTitle: nextTitle,
                                hasRecoverableWarnings:
                                    result.hasRecoverableWarnings,
                                warningCount: recoverableWarningCount,
                                contentColumnCount: layout.contentColumnCount,
                                onToggleViewMode: _toggleViewMode,
                                onTransposeDown: _transposeDown,
                                onTransposeUp: _transposeUp,
                                onDecreaseFontScale: () =>
                                    _adjustSharedFontScale(-0.1),
                                onIncreaseFontScale: () =>
                                    _adjustSharedFontScale(0.1),
                              )
                            : SongReaderCompactSurface(
                                projection: projection,
                                areControlsVisible:
                                    readerState.areCompactControlsVisible,
                                currentTitle: currentTitle,
                                previousTitle: previousTitle,
                                nextTitle: nextTitle,
                                onSurfaceTap: _toggleCompactControls,
                                onSurfaceDoubleTap: _toggleAutoFit,
                                hasRecoverableWarnings:
                                    result.hasRecoverableWarnings,
                                warningCount: recoverableWarningCount,
                                contentColumnCount: layout.contentColumnCount,
                                onToggleViewMode: _toggleViewMode,
                                onTransposeDown: _transposeDown,
                                onTransposeUp: _transposeUp,
                                onDecreaseFontScale: () =>
                                    _adjustSharedFontScale(-0.1),
                                onIncreaseFontScale: () =>
                                    _adjustSharedFontScale(0.1),
                              );

                        return Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: layout.shell == SongReaderShell.expanded
                                  ? _expandedContentWidth
                                  : _contentWidth,
                            ),
                            child: Padding(
                              padding: _contentPadding,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _CatalogStatusSurface(state: catalogState),
                                  if (_hasVisibleStatus(catalogState))
                                    const SizedBox(height: 24),
                                  Row(
                                    children: [
                                      FilledButton.tonal(
                                        onPressed: () =>
                                            _editSong(context, result),
                                        child: const Text(
                                          AppStrings.songEditAction,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      FilledButton.tonal(
                                        onPressed: () => _deleteSong(context),
                                        child: const Text(
                                          AppStrings.songDeleteAction,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 24),
                                  if (_isScopedMode)
                                    _ScopedNavigationSurface(
                                      scopedContextAsync: scopedContextAsync!,
                                      currentWarmPlanDetail:
                                          widget.warmPlanDetail,
                                    ),
                                  if (_isScopedMode) const SizedBox(height: 24),
                                  Padding(
                                    padding:
                                        layout.shell == SongReaderShell.expanded
                                        ? const EdgeInsets.symmetric(
                                            horizontal:
                                                _expandedPanelGap +
                                                _expandedContextPanelWidth,
                                          ).copyWith(
                                            right:
                                                _expandedPanelGap +
                                                _expandedToolsPanelWidth,
                                          )
                                        : EdgeInsets.zero,
                                    child: SongReaderTitleBar(
                                      title: currentTitle,
                                      subtitle: projection.subtitle,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Expanded(child: readerSurface),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class _SongEditDialog extends StatefulWidget {
  const _SongEditDialog({
    required this.initialTitle,
    required this.initialSource,
  });

  final String initialTitle;
  final String initialSource;

  @override
  State<_SongEditDialog> createState() => _SongEditDialogState();
}

class _SongEditDialogState extends State<_SongEditDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _sourceController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
    _sourceController = TextEditingController(text: widget.initialSource);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _sourceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(AppStrings.songEditAction),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: AppStrings.songTitleLabel,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _sourceController,
              minLines: 4,
              maxLines: null,
              decoration: const InputDecoration(
                labelText: AppStrings.songSourceLabel,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(AppStrings.songCancelAction),
        ),
        FilledButton(
          onPressed: () => Navigator.of(
            context,
          ).pop((_titleController.text.trim(), _sourceController.text)),
          child: const Text(AppStrings.songSaveAction),
        ),
      ],
    );
  }
}

class _ScopedNavigationSurface extends StatelessWidget {
  const _ScopedNavigationSurface({
    required this.scopedContextAsync,
    required this.currentWarmPlanDetail,
  });

  final AsyncValue<SessionScopedReaderContextResult> scopedContextAsync;
  final PlanDetail? currentWarmPlanDetail;

  @override
  Widget build(BuildContext context) {
    return scopedContextAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (error, stackTrace) => const SizedBox.shrink(),
      data: (result) {
        if (result is! ResolvedSessionScopedReaderContextResult) {
          return const SizedBox.shrink();
        }

        final scopedContext = result.context;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            OutlinedButton(
              onPressed: scopedContext.previousItem == null
                  ? null
                  : () {
                      context.replace(
                        PlanningRoutes.planSessionSongReaderLocation(
                          planSlug: scopedContext.planSlug,
                          sessionSlug: scopedContext.sessionSlug,
                          songSlug: scopedContext.previousItem!.songSlug,
                        ),
                        extra: currentWarmPlanDetail,
                      );
                    },
              child: const Text(AppStrings.scopedReaderPreviousAction),
            ),
            OutlinedButton(
              onPressed: scopedContext.nextItem == null
                  ? null
                  : () {
                      context.replace(
                        PlanningRoutes.planSessionSongReaderLocation(
                          planSlug: scopedContext.planSlug,
                          sessionSlug: scopedContext.sessionSlug,
                          songSlug: scopedContext.nextItem!.songSlug,
                        ),
                        extra: currentWarmPlanDetail,
                      );
                    },
              child: const Text(AppStrings.scopedReaderNextAction),
            ),
          ],
        );
      },
    );
  }
}

String _sessionSlugFor(PlanDetail? planDetail, String sessionId) {
  final session = planDetail?.sessions
      .where((candidate) => candidate.id == sessionId)
      .firstOrNull;
  return session?.slug ?? sessionId;
}

bool _hasVisibleStatus(CatalogSnapshotState state) {
  return state.connectionStatus == CatalogConnectionStatus.online ||
      state.connectionStatus == CatalogConnectionStatus.offlineCached ||
      state.refreshStatus == CatalogRefreshStatus.refreshing ||
      (state.refreshStatus == CatalogRefreshStatus.failed &&
          state.hasCachedCatalog);
}

class _CatalogStatusSurface extends StatelessWidget {
  const _CatalogStatusSurface({required this.state});

  final CatalogSnapshotState state;

  @override
  Widget build(BuildContext context) {
    final messages = <String>[
      if (state.connectionStatus == CatalogConnectionStatus.online)
        AppStrings.songCatalogOnlineStatus,
      if (state.connectionStatus == CatalogConnectionStatus.offlineCached)
        AppStrings.songCatalogOfflineStatus,
      if (state.refreshStatus == CatalogRefreshStatus.refreshing)
        AppStrings.songCatalogRefreshingStatus,
      if (state.refreshStatus == CatalogRefreshStatus.failed &&
          state.hasCachedCatalog)
        AppStrings.songCatalogRefreshFailedStatus,
    ];

    if (messages.isEmpty) {
      return const SizedBox.shrink();
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: messages
              .map((message) => Text(message))
              .toList(growable: false),
        ),
      ),
    );
  }
}
