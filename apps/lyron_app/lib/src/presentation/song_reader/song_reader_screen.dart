import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lyron_app/src/application/providers.dart';
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
import 'package:lyron_app/src/router/app_routes.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

enum _SongReaderOverflowAction { edit, delete }

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
      _bumpCompactOverlayInactivityIfVisible();
      return;
    }

    _updateState((controller) => controller.toggleViewMode());
    _bumpCompactOverlayInactivityIfVisible();
  }

  void _transposeDown() {
    if (_isScopedMode) {
      ref
          .read(sessionScopedReaderRuntimeControllerProvider(_sessionKey))
          .transposeDown();
      _bumpCompactOverlayInactivityIfVisible();
      return;
    }

    _updateState((controller) => controller.transposeDown());
    _bumpCompactOverlayInactivityIfVisible();
  }

  void _transposeUp() {
    if (_isScopedMode) {
      ref
          .read(sessionScopedReaderRuntimeControllerProvider(_sessionKey))
          .transposeUp();
      _bumpCompactOverlayInactivityIfVisible();
      return;
    }

    _updateState((controller) => controller.transposeUp());
    _bumpCompactOverlayInactivityIfVisible();
  }

  void _adjustSharedFontScale(double delta) {
    if (_isScopedMode) {
      final runtimeController = ref.read(
        sessionScopedReaderRuntimeControllerProvider(_sessionKey),
      );
      runtimeController.setSharedFontScale(
        runtimeController.state.readerState.sharedFontScale + delta,
      );
      _bumpCompactOverlayInactivityIfVisible();
      return;
    }

    _updateState((controller) {
      controller.setSharedFontScale(controller.state.sharedFontScale + delta);
    });
    _bumpCompactOverlayInactivityIfVisible();
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
      _bumpCompactOverlayInactivityIfVisible();
      return;
    }

    _updateState((controller) => controller.toggleAutoFit());
    _bumpCompactOverlayInactivityIfVisible();
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

  void _bumpCompactOverlayInactivityIfVisible() {
    final isVisible = _isScopedMode
        ? ref
              .read(sessionScopedReaderRuntimeControllerProvider(_sessionKey))
              .state
              .readerState
              .areCompactControlsVisible
        : _controller.state.areCompactControlsVisible;
    if (!isVisible) {
      return;
    }
    _handleCompactOverlayVisibilityChanged(true);
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

  void _navigateToScopedSong(
    BuildContext context, {
    required SessionScopedReaderContext scopedContext,
    required String songSlug,
  }) {
    context.replace(
      PlanningRoutes.planSessionSongReaderLocation(
        planSlug: scopedContext.planSlug,
        sessionSlug: scopedContext.sessionSlug,
        songSlug: songSlug,
      ),
      extra: widget.warmPlanDetail,
    );
  }

  VoidCallback? _buildScopedNeighborNavigationTap(
    BuildContext context, {
    required SessionScopedReaderContext? scopedContext,
    required SessionScopedReaderNeighbor? neighbor,
  }) {
    if (scopedContext == null || neighbor == null) {
      return null;
    }

    return () => _navigateToScopedSong(
      context,
      scopedContext: scopedContext,
      songSlug: neighbor.songSlug,
    );
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

  String _resolvePreservedScopedTitle(
    SessionScopedReaderContext? scopedContext,
  ) {
    final scopedTitle = scopedContext?.selectedItem.title.trim() ?? '';
    if (scopedTitle.isNotEmpty) {
      return scopedTitle;
    }
    final warmPlanDetail = widget.warmPlanDetail;
    final sessionItemId = widget.sessionItemId;
    if (warmPlanDetail != null && sessionItemId != null) {
      for (final session in warmPlanDetail.sessions) {
        for (final item in session.items) {
          if (item.id == sessionItemId && item.song.id == widget.songId) {
            final preservedTitle = item.song.title.trim();
            if (preservedTitle.isNotEmpty) {
              return preservedTitle;
            }
          }
        }
      }
    }
    return AppStrings.songReaderTitle;
  }

  Widget _buildScopedDeletedTombstone({
    required SessionScopedReaderContext? scopedContext,
    required SongMutationRecord? mutationRecord,
  }) {
    final message =
        mutationRecord?.isRemoteDeletedConflict == true &&
            mutationRecord?.effectiveSyncStatus == SongSyncStatus.pendingUpdate
        ? AppStrings.songReaderDeletedConflictMessage
        : AppStrings.songReaderDeletedMessage;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _resolvePreservedScopedTitle(scopedContext),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              AppStrings.songReaderDeletedTitle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  bool _canShowScopedDeletedTombstone({
    required CatalogSnapshotState catalogState,
    required SongMutationRecord? mutationRecord,
  }) {
    return mutationRecord?.isRemoteDeletedConflict == true ||
        catalogState.context != null;
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
    final mutationRecordAsync = _isScopedMode
        ? ref.watch(songMutationRecordByIdProvider(widget.songId))
        : null;
    final readerResult = readerAsync.valueOrNull;
    final scopedContextResult = scopedContextAsync?.valueOrNull;
    final resolvedScopedContext =
        scopedContextResult is ResolvedSessionScopedReaderContextResult
        ? scopedContextResult.context
        : null;
    final mutationRecord = mutationRecordAsync?.valueOrNull;
    final projection = readerResult == null
        ? null
        : SongReaderProjection(song: readerResult.song, state: readerState);
    final currentTitle = projection == null
        ? _resolvePreservedScopedTitle(resolvedScopedContext)
        : _resolveCurrentTitle(
            scopedContext: resolvedScopedContext,
            projection: projection,
          );

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
            title: const Text(AppStrings.songReaderTitle),
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
        title: Text(currentTitle),
        actions: [
          if (readerResult != null)
            PopupMenuButton<_SongReaderOverflowAction>(
              icon: const Icon(Icons.more_horiz),
              onSelected: (action) {
                switch (action) {
                  case _SongReaderOverflowAction.edit:
                    unawaited(_editSong(context, readerResult));
                  case _SongReaderOverflowAction.delete:
                    unawaited(_deleteSong(context));
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: _SongReaderOverflowAction.edit,
                  child: Text(AppStrings.songEditAction),
                ),
                PopupMenuItem(
                  value: _SongReaderOverflowAction.delete,
                  child: Text(AppStrings.songDeleteAction),
                ),
              ],
            ),
        ],
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
                      if (error is SongNotFoundException) {
                        if (_canShowScopedDeletedTombstone(
                          catalogState: catalogState,
                          mutationRecord: mutationRecord,
                        )) {
                          return _buildScopedDeletedTombstone(
                            scopedContext: resolvedScopedContext,
                            mutationRecord: mutationRecord,
                          );
                        }
                      }
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
                    final showExpandedContextPanel =
                        resolvedScopedContext != null;

                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final layout = resolveSongReaderLayout(
                          viewportWidth: constraints.maxWidth,
                          sharedFontScale: projection.sharedFontScale,
                          isAutoFitEnabled: readerState.isAutoFitEnabled,
                        );
                        final showCompactBottomContextBar =
                            resolvedScopedContext != null;

                        final readerSurface =
                            layout.shell == SongReaderShell.expanded
                            ? SongReaderExpandedSurface(
                                projection: projection,
                                showContextPanel: showExpandedContextPanel,
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
                                onPreviousTap:
                                    _buildScopedNeighborNavigationTap(
                                      context,
                                      scopedContext: resolvedScopedContext,
                                      neighbor:
                                          resolvedScopedContext?.previousItem,
                                    ),
                                onNextTap: _buildScopedNeighborNavigationTap(
                                  context,
                                  scopedContext: resolvedScopedContext,
                                  neighbor: resolvedScopedContext?.nextItem,
                                ),
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
                                showBottomContextBar:
                                    showCompactBottomContextBar,
                                onToggleViewMode: _toggleViewMode,
                                onTransposeDown: _transposeDown,
                                onTransposeUp: _transposeUp,
                                onDecreaseFontScale: () =>
                                    _adjustSharedFontScale(-0.1),
                                onIncreaseFontScale: () =>
                                    _adjustSharedFontScale(0.1),
                                onPreviousTap:
                                    _buildScopedNeighborNavigationTap(
                                      context,
                                      scopedContext: resolvedScopedContext,
                                      neighbor:
                                          resolvedScopedContext?.previousItem,
                                    ),
                                onNextTap: _buildScopedNeighborNavigationTap(
                                  context,
                                  scopedContext: resolvedScopedContext,
                                  neighbor: resolvedScopedContext?.nextItem,
                                ),
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
                                children: [Expanded(child: readerSurface)],
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

String _sessionSlugFor(PlanDetail? planDetail, String sessionId) {
  final session = planDetail?.sessions
      .where((candidate) => candidate.id == sessionId)
      .firstOrNull;
  return session?.slug ?? sessionId;
}
