import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/song_library/catalog_connection_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_refresh_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_snapshot_state.dart';
import 'package:lyron_app/src/application/song_library/chordpro_import_types.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_types.dart';
import 'package:lyron_app/src/presentation/song_library/chordpro_import_controller.dart';
import 'package:lyron_app/src/presentation/song_library/song_library_browse_state.dart';
import 'package:lyron_app/src/presentation/song_library/widgets/import_duplicate_dialog.dart';
import 'package:lyron_app/src/presentation/song_library/widgets/import_summary_dialog.dart';
import 'package:lyron_app/src/presentation/sync/unified_sync_header_control.dart';
import 'package:lyron_app/src/presentation/sync/unified_sync_providers.dart';
import 'package:lyron_app/src/router/app_routes.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

class SongListScreen extends ConsumerStatefulWidget {
  const SongListScreen({super.key});

  static const _contentWidth = 720.0;
  static const _horizontalPadding = 24.0;

  @override
  ConsumerState<SongListScreen> createState() => _SongListScreenState();
}

class _SongListScreenState extends ConsumerState<SongListScreen> {
  late final TextEditingController _searchController;
  List<SongMutationRecord>? _cachedMutationEntries;
  String? _cachedMutationEntriesOrganizationId;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(catalogSnapshotStateProvider.select((state) => state.context), (
      previous,
      next,
    ) {
      if (previous == next) {
        return;
      }
      if (previous == null && next == null) {
        return;
      }
      setState(() {
        _cachedMutationEntries = null;
        _cachedMutationEntriesOrganizationId = null;
      });
      ref.read(songLibraryBrowseControllerProvider.notifier).reset();
    });

    ref.listen(songMutationEntriesProvider, (previous, next) {
      if (!next.hasValue) {
        return;
      }

      final nextValue = next.value!;
      final activeOrganizationId = ref.read(
        catalogSnapshotStateProvider.select(
          (state) => state.context?.organizationId,
        ),
      );
      final nextOrganizationId = nextValue.isEmpty
          ? activeOrganizationId
          : nextValue.first.organizationId;
      if (activeOrganizationId != null &&
          (nextOrganizationId == null ||
              nextOrganizationId != activeOrganizationId)) {
        return;
      }

      if (identical(_cachedMutationEntries, nextValue) &&
          _cachedMutationEntriesOrganizationId == nextOrganizationId) {
        return;
      }

      setState(() {
        _cachedMutationEntries = nextValue;
        _cachedMutationEntriesOrganizationId = nextOrganizationId;
      });
    });

    final songsAsync = ref.watch(songLibraryListProvider);
    final catalogState = ref.watch(catalogSnapshotStateProvider);
    final browseState = ref.watch(songLibraryBrowseControllerProvider);
    final mutationEntriesAsync = ref.watch(songMutationEntriesProvider);
    final isResolvingCatalogContext =
        catalogState.context == null &&
        catalogState.refreshStatus == CatalogRefreshStatus.refreshing;

