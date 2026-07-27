import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/song_library/catalog_refresh_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_snapshot_state.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_types.dart';
import 'package:lyron_app/src/application/song_library/song_reader_result.dart';
import 'package:lyron_app/src/domain/core/capability.dart';
import 'package:lyron_app/src/domain/planning/plan_detail.dart';
import 'package:lyron_app/src/domain/song/parse_diagnostic.dart';
import 'package:lyron_app/src/domain/song/song_access_denied_exception.dart';
import 'package:lyron_app/src/domain/song/song_not_found_exception.dart';
import 'package:lyron_app/src/presentation/planning/planning_routes.dart';
import 'package:lyron_app/src/presentation/song_reader/session_scoped_reader_context.dart';
import 'package:lyron_app/src/presentation/song_reader/session_scoped_reader_context_provider.dart';
import 'package:lyron_app/src/presentation/song_reader/session_scoped_reader_runtime_controller.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_controller.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_immersive_mode.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_layout.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_preferences_store.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_song_actions.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_zoom_persistence.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_app_bar.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_compact_surface.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_expanded_surface.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_overflow_menu.dart';
import 'package:lyron_app/src/router/app_routes.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

/// Overridable provider that resolves the current user's ID.
///
/// Defaults to reading from [supabaseClientProvider] so production behaviour is
/// unchanged. Tests override this with a [Provider.value] to avoid initialising
/// a real [SupabaseClient].
final readerUserIdProvider = Provider<String?>((ref) {
  try {
    return ref.watch(supabaseClientProvider).auth.currentUser?.id;
  } catch (_) {
    return null;
  }
});

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
  static const _contentPadding = EdgeInsets.all(24);

  late final SongReaderController _controller = SongReaderController();
  final _immersiveMode = SongReaderImmersiveMode();
  final _zoomPersistence = SongReaderZoomPersistence();

  // Rebuilt on every access (it is a cheap, stateless const-constructed value
  // holder) so it always reflects the current widget.songId — this state can
  // be reused across scoped song-to-song navigation, where widget.songId
  // changes without a new State being created (see didUpdateWidget).
  SongReaderSongActions get _songActions =>
      SongReaderSongActions(songId: widget.songId);

  bool get _isScopedMode =>
      widget.planId != null &&
      widget.sessionId != null &&
      widget.sessionItemId != null;

  String get _sessionKey => '${widget.planId}:${widget.sessionId}';

  @override
  void initState() {
    super.initState();
    _syncScopedRuntimeState();
    _seedZoomFromStorage();
    // A sibling reader's `dispose` (scoped song-to-song navigation via
    // `context.replace`) resets the global system UI to edgeToEdge. Re-apply
    // immersive mode here so a freshly opened reader honors the persisted
    // control visibility instead of dropping out of immersive silently.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncImmersiveToControls();
    });
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
    _zoomPersistence.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  /// Reads the stored zoom for this user+song once on open and applies it via
  /// the same path as [_setSharedFontScale]. The one-shot guard lives in
  /// [_zoomPersistence]; this method keeps the `mounted` checks, since those
  /// belong to the screen's lifecycle, not to the persistence class.
  void _seedZoomFromStorage() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }

      // Resolve userId inside the callback so tests can override the provider
      // and the read does not crash during Supabase-less test environments.
      final zoom = await _zoomPersistence.seedFromStorage(
        userId: ref.read(readerUserIdProvider),
        songId: widget.songId,
        resolveStore: () => ref.read(songReaderPreferencesStoreProvider.future),
      );
      if (!mounted || zoom == null) {
        return;
      }
      _setSharedFontScale(zoom);
    });
  }

  /// Debounced persist: (re)starts a 400 ms timer that writes the current
  /// sharedFontScale for this user+song. Called on pinch-end and double-tap fit.
  void _persistFontScale() {
    _zoomPersistence.schedulePersist(
      userId: ref.read(readerUserIdProvider),
      songId: widget.songId,
      isMounted: () => mounted,
      readScale: () => _isScopedMode
          ? ref
                .read(sessionScopedReaderRuntimeControllerProvider(_sessionKey))
                .state
                .readerState
                .sharedFontScale
          : _controller.state.sharedFontScale,
      resolveStore: () => ref.read(songReaderPreferencesStoreProvider.future),
    );
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

  void _capoDown() {
    if (_isScopedMode) {
      ref
          .read(sessionScopedReaderRuntimeControllerProvider(_sessionKey))
          .capoDown();
      return;
    }

    _updateState((controller) => controller.capoDown());
  }

  void _capoUp() {
    if (_isScopedMode) {
      ref
          .read(sessionScopedReaderRuntimeControllerProvider(_sessionKey))
          .capoUp();
      return;
    }

    _updateState((controller) => controller.capoUp());
  }

  void _setInstrumentDisplayMode(SongReaderInstrumentDisplayMode mode) {
    if (_isScopedMode) {
      ref
          .read(sessionScopedReaderRuntimeControllerProvider(_sessionKey))
          .setInstrumentDisplayMode(mode);
      return;
    }

    _updateState((controller) => controller.setInstrumentDisplayMode(mode));
  }

  void _adjustSharedFontScale(double delta) {
    if (_isScopedMode) {
      final runtimeController = ref.read(
        sessionScopedReaderRuntimeControllerProvider(_sessionKey),
      );
      runtimeController.setSharedFontScale(
        runtimeController.state.readerState.sharedFontScale + delta,
      );
      _persistFontScale();
      return;
    }

    _updateState((controller) {
      controller.setSharedFontScale(controller.state.sharedFontScale + delta);
    });
    _persistFontScale();
  }

  void _setSharedFontScale(double scale) {
    if (_isScopedMode) {
      final runtimeController = ref.read(
        sessionScopedReaderRuntimeControllerProvider(_sessionKey),
      );
      runtimeController.setSharedFontScale(scale);
      return;
    }

    _updateState((controller) {
      controller.setSharedFontScale(scale);
    });
  }

  /// Reads whether the compact controls are currently visible from the active
  /// state source (scoped runtime controller or local controller).
  bool get _areControlsVisible {
    if (_isScopedMode) {
      return ref
          .read(sessionScopedReaderRuntimeControllerProvider(_sessionKey))
          .state
          .readerState
          .areCompactControlsVisible;
    }
    return _controller.state.areCompactControlsVisible;
  }

  /// Re-applies immersive mode to match the current control visibility. Used on
  /// open and when this screen regains focus after a sibling screen's `dispose`
  /// or a pushed route's pop reset the global system UI state.
  void _syncImmersiveToControls() {
    if (!mounted) {
      return;
    }
    _immersiveMode.apply(_areControlsVisible);
  }

  void _toggleCompactControls() {
    if (_isScopedMode) {
      final runtimeController = ref.read(
        sessionScopedReaderRuntimeControllerProvider(_sessionKey),
      );
      runtimeController.toggleCompactControls();
      _immersiveMode.apply(
        runtimeController.state.readerState.areCompactControlsVisible,
      );
      return;
    }

    _updateState((controller) => controller.toggleCompactControls());
    _immersiveMode.apply(_controller.state.areCompactControlsVisible);
  }

  void _handleBack(BuildContext context) {
    _immersiveMode.apply(false);
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

  Future<void> _showWarningsDialog(BuildContext context, int count) {
    final message = count == 1
        ? AppStrings.songReaderWarningSingular
        : AppStrings.songReaderWarningPlural(count);
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AppStrings.songReaderWarningDialogTitle),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(AppStrings.songReaderCloseAction),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final readerAsync = ref.watch(songLibraryReaderProvider(widget.songId));
    final catalogState = ref.watch(catalogSnapshotStateProvider);

    // Resolve edit capability synchronously (cache hit) for the overflow menu.
    // Fail-open when org context or resolver are unavailable.
    final orgId = catalogState.context?.organizationId;
    bool canEditSongs = true;
    if (orgId != null) {
      try {
        final resolver = ref.watch(capabilityResolverProvider);
        canEditSongs =
            resolver.hasCapabilitySync(orgId, Capability.editSongs) ?? true;
      } catch (_) {}
    }

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
    final hasRecoverableWarnings =
        readerResult?.hasRecoverableWarnings ?? false;
    final recoverableWarningCount = readerResult == null
        ? 0
        : readerResult.song.diagnostics
              .where((d) => d.severity == ParseDiagnosticSeverity.warning)
              .length;

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
      appBar: SongReaderAppBar(
        title: currentTitle,
        effectiveKey: projection?.effectiveKey,
        onBack: () => _handleBack(context),
        hasRecoverableWarnings: hasRecoverableWarnings,
        onShowWarnings: () =>
            _showWarningsDialog(context, recoverableWarningCount),
        overflowMenu: readerResult == null
            ? null
            : SongReaderOverflowMenu(
                viewMode: readerState.viewMode,
                canEditSongs: canEditSongs,
                onSelected: (action) {
                  switch (action) {
                    case SongReaderOverflowAction.toggleViewMode:
                      _toggleViewMode();
                      break;
                    case SongReaderOverflowAction.guitarView:
                      _setInstrumentDisplayMode(
                        SongReaderInstrumentDisplayMode.guitar,
                      );
                      break;
                    case SongReaderOverflowAction.pianoView:
                      _setInstrumentDisplayMode(
                        SongReaderInstrumentDisplayMode.piano,
                      );
                      break;
                    case SongReaderOverflowAction.edit:
                      unawaited(
                        _songActions.edit(
                          context,
                          ref,
                          immersiveMode: _immersiveMode,
                          wasImmersive: _areControlsVisible,
                        ),
                      );
                      break;
                    case SongReaderOverflowAction.delete:
                      unawaited(
                        _songActions.delete(
                          context,
                          ref,
                          onDeleted: _handleBack,
                        ),
                      );
                      break;
                  }
                },
              ),
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
                                contentColumnCount: layout.contentColumnCount,
                                onTransposeDown: _transposeDown,
                                onTransposeUp: _transposeUp,
                                onCapoDown: projection.effectiveCapo > 0
                                    ? _capoDown
                                    : null,
                                onCapoUp: _capoUp,
                                onDecreaseFontScale: () =>
                                    _adjustSharedFontScale(-0.1),
                                onIncreaseFontScale: () =>
                                    _adjustSharedFontScale(0.1),
                                onSetFontScale: _setSharedFontScale,
                                onPersistFontScale: _persistFontScale,
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
                                contentPadding: _contentPadding,
                              )
                            : SongReaderCompactSurface(
                                projection: projection,
                                areControlsVisible:
                                    readerState.areCompactControlsVisible,
                                currentTitle: currentTitle,
                                previousTitle: previousTitle,
                                nextTitle: nextTitle,
                                onSurfaceTap: _toggleCompactControls,
                                hasRecoverableWarnings:
                                    result.hasRecoverableWarnings,
                                warningCount: recoverableWarningCount,
                                contentColumnCount: layout.contentColumnCount,
                                showBottomContextBar:
                                    showCompactBottomContextBar,
                                onTransposeDown: _transposeDown,
                                onTransposeUp: _transposeUp,
                                onCapoDown: projection.effectiveCapo > 0
                                    ? _capoDown
                                    : null,
                                onCapoUp: _capoUp,
                                onDecreaseFontScale: () =>
                                    _adjustSharedFontScale(-0.1),
                                onIncreaseFontScale: () =>
                                    _adjustSharedFontScale(0.1),
                                onSetFontScale: _setSharedFontScale,
                                onPersistFontScale: _persistFontScale,
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
                                maxContentWidth: _contentWidth,
                                contentPadding: _contentPadding,
                              );

                        // The surface itself is full-width; ConstrainedBox and
                        // padding are applied inside the scroll view by each
                        // surface widget so the scrollbar thumb sits at the
                        // physical screen edge.
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [Expanded(child: readerSurface)],
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

String _sessionSlugFor(PlanDetail? planDetail, String sessionId) {
  final session = planDetail?.sessions
      .where((candidate) => candidate.id == sessionId)
      .firstOrNull;
  return session?.slug ?? sessionId;
}
