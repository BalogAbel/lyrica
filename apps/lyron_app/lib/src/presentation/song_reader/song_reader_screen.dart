import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/song_library/catalog_refresh_status.dart';
import 'package:lyron_app/src/domain/core/capability.dart';
import 'package:lyron_app/src/domain/planning/plan_detail.dart';
import 'package:lyron_app/src/domain/song/parse_diagnostic.dart';
import 'package:lyron_app/src/presentation/planning/planning_routes.dart';
import 'package:lyron_app/src/presentation/song_reader/session_scoped_reader_context.dart';
import 'package:lyron_app/src/presentation/song_reader/session_scoped_reader_context_provider.dart';
import 'package:lyron_app/src/presentation/song_reader/session_scoped_reader_runtime_controller.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_controller.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_immersive_mode.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_preferences_store.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_song_actions.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_titles.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_zoom_persistence.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_app_bar.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_overflow_menu.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_shell.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_status_views.dart';
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
    final preservedScopedTitle = resolvePreservedScopedTitle(
      scopedContext: resolvedScopedContext,
      warmPlanDetail: widget.warmPlanDetail,
      sessionItemId: widget.sessionItemId,
      songId: widget.songId,
    );
    final currentTitle = projection == null
        ? preservedScopedTitle
        : resolveCurrentTitle(
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
        return SongReaderScopedContextFailureScaffold(
          onBack: () => _handleBack(context),
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
      body: SongReaderBodyShell(
        isResolvingCatalogContext: isResolvingCatalogContext,
        readerAsync: readerAsync,
        isScopedMode: _isScopedMode,
        catalogState: catalogState,
        mutationRecord: mutationRecord,
        resolvedScopedContext: resolvedScopedContext,
        readerState: readerState,
        preservedScopedTitle: preservedScopedTitle,
        onBack: _handleBack,
        onRetry: () => ref.invalidate(songLibraryReaderProvider(widget.songId)),
        onTransposeDown: _transposeDown,
        onTransposeUp: _transposeUp,
        onCapoDown: _capoDown,
        onCapoUp: _capoUp,
        onAdjustSharedFontScale: _adjustSharedFontScale,
        onSetFontScale: _setSharedFontScale,
        onPersistFontScale: _persistFontScale,
        onToggleCompactControls: _toggleCompactControls,
        resolveNeighborTap: (context, neighbor) =>
            _buildScopedNeighborNavigationTap(
              context,
              scopedContext: resolvedScopedContext,
              neighbor: neighbor,
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
