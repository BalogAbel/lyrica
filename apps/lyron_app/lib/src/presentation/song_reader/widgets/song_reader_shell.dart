import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/application/song_library/catalog_snapshot_state.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_types.dart';
import 'package:lyron_app/src/application/song_library/song_reader_result.dart';
import 'package:lyron_app/src/domain/song/song_access_denied_exception.dart';
import 'package:lyron_app/src/domain/song/song_not_found_exception.dart';
import 'package:lyron_app/src/presentation/song_reader/session_scoped_reader_context.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_layout.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_titles.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_bottom_bar.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_compact_surface.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_expanded_surface.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_status_views.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

/// The song reader's body shell: back-gesture handling, the loading/error/
/// tombstone states (each wrapped in the compact shell's chrome frame via
/// [_wrapCompactStatus]), and the compact-vs-expanded surface composition
/// driven by the [shellLayout] threaded down from the screen.
///
/// Takes only resolved values and callbacks — it does not read any
/// providers. Capability/route/provider decisions stay in the screen.
class SongReaderBodyShell extends StatelessWidget {
  const SongReaderBodyShell({
    super.key,
    required this.isResolvingCatalogContext,
    required this.readerAsync,
    required this.isScopedMode,
    required this.catalogState,
    required this.mutationRecord,
    required this.resolvedScopedContext,
    required this.readerState,
    required this.preservedScopedTitle,
    required this.onBack,
    required this.onRetry,
    required this.onTransposeDown,
    required this.onTransposeUp,
    required this.onCapoDown,
    required this.onCapoUp,
    required this.onAdjustSharedFontScale,
    required this.onSetFontScale,
    required this.onPersistFontScale,
    required this.onToggleCompactControls,
    required this.resolveNeighborTap,
    required this.compactTopBar,
    required this.shellLayout,
  });

