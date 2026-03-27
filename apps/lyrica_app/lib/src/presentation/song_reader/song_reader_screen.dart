import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lyrica_app/src/application/providers.dart';
import 'package:lyrica_app/src/application/song_library/catalog_connection_status.dart';
import 'package:lyrica_app/src/application/song_library/catalog_refresh_status.dart';
import 'package:lyrica_app/src/application/song_library/catalog_snapshot_state.dart';
import 'package:lyrica_app/src/application/song_library/song_reader_result.dart';
import 'package:lyrica_app/src/domain/song/parse_diagnostic.dart';
import 'package:lyrica_app/src/domain/song/song_access_denied_exception.dart';
import 'package:lyrica_app/src/domain/song/song_not_found_exception.dart';
import 'package:lyrica_app/src/presentation/song_reader/song_reader_controller.dart';
import 'package:lyrica_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyrica_app/src/presentation/song_reader/widgets/song_reader_header.dart';
import 'package:lyrica_app/src/presentation/song_reader/widgets/song_section_view.dart';
import 'package:lyrica_app/src/router/app_routes.dart';
import 'package:lyrica_app/src/shared/app_strings.dart';

class SongReaderScreen extends ConsumerStatefulWidget {
  const SongReaderScreen({super.key, required this.songId});

  final String songId;

  @override
  ConsumerState<SongReaderScreen> createState() => _SongReaderScreenState();
}

class _SongReaderScreenState extends ConsumerState<SongReaderScreen> {
  static const _contentWidth = 960.0;
  static const _contentPadding = EdgeInsets.all(24);

  late final SongReaderController _controller = SongReaderController();

  void _updateState(void Function(SongReaderController controller) update) {
    setState(() {
      update(_controller);
    });
  }

  void _handleBack(BuildContext context) {
    if (context.canPop()) {
      context.pop();
      return;
    }

    context.replace(AppRoutes.home.path);
  }

  @override
  Widget build(BuildContext context) {
    final readerAsync = ref.watch(songLibraryReaderProvider(widget.songId));
    final catalogState = ref.watch(catalogSnapshotStateProvider);
    final isResolvingCatalogContext =
        catalogState.context == null &&
        catalogState.refreshStatus == CatalogRefreshStatus.refreshing;

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
                      state: _controller.state,
                    );
                    final recoverableWarningCount = result.song.diagnostics
                        .where(
                          (diagnostic) =>
                              diagnostic.severity ==
                              ParseDiagnosticSeverity.warning,
                        )
                        .length;

                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: _contentWidth,
                        ),
                        child: ListView(
                          padding: _contentPadding,
                          children: [
                            _CatalogStatusSurface(state: catalogState),
                            if (_hasVisibleStatus(catalogState))
                              const SizedBox(height: 24),
                            SongReaderHeader(
                              projection: projection,
                              hasRecoverableWarnings:
                                  result.hasRecoverableWarnings,
                              warningCount: recoverableWarningCount,
                              onToggleViewMode: () {
                                _updateState(
                                  (controller) => controller.toggleViewMode(),
                                );
                              },
                              onTransposeDown: () {
                                _updateState(
                                  (controller) => controller.transposeDown(),
                                );
                              },
                              onTransposeUp: () {
                                _updateState(
                                  (controller) => controller.transposeUp(),
                                );
                              },
                              onDecreaseFontScale: () {
                                _updateState((controller) {
                                  controller.setSharedFontScale(
                                    controller.state.sharedFontScale - 0.1,
                                  );
                                });
                              },
                              onIncreaseFontScale: () {
                                _updateState((controller) {
                                  controller.setSharedFontScale(
                                    controller.state.sharedFontScale + 0.1,
                                  );
                                });
                              },
                            ),
                            const SizedBox(height: 24),
                            for (final section in projection.sections) ...[
                              SongSectionView(
                                section: section,
                                viewMode: projection.viewMode,
                                sharedFontScale: projection.sharedFontScale,
                              ),
                              const SizedBox(height: 20),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
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
