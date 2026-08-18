import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/app/theme_mode_store.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/song_library/catalog_refresh_status.dart';
import 'package:lyron_app/src/domain/core/capability.dart';
import 'package:lyron_app/src/domain/planning/plan_detail.dart';
import 'package:lyron_app/src/domain/song/parse_diagnostic.dart';
import 'package:lyron_app/src/presentation/song_reader/session_scoped_reader_context.dart';
import 'package:lyron_app/src/presentation/song_reader/session_scoped_reader_context_provider.dart';
import 'package:lyron_app/src/presentation/song_reader/session_scoped_reader_runtime_controller.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_commands.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_controller.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_immersive_mode.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_layout.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_preferences_store.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_providers.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_scoped_navigation.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_song_actions.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_titles.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_zoom_persistence.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_app_bar.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_overflow_menu.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_shell.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_status_views.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_top_bar.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

export 'song_reader_providers.dart' show readerUserIdProvider;

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

  // Same rationale as `_songActions`: cheap to rebuild, and `onChanged` must
  // always close over the current `setState` (this State object never
  // changes, but keeping construction here matches the other delegate
  // getters and keeps `setState` ownership visibly on the screen).
  SongReaderCommands get _commands => SongReaderCommands(
    controller: _controller,
    onChanged: () => setState(() {}),
  );

  // Same rationale again: cheap, and always reflects the current widget
  // fields (needed for the same scoped song-to-song reason as `_songActions`).
  SongReaderScopedNavigation get _scopedNavigation =>
      SongReaderScopedNavigation(
        planId: widget.planId,
        sessionId: widget.sessionId,
        sessionItemId: widget.sessionItemId,
        warmPlanDetail: widget.warmPlanDetail,
        songId: widget.songId,
      );

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
        isMounted: () => mounted,
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

  void _toggleViewMode() {
    _commands.toggleViewMode(
      ref: ref,
      isScopedMode: _isScopedMode,
      sessionKey: _sessionKey,
    );
  }

  void _transposeDown() {
    _commands.transposeDown(
      ref: ref,
      isScopedMode: _isScopedMode,
      sessionKey: _sessionKey,
    );
  }

  void _transposeUp() {
    _commands.transposeUp(
      ref: ref,
      isScopedMode: _isScopedMode,
      sessionKey: _sessionKey,
    );
  }

  void _capoDown() {
    _commands.capoDown(
      ref: ref,
      isScopedMode: _isScopedMode,
      sessionKey: _sessionKey,
    );
  }

  void _capoUp() {
    _commands.capoUp(
      ref: ref,
      isScopedMode: _isScopedMode,
      sessionKey: _sessionKey,
    );
  }

  void _setInstrumentDisplayMode(SongReaderInstrumentDisplayMode mode) {
    _commands.setInstrumentDisplayMode(
      mode,
      ref: ref,
      isScopedMode: _isScopedMode,
      sessionKey: _sessionKey,
    );
  }

  void _adjustSharedFontScale(double delta) {
    _commands.adjustSharedFontScale(
      delta,
      ref: ref,
      isScopedMode: _isScopedMode,
      sessionKey: _sessionKey,
      persistFontScale: _persistFontScale,
    );
  }

  void _setSharedFontScale(double scale) {
    _commands.setSharedFontScale(
      scale,
      ref: ref,
      isScopedMode: _isScopedMode,
      sessionKey: _sessionKey,
    );
  }

  /// Reads whether the compact controls are currently visible from the active
  /// state source (scoped runtime controller or local controller). Kept on
  /// the screen (not moved into [SongReaderCommands]) because it feeds
  /// [_syncImmersiveToControls] and the `wasImmersive` capture in the edit
  /// flow — both screen-lifecycle/immersive-mode concerns, not command
  /// dispatch.
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
  /// or a pushed route's pop reset the global system UI state. Kept on the
  /// screen because it reads `mounted`, which only the `State` object has.
  void _syncImmersiveToControls() {
    if (!mounted) {
      return;
    }
    _immersiveMode.apply(_areControlsVisible);
  }

  void _toggleCompactControls() {
    _commands.toggleCompactControls(
      ref: ref,
      isScopedMode: _isScopedMode,
      sessionKey: _sessionKey,
      immersiveMode: _immersiveMode,
    );
  }

  void _handleBack(BuildContext context) {
    _scopedNavigation.handleBack(context, immersiveMode: _immersiveMode);
  }

  void _syncScopedRuntimeState() {
    _scopedNavigation.syncScopedRuntimeState(
      ref: ref,
      isMounted: () => mounted,
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
    final readerResult = readerAsync.value;
    final scopedContextResult = scopedContextAsync?.value;
    final resolvedScopedContext =
        scopedContextResult is ResolvedSessionScopedReaderContextResult
        ? scopedContextResult.context
        : null;
    final mutationRecord = mutationRecordAsync?.value;
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
      final scopedValue = scopedContextAsync.value;
      if (scopedValue is SessionScopedReaderContextFailureResult) {
        return SongReaderScopedContextFailureScaffold(
          onBack: () => _handleBack(context),
        );
      }
    }

    // Resolved once, here, off MediaQuery -- and threaded down into
    // SongReaderBodyShell as `shellLayout` rather than re-derived. The body
    // used to re-run resolveSongReaderLayout off its own LayoutBuilder's
    // constraints.maxWidth, which sits inside the body's SafeArea and can
    // disagree with this MediaQuery width once SafeArea eats left/right
    // insets (landscape on a notched device). A single resolution threaded
    // down cannot disagree with itself.
    final shellLayout = resolveSongReaderLayout(
      viewportWidth: MediaQuery.sizeOf(context).width,
      isAutoFitEnabled: readerState.isAutoFitEnabled,
    );
    final isCompactShell = shellLayout.shell == SongReaderShell.compact;

    void handleOverflowAction(SongReaderOverflowAction action) {
      switch (action) {
        case SongReaderOverflowAction.toggleViewMode:
          _toggleViewMode();
          break;
        case SongReaderOverflowAction.guitarView:
          _setInstrumentDisplayMode(SongReaderInstrumentDisplayMode.guitar);
          break;
        case SongReaderOverflowAction.pianoView:
          _setInstrumentDisplayMode(SongReaderInstrumentDisplayMode.piano);
          break;
        case SongReaderOverflowAction.toggleTheme:
          unawaited(
            ref
                .read(themeModeControllerProvider.notifier)
                .toggle(Theme.of(context).brightness),
          );
          break;
        case SongReaderOverflowAction.edit:
          unawaited(
            _songActions.edit(
              context,
              ref,
              immersiveMode: _immersiveMode,
              readControlsVisible: () => _areControlsVisible,
            ),
          );
          break;
        case SongReaderOverflowAction.delete:
          unawaited(_songActions.delete(context, ref, onDeleted: _handleBack));
          break;
      }
    }

    // SongReaderAppBar (a `PreferredSizeWidget`) is still what the EXPANDED
    // shell renders via `Scaffold.appBar` -- the expanded shell keeps its
    // current chrome (spec section 7). It is no longer what the compact
    // shell uses: that shell gets `SongReaderTopBar`, its own floating
    // overlay (song-presentation-slice Task 7), built separately below with
    // the same resolved values and the same `handleOverflowAction`.
    final readerAppBar = SongReaderAppBar(
      title: currentTitle,
      effectiveKey: projection?.effectiveKey,
      onBack: () => _handleBack(context),
      hasRecoverableWarnings: hasRecoverableWarnings,
      onShowWarnings: () =>
          _showWarningsDialog(context, recoverableWarningCount),
      showOverflowMenu: readerResult != null,
      viewMode: readerState.viewMode,
      canEditSongs: canEditSongs,
      isDarkActive: Theme.of(context).brightness == Brightness.dark,
      onOverflowAction: handleOverflowAction,
    );

    final compactTopBar = SongReaderTopBar(
      title: currentTitle,
      onBack: () => _handleBack(context),
      hasRecoverableWarnings: hasRecoverableWarnings,
      onShowWarnings: () =>
          _showWarningsDialog(context, recoverableWarningCount),
      showOverflowMenu: readerResult != null,
      viewMode: readerState.viewMode,
      canEditSongs: canEditSongs,
      isDarkActive: Theme.of(context).brightness == Brightness.dark,
      onOverflowAction: handleOverflowAction,
    );

    return Scaffold(
      appBar: isCompactShell ? null : readerAppBar,
      body: SongReaderBodyShell(
        shellLayout: shellLayout,
        compactTopBar: compactTopBar,
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
            _scopedNavigation.buildScopedNeighborNavigationTap(
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