    ref.listen(songLibraryBrowseControllerProvider.select((s) => s.query), (
      previous,
      next,
    ) {
      if (_searchController.text == next) {
        return;
      }

      _searchController.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: next.length),
      );
    });

    ref.listen<ChordProImportState>(chordProImportControllerProvider, (
      previous,
      next,
    ) {
      if (!mounted) return;
      switch (next) {
        case ImportAwaitingDuplicateResolution(:final result, :final successes):
          unawaited(_resolveImportDuplicates(context, ref, result, successes));
        case ImportDone(:final result, :final skippedCount):
          unawaited(
            showImportSummaryDialog(
              context: context,
              result: result,
              skippedCount: skippedCount,
            ).then((_) {
              if (mounted) {
                ref.invalidate(songLibraryListProvider);
                ref.read(chordProImportControllerProvider.notifier).reset();
              }
            }),
          );
        case ImportFailed(:final message):
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
          ref.read(chordProImportControllerProvider.notifier).reset();
        default:
          break;
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.appName),
        actions: [
          const UnifiedSyncHeaderControl(),
          TextButton(
            onPressed: () {
              unawaited(
                ref
                    .read(chordProImportControllerProvider.notifier)
                    .startImport(),
              );
            },
            child: const Text(AppStrings.songImportAction),
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
            constraints: const BoxConstraints(
              maxWidth: SongListScreen._contentWidth,
            ),
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    SongListScreen._horizontalPadding,
                    0,
                    SongListScreen._horizontalPadding,
                    12,
                  ),
                  child: TextField(
                    key: const ValueKey('song-list-search-field'),
                    controller: _searchController,
                    enabled: !isResolvingCatalogContext,
                    decoration: const InputDecoration(
                      labelText: AppStrings.songListSearchLabel,
                      hintText: AppStrings.songListSearchHint,
                    ),
                    onChanged: (value) {
                      ref
                          .read(songLibraryBrowseControllerProvider.notifier)
                          .setQuery(value);
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    SongListScreen._horizontalPadding,
                    0,
                    SongListScreen._horizontalPadding,
                    12,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SegmentedButton<SongLibraryBrowseFilter>(
                      key: const ValueKey('song-list-filter-control'),
                      segments: const [
                        ButtonSegment(
                          value: SongLibraryBrowseFilter.all,
                          label: Text(AppStrings.songLibraryFilterAllLabel),
                        ),
                        ButtonSegment(
                          value: SongLibraryBrowseFilter.pendingSync,
                          label: Text(
                            AppStrings.songLibraryFilterPendingSyncLabel,
                          ),
                        ),
                        ButtonSegment(
                          value: SongLibraryBrowseFilter.conflicts,
                          label: Text(
                            AppStrings.songLibraryFilterConflictsLabel,
                          ),
                        ),
                      ],
                      selected: {browseState.filter},
                      onSelectionChanged: (selection) {
                        if (selection.isEmpty) {
                          return;
                        }
                        ref
                            .read(songLibraryBrowseControllerProvider.notifier)
                            .setFilter(selection.first);
                      },
                    ),
                  ),
                ),
                Expanded(
                  child: isResolvingCatalogContext
                      ? const Center(
                          child: Text(AppStrings.songListLoadingMessage),
                        )
                      : Builder(
                          builder: (context) {
                            final songs = songsAsync.valueOrNull;
                            if (songs == null && songsAsync.hasError) {
                              return _RetryableErrorState(
                                message: AppStrings.songListLoadFailureMessage,
                                onRetry: () =>
                                    ref.invalidate(songLibraryListProvider),
                              );
                            }

                            if (songs == null) {
                              return const Center(
                                child: Text(AppStrings.songListLoadingMessage),
                              );
                            }

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

                            final browseRows = ref.watch(
                              songLibraryBrowseRowsProvider,
                            );

                            final activeOrganizationId =
                                catalogState.context?.organizationId;
                            final mutationEntries = _resolveMutationEntries(
                              activeOrganizationId: activeOrganizationId,
                              mutationEntriesAsync: mutationEntriesAsync,
                            );
                            final mutationRowsReady = mutationEntries != null;
                            if (!mutationRowsReady &&
                                browseState.filter !=
                                    SongLibraryBrowseFilter.all) {
                              if (mutationEntriesAsync.hasError) {
                                return _RetryableErrorState(
                                  message: AppStrings
                                      .songListMutationStatusFailedMessage,
                                  onRetry: () => ref.invalidate(
                                    songMutationEntriesProvider,
                                  ),
                                );
                              }

                              return const Center(
                                child: Text(
                                  AppStrings
                                      .songListMutationStatusLoadingMessage,
                                ),
                              );
                            }

                            final visibleSongs = browseRows
                                .map((row) => row.song)
                                .toList(growable: false);
                            final mutationStatusMessage =
                                mutationEntriesAsync.isLoading
                                ? AppStrings
                                      .songListMutationStatusLoadingMessage
                                : mutationEntriesAsync.hasError
                                ? AppStrings.songListMutationStatusFailedMessage
                                : null;

                            Widget content;
                            if (visibleSongs.isEmpty) {
                              content = const Center(
                                child: Text(
                                  AppStrings.songListNoResultsMessage,
                                ),
                              );
                            } else {
                              content = ListView.separated(
                                key: const ValueKey(
                                  'song-library-results-list',
                                ),
                                padding: const EdgeInsets.all(
                                  SongListScreen._horizontalPadding,
                                ),
                                itemCount: visibleSongs.length,
                                separatorBuilder: (context, index) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final song = visibleSongs[index];

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
                            }

                            return Column(
                              children: [
                                if (mutationStatusMessage != null)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      SongListScreen._horizontalPadding,
                                      0,
                                      SongListScreen._horizontalPadding,
                                      12,
                                    ),
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        mutationStatusMessage,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    ),
                                  ),
                                Expanded(child: content),
                              ],
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

  List<SongMutationRecord>? _resolveMutationEntries({
    required String? activeOrganizationId,
    required AsyncValue<List<SongMutationRecord>> mutationEntriesAsync,
  }) {
    final mutationEntriesFromProvider = mutationEntriesAsync.valueOrNull;
    final mutationEntriesFromProviderOrganizationId =
        mutationEntriesFromProvider == null
        ? null
        : mutationEntriesFromProvider.isEmpty
        ? activeOrganizationId
        : mutationEntriesFromProvider.first.organizationId;

    return activeOrganizationId == null
        ? mutationEntriesFromProvider ?? _cachedMutationEntries
        : mutationEntriesFromProviderOrganizationId == activeOrganizationId
        ? mutationEntriesFromProvider
        : _cachedMutationEntriesOrganizationId == activeOrganizationId
        ? _cachedMutationEntries
        : null;
  }

  Future<void> _createSong(BuildContext context, WidgetRef ref) async {
    final activeContext = ref.read(activeCatalogContextProvider);
    if (activeContext == null) {
      return;
    }
    context.push(AppRoutes.songCreate.path);
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final hasUnsyncedChanges = ref
        .read(unifiedSyncOverviewProvider)
        .hasUnsyncedWork;
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
    await ref.read(planningSyncControllerProvider).handleExplicitSignOut();
    await ref.read(appAuthControllerProvider).signOut();
  }

  Future<void> _resolveImportDuplicates(
    BuildContext context,
    WidgetRef ref,
    ImportBatchResult result,
    List<ImportSuccess> successes,
  ) async {
    if (!mounted) return;
    final resolved = await showImportDuplicateDialog(
      context: context,
      duplicates: result.duplicates,
    );
    if (!mounted) return;
    if (resolved == null) {
      ref.read(chordProImportControllerProvider.notifier).reset();
      return;
    }
    await ref
        .read(chordProImportControllerProvider.notifier)
        .commitWithResolutions(
          successes: successes,
          resolvedDuplicates: resolved,
        );
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
                                        .read(
                                          songMutationSyncControllerProvider,
                                        )
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
                                child: const Text(
                                  AppStrings.songKeepMineAction,
                                ),
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
                                        .read(
                                          songMutationSyncControllerProvider,
                                        )
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
      SongMutationSyncErrorCode.remoteDeleted =>
        'This song was removed on another device. Resolve the conflict to keep your version or accept the deletion.',
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
