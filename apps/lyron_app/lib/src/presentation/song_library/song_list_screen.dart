import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/song_library/catalog_connection_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_refresh_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_snapshot_state.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_types.dart';
import 'package:lyron_app/src/router/app_routes.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

class SongListScreen extends ConsumerWidget {
  const SongListScreen({super.key});

  static const _contentWidth = 720.0;
  static const _horizontalPadding = 24.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songsAsync = ref.watch(songLibraryListProvider);
    final catalogState = ref.watch(catalogSnapshotStateProvider);
    final mutationEntriesAsync = ref.watch(songMutationEntriesProvider);
    final isRefreshing =
        catalogState.refreshStatus == CatalogRefreshStatus.refreshing;
    final isResolvingCatalogContext =
        catalogState.context == null &&
        catalogState.refreshStatus == CatalogRefreshStatus.refreshing;

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.appName),
        actions: [
          IconButton(
            onPressed: isRefreshing
                ? null
                : () {
                    unawaited(_syncNow(ref));
                  },
            icon: const Icon(Icons.sync),
            tooltip: AppStrings.songCatalogRefreshAction,
          ),
          TextButton(
            onPressed: () {
              unawaited(_createSong(context, ref));
            },
            child: const Text(AppStrings.songCreateAction),
          ),
          TextButton(
            onPressed: () {
              context.push(AppRoutes.planList.path);
            },
            child: const Text(AppStrings.planningEntryAction),
          ),
          TextButton(
            onPressed: () {
              unawaited(_signOut(context, ref));
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
                mutationEntriesAsync.when(
                  data: (entries) => entries.isEmpty
                      ? const SizedBox.shrink()
                      : _MutationStatusSurface(entries: entries),
                  loading: () => const SizedBox.shrink(),
                  error: (error, stackTrace) => const SizedBox.shrink(),
                ),
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
                                      ':songSlug',
                                      song.slug,
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

  Future<void> _syncNow(WidgetRef ref) async {
    final context = ref.read(activeCatalogContextProvider);
    if (context != null) {
      await ref
          .read(songMutationSyncControllerProvider)
          .syncPendingSongs(
            SongMutationContext(
              userId: context.userId,
              organizationId: context.organizationId,
            ),
          );
      ref.invalidate(songMutationEntriesProvider);
      ref.invalidate(songLibraryListProvider);
    }
    await ref.read(songCatalogControllerProvider).refreshCatalog();
    ref.invalidate(songLibraryListProvider);
  }

  Future<void> _createSong(BuildContext context, WidgetRef ref) async {
    final activeContext = ref.read(activeCatalogContextProvider);
    if (activeContext == null) {
      return;
    }

    final draft = await showDialog<_SongEditorDraft>(
      context: context,
      builder: (context) => const _SongEditorDialog(),
    );
    if (draft == null) {
      return;
    }

    await ref
        .read(songLibraryServiceProvider)
        .createSong(
          context: activeContext,
          title: draft.title,
          chordproSource: draft.source,
        );
    ref.invalidate(songMutationEntriesProvider);
    ref.invalidate(songLibraryListProvider);
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final hasUnsyncedChanges = await ref.read(
      hasUnsyncedSongMutationsProvider.future,
    );
    if (!context.mounted) {
      return;
    }
    if (hasUnsyncedChanges) {
      final shouldContinue = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text(AppStrings.unsyncedSignOutTitle),
          content: const Text(AppStrings.unsyncedSignOutMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(AppStrings.songCancelAction),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text(AppStrings.unsyncedSignOutConfirmAction),
            ),
          ],
        ),
      );
      if (shouldContinue != true) {
        return;
      }
    }

    await ref.read(songCatalogControllerProvider).handleExplicitSignOut();
    await ref.read(appAuthControllerProvider).signOut();
  }
}

class _MutationStatusSurface extends ConsumerWidget {
  const _MutationStatusSurface({required this.entries});

