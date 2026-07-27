import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/application/song_library/catalog_snapshot_state.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_types.dart';
import 'package:lyron_app/src/application/song_library/song_reader_result.dart';
import 'package:lyron_app/src/domain/song/parse_diagnostic.dart';
import 'package:lyron_app/src/domain/song/song_access_denied_exception.dart';
import 'package:lyron_app/src/domain/song/song_not_found_exception.dart';
import 'package:lyron_app/src/presentation/song_reader/session_scoped_reader_context.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_layout.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_titles.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_compact_surface.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_expanded_surface.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_status_views.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

/// The song reader's body shell: back-gesture handling, the loading/error/
/// tombstone states, and the `LayoutBuilder`-driven compact-vs-expanded
/// surface composition.
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
  });

  static const _contentWidth = 960.0;
  static const _contentPadding = EdgeInsets.all(24);

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

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }

        onBack(context);
      },
      child: SafeArea(
        child: isResolvingCatalogContext
            ? const SongReaderLoadingView()
            : readerAsync.when(
                loading: () => const SongReaderLoadingView(),
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
                        return SongReaderDeletedTombstoneView(
                          title: preservedScopedTitle,
                          message: message,
                        );
                      }
                    }
                    return const SongReaderScopedUnavailableView();
                  }

                  if (error is SongAccessDeniedException) {
                    return const SongReaderAccessDeniedView();
                  }

                  if (error is SongNotFoundException) {
                    return const SongReaderNotFoundView();
                  }

                  return SongReaderLoadFailureView(onRetry: onRetry);
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
                              previousTitle: previousTitle,
                              nextTitle: nextTitle,
                              onSurfaceTap: onToggleCompactControls,
                              hasRecoverableWarnings:
                                  result.hasRecoverableWarnings,
                              warningCount: recoverableWarningCount,
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
    );
  }
}
