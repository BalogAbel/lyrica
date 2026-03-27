import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lyrica_app/src/application/providers.dart';
import 'package:lyrica_app/src/application/song_library/catalog_connection_status.dart';
import 'package:lyrica_app/src/application/song_library/catalog_refresh_status.dart';
import 'package:lyrica_app/src/application/song_library/catalog_snapshot_state.dart';
import 'package:lyrica_app/src/router/app_routes.dart';
import 'package:lyrica_app/src/shared/app_strings.dart';

class SongListScreen extends ConsumerWidget {
  const SongListScreen({super.key});

  static const _contentWidth = 720.0;
  static const _horizontalPadding = 24.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songsAsync = ref.watch(songLibraryListProvider);
    final catalogState = ref.watch(catalogSnapshotStateProvider);
    final isResolvingCatalogContext =
        catalogState.context == null &&
        catalogState.refreshStatus == CatalogRefreshStatus.refreshing;

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.appName),
        actions: [
          TextButton(
            onPressed: () {
              unawaited(_signOut(ref));
            },
            child: const Text(AppStrings.signOutAction),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _contentWidth),
            child: Column(
              children: [
                _CatalogStatusSurface(state: catalogState),
                Expanded(
                  child: isResolvingCatalogContext
                      ? const Center(
                          child: Text(AppStrings.songListLoadingMessage),
                        )
                      : songsAsync.when(
                          loading: () => const Center(
                            child: Text(AppStrings.songListLoadingMessage),
                          ),
                          error: (error, stackTrace) => _RetryableErrorState(
                            message: AppStrings.songListLoadFailureMessage,
                            onRetry: () =>
                                ref.invalidate(songLibraryListProvider),
                          ),
                          data: (songs) {
                            if (!catalogState.hasCachedCatalog &&
                                catalogState.connectionStatus ==
                                    CatalogConnectionStatus.unavailable) {
                              return const Center(
                                child: Text(
                                  AppStrings.songCatalogUnavailableMessage,
                                ),
                              );
                            }

                            if (songs.isEmpty) {
                              return const Center(
                                child: Text(AppStrings.songListEmptyMessage),
                              );
                            }

                            return ListView.separated(
                              padding: const EdgeInsets.all(_horizontalPadding),
                              itemCount: songs.length,
                              separatorBuilder: (context, index) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final song = songs[index];

                                return ListTile(
                                  title: Text(song.title),
                                  onTap: () => context.push(
                                    AppRoutes.songReader.path.replaceFirst(
                                      ':songId',
                                      song.id,
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _signOut(WidgetRef ref) async {
    await ref.read(songCatalogControllerProvider).handleExplicitSignOut();
    await ref.read(appAuthControllerProvider).signOut();
  }
}

class _RetryableErrorState extends StatelessWidget {
  const _RetryableErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: onRetry,
            child: const Text(AppStrings.retryAction),
          ),
        ],
      ),
    );
  }
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: DecoratedBox(
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
      ),
    );
  }
}