  static const _maxHeight = 240.0;
  final List<SongMutationRecord> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: _maxHeight),
        child: ListView(
          shrinkWrap: true,
          children: entries
              .map(
                (entry) => Card(
                  child: ListTile(
                    title: Text(entry.title),
                    subtitle: Text(_messageFor(entry)),
                    trailing: entry.syncStatus == SongSyncStatus.conflict
                        ? Wrap(
                            spacing: 8,
                            children: [
                              TextButton(
                                onPressed: () async {
                                  final activeContext = ref.read(
                                    activeCatalogContextProvider,
                                  );
                                  if (activeContext == null) {
                                    return;
                                  }
                                  try {
                                    await ref
                                        .read(songMutationSyncControllerProvider)
                                        .keepMine(
                                          SongMutationContext(
                                            userId: activeContext.userId,
                                            organizationId:
                                                activeContext.organizationId,
                                          ),
                                          songId: entry.id,
                                        );
                                    ref.invalidate(songMutationEntriesProvider);
                                    ref.invalidate(songLibraryListProvider);
                                  } on SongMutationSyncException catch (error) {
                                    ref.invalidate(songMutationEntriesProvider);
                                    if (!context.mounted) {
                                      return;
                                    }
                                    await _showSyncIssueDialog(
                                      context,
                                      message: _messageFor(
                                        entry.copyWith(
                                          errorCode: error.code,
                                          errorMessage: error.message,
                                        ),
                                      ),
                                    );
                                  }
                                },
                                child: const Text(AppStrings.songKeepMineAction),
                              ),
                              TextButton(
                                onPressed: () async {
                                  final activeContext = ref.read(
                                    activeCatalogContextProvider,
                                  );
                                  if (activeContext == null) {
                                    return;
                                  }
                                  try {
                                    await ref
                                        .read(songMutationSyncControllerProvider)
                                        .discardMine(
                                          SongMutationContext(
                                            userId: activeContext.userId,
                                            organizationId:
                                                activeContext.organizationId,
                                          ),
                                          songId: entry.id,
                                        );
                                    ref.invalidate(songMutationEntriesProvider);
                                    ref.invalidate(songLibraryListProvider);
                                  } on SongMutationSyncException catch (error) {
                                    ref.invalidate(songMutationEntriesProvider);
                                    if (!context.mounted) {
                                      return;
                                    }
                                    await _showSyncIssueDialog(
                                      context,
                                      message: _messageFor(
                                        entry.copyWith(
                                          errorCode: error.code,
                                          errorMessage: error.message,
                                        ),
                                      ),
                                    );
                                  }
                                },
                                child: const Text(
                                  AppStrings.songDiscardMineAction,
                                ),
                              ),
                            ],
                          )
                        : null,
                  ),
                ),
              )
              .toList(growable: false),
        ),
      ),
    );
  }

  String _messageFor(SongMutationRecord entry) {
    if (entry.syncStatus == SongSyncStatus.conflict &&
        (entry.errorCode == null ||
            entry.errorCode == SongMutationSyncErrorCode.conflict)) {
      return AppStrings.songConflictMessage;
    }
    return switch (entry.errorCode) {
      SongMutationSyncErrorCode.authorizationDenied =>
        'Song sync is blocked because edit access was revoked.',
      SongMutationSyncErrorCode.dependencyBlocked =>
        AppStrings.songDeleteBlockedMessage,
      SongMutationSyncErrorCode.connectivityFailure =>
        'Song changes are pending until connectivity returns.',
      SongMutationSyncErrorCode.unknown =>
        entry.errorMessage ?? 'Song changes are pending sync.',
      null => entry.errorMessage ?? 'Song changes are pending sync.',
      SongMutationSyncErrorCode.conflict => AppStrings.songConflictMessage,
    };
  }

  Future<void> _showSyncIssueDialog(
    BuildContext context, {
    required String message,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AppStrings.songSyncIssueTitle),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(AppStrings.songCancelAction),
          ),
        ],
      ),
    );
  }
}

class _SongEditorDraft {
  const _SongEditorDraft({required this.title, required this.source});

  final String title;
  final String source;
}

class _SongEditorDialog extends StatefulWidget {
  const _SongEditorDialog();

  @override
  State<_SongEditorDialog> createState() => _SongEditorDialogState();
}

class _SongEditorDialogState extends State<_SongEditorDialog> {
  late final TextEditingController _titleController = TextEditingController();
  late final TextEditingController _sourceController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    _sourceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(AppStrings.songCreateAction),
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
              maxLines: 8,
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
          onPressed: () {
            Navigator.of(context).pop(
              _SongEditorDraft(
                title: _titleController.text.trim(),
                source: _sourceController.text,
              ),
            );
          },
          child: const Text(AppStrings.songSaveAction),
        ),
      ],
    );
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