  static const _contentWidth = 960.0;
  static const _contentPadding = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 14,
  );

  final bool isResolvingCatalogContext;
  final AsyncValue<SongReaderResult> readerAsync;
  final bool isScopedMode;
  final CatalogSnapshotState catalogState;
  final SongMutationRecord? mutationRecord;
  final SessionScopedReaderContext? resolvedScopedContext;
  final SongReaderState readerState;

  /// Preserved title to show in the deleted-song tombstone. Precomputed by
  /// the screen (pure, cheap) since the tombstone widget itself takes only
  /// resolved values.
  final String preservedScopedTitle;

  final void Function(BuildContext context) onBack;
  final VoidCallback onRetry;
  final VoidCallback onTransposeDown;
  final VoidCallback onTransposeUp;
  final VoidCallback onCapoDown;
  final VoidCallback onCapoUp;
  final void Function(double delta) onAdjustSharedFontScale;
  final void Function(double scale) onSetFontScale;
  final VoidCallback onPersistFontScale;
  final VoidCallback onToggleCompactControls;

  /// Resolves the tap handler for a scoped neighbor (previous/next), or null
  /// when there is no scoped context or no such neighbor. Bound by the screen
  /// since navigating to a neighbor needs screen/widget state (warmPlanDetail).
  final VoidCallback? Function(
    BuildContext context,
    SessionScopedReaderNeighbor? neighbor,
  )
  resolveNeighborTap;

  /// The reader's top bar content, rendered by the compact surface as a
  /// `Positioned` overlay (see `SongReaderCompactSurface.topBar`). The screen
  /// builds this once and decides whether it goes here or into
  /// `Scaffold.appBar`, based on which shell the same width resolves to --
  /// this widget only places it, it does not decide compact-vs-expanded.
  final Widget compactTopBar;

  /// The shell type (compact vs. expanded) and content column count for
  /// this build, resolved ONCE by the screen off `MediaQuery.sizeOf` and
  /// threaded down here -- this widget must not re-derive it from its own
  /// `LayoutBuilder` constraints. See `SongReaderScreen.build`'s comment
  /// above its `resolveSongReaderLayout` call for why a second resolution
  /// off a different width source is a bug, not a convenience.
  final SongReaderLayout shellLayout;

  /// Wraps [statusView] with the compact shell's permanently-visible top bar
  /// and always-visible bottom bar when [shellLayout] resolves to the
  /// compact shell. Used for every `readerAsync` state that is NOT `data`
  /// (loading, access denied, not found, retryable failure, tombstone,
  /// unresolved conflict, scoped-context-unavailable) -- none of these ever
  /// built `SongReaderCompactSurface`, which is the only place the chrome
  /// lived before this wrapper existed, so they rendered with no back
  /// control and no bottom bar at all on compact widths.
  ///
  /// Unlike the data state's tap-revealed overlay, the top bar here is
  /// unconditional: tap-to-reveal exists so song content can have the full
  /// screen, and there is no song content in these states. [bottomBarTitle]
  /// is whatever title is legitimately known (the tombstone's preserved
  /// title) or the neutral fallback the caller supplies -- never invented.
  ///
  /// In the expanded shell this returns [statusView] unchanged:
  /// `Scaffold.appBar` already carries the back control there (the screen
  /// only sets it to null for the compact shell), and the expanded shell's
  /// chrome model is out of scope for this work.
  Widget _wrapCompactStatus(
    BuildContext context,
    Widget statusView, {
    required String bottomBarTitle,
  }) {
    if (shellLayout.shell != SongReaderShell.compact) {
      return statusView;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        compactTopBar,
        Expanded(child: statusView),
        // No SizedBox: the bar sizes itself, bar height plus the bottom
        // safe-area inset. See SongReaderBottomBar's doc comment.
        SongReaderBottomBar(currentTitle: bottomBarTitle),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // ADR-034 scopes the chrome restructure to the COMPACT shell only -- the
    // expanded shell (>= 1600px) keeps its pre-restructure chrome and has no
    // per-surface inset handling of its own: `Scaffold.appBar` consumes only
    // the top inset, so without a SafeArea here the expanded surface (and
    // its side context/tools panels) would render under the bottom/side
    // insets on, e.g., an iPad in landscape. Wrapping only the expanded path
    // restores exactly the coverage the removed blanket SafeArea used to
    // give it, without reintroducing that blanket over the compact path --
    // which is the thing this whole restructure removed (see the compact
    // per-surface inset comments in SongReaderBottomBar/TopBar/ControlRail).
    final isExpandedShell = shellLayout.shell == SongReaderShell.expanded;

    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }

        onBack(context);
      },
      child: Builder(
        builder: (context) {
          final body = isResolvingCatalogContext
              ? _wrapCompactStatus(
                  context,
                  const SongReaderLoadingView(),
                  bottomBarTitle: AppStrings.songReaderTitle,
                )
              : readerAsync.when(
                  loading: () => _wrapCompactStatus(
                    context,
                    const SongReaderLoadingView(),
                    bottomBarTitle: AppStrings.songReaderTitle,
                  ),
                  error: (error, stackTrace) {
                    if (isScopedMode) {
                      if (error is SongNotFoundException) {
                        if (canShowScopedDeletedTombstone(
                          catalogState: catalogState,
                          mutationRecord: mutationRecord,
                        )) {
                          final message =
                              mutationRecord?.isRemoteDeletedConflict == true &&
                                  mutationRecord?.effectiveSyncStatus ==
                                      SongSyncStatus.pendingUpdate
                              ? AppStrings.songReaderDeletedConflictMessage
                              : AppStrings.songReaderDeletedMessage;
                          return _wrapCompactStatus(
                            context,
                            SongReaderDeletedTombstoneView(
                              title: preservedScopedTitle,
                              message: message,
                            ),
                            bottomBarTitle: preservedScopedTitle,
                          );
                        }
                      }
                      return _wrapCompactStatus(
                        context,
                        const SongReaderScopedUnavailableView(),
                        bottomBarTitle: AppStrings.songReaderTitle,
                      );
                    }

                    if (error is SongAccessDeniedException) {
                      return _wrapCompactStatus(
                        context,
                        const SongReaderAccessDeniedView(),
                        bottomBarTitle: AppStrings.songReaderTitle,
                      );
                    }

                    if (error is SongNotFoundException) {
                      return _wrapCompactStatus(
                        context,
                        const SongReaderNotFoundView(),
                        bottomBarTitle: AppStrings.songReaderTitle,
                      );
                    }

                    return _wrapCompactStatus(
                      context,
                      SongReaderLoadFailureView(onRetry: onRetry),
                      bottomBarTitle: AppStrings.songReaderTitle,
                    );
                  },
                  data: (SongReaderResult result) {
                    final projection = SongReaderProjection(
                      song: result.song,
                      state: readerState,
                    );
                    final currentTitle = resolveCurrentTitle(
                      scopedContext: resolvedScopedContext,
                      projection: projection,
                    );
                    final previousTitle = resolveNeighborTitle(
                      resolvedScopedContext?.previousItem?.title,
                    );
                    final nextTitle = resolveNeighborTitle(
                      resolvedScopedContext?.nextItem?.title,
                    );
                    final showExpandedContextPanel =
                        resolvedScopedContext != null;

                    // `shellLayout` is resolved once by the screen and handed
                    // down (see the field doc) rather than re-derived here off
                    // a LayoutBuilder's constraints -- so this no longer needs
                    // its own LayoutBuilder.
                    final layout = shellLayout;
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
                            onTransposeDown: onTransposeDown,
                            onTransposeUp: onTransposeUp,
                            onCapoDown: projection.effectiveCapo > 0
                                ? onCapoDown
                                : null,
                            onCapoUp: onCapoUp,
                            onDecreaseFontScale: () =>
                                onAdjustSharedFontScale(-0.1),
                            onIncreaseFontScale: () =>
                                onAdjustSharedFontScale(0.1),
                            onSetFontScale: onSetFontScale,
                            onPersistFontScale: onPersistFontScale,
                            onPreviousTap: resolveNeighborTap(
                              context,
                              resolvedScopedContext?.previousItem,
                            ),
                            onNextTap: resolveNeighborTap(
                              context,
                              resolvedScopedContext?.nextItem,
                            ),
                            contentPadding: _contentPadding,
                          )
                        : SongReaderCompactSurface(
                            projection: projection,
                            areControlsVisible:
                                readerState.areCompactControlsVisible,
                            currentTitle: currentTitle,
                            topBar: compactTopBar,
                            previousTitle: previousTitle,
                            nextTitle: nextTitle,
                            onSurfaceTap: onToggleCompactControls,
                            contentColumnCount: layout.contentColumnCount,
                            showBottomContextBar: showCompactBottomContextBar,
                            onTransposeDown: onTransposeDown,
                            onTransposeUp: onTransposeUp,
                            onCapoDown: projection.effectiveCapo > 0
                                ? onCapoDown
                                : null,
                            onCapoUp: onCapoUp,
                            onDecreaseFontScale: () =>
                                onAdjustSharedFontScale(-0.1),
                            onIncreaseFontScale: () =>
                                onAdjustSharedFontScale(0.1),
                            onSetFontScale: onSetFontScale,
                            onPersistFontScale: onPersistFontScale,
                            onPreviousTap: resolveNeighborTap(
                              context,
                              resolvedScopedContext?.previousItem,
                            ),
                            onNextTap: resolveNeighborTap(
                              context,
                              resolvedScopedContext?.nextItem,
                            ),
                            position: resolvedScopedContext?.position,
                            itemCount: resolvedScopedContext?.itemCount,
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

          // Compact gets no SafeArea (see the comment above): each of its
          // chrome surfaces owns the inset it sits against. Expanded gets
          // one, same as before this branch -- `Scaffold.appBar` already
          // strips the top inset from the body, so this only ever supplies
          // bottom/left/right, which nothing else here claims.
          return isExpandedShell ? SafeArea(child: body) : body;
        },
      ),
    );
  }
}
