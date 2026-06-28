import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/song_library/catalog_connection_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_refresh_status.dart';
import 'package:lyron_app/src/application/song_library/chordpro_import_types.dart';
import 'package:lyron_app/src/domain/core/capability.dart';
import 'package:lyron_app/src/presentation/auth/reauth_banner.dart';
import 'package:lyron_app/src/presentation/shared/if_capability.dart';
import 'package:lyron_app/src/presentation/song_library/chordpro_import_controller.dart';
import 'package:lyron_app/src/presentation/song_library/widgets/import_duplicate_dialog.dart';
import 'package:lyron_app/src/presentation/song_library/widgets/import_summary_dialog.dart';
import 'package:lyron_app/src/presentation/sync/unified_sync_header_control.dart';
import 'package:lyron_app/src/presentation/sync/unified_sync_providers.dart';
import 'package:lyron_app/src/router/app_routes.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

enum _SongListMenuAction { import, signOut }

class SongListScreen extends ConsumerStatefulWidget {
  const SongListScreen({super.key});

  static const _contentWidth = 720.0;
  static const _horizontalPadding = 24.0;

  @override
  ConsumerState<SongListScreen> createState() => _SongListScreenState();
}

class _SongListScreenState extends ConsumerState<SongListScreen> {
  late final TextEditingController _searchController;

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
      ref.read(songLibraryBrowseControllerProvider.notifier).reset();
    });

    final songsAsync = ref.watch(songLibraryListProvider);
    final catalogState = ref.watch(catalogSnapshotStateProvider);
    final isResolvingCatalogContext =
        catalogState.context == null &&
        catalogState.refreshStatus == CatalogRefreshStatus.refreshing;
    final orgId = catalogState.context?.organizationId;

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
          IconButton(
            key: const Key('song-plans-button'),
            tooltip: AppStrings.planningEntryAction,
            icon: const Icon(Icons.event_note_outlined),
            onPressed: () {
              context.push(AppRoutes.planList.path);
            },
          ),
          IfCapability(
            key: const Key('song-create-button'),
            capability: Capability.editSongs,
            organizationId: orgId,
            child: IconButton(
              tooltip: AppStrings.songCreateAction,
              icon: const Icon(Icons.add),
              onPressed: () {
                unawaited(_createSong(context, ref));
              },
            ),
          ),
          PopupMenuButton<_SongListMenuAction>(
            key: const Key('song-list-overflow-menu'),
            onSelected: (action) {
              switch (action) {
                case _SongListMenuAction.import:
                  unawaited(
                    ref
                        .read(chordProImportControllerProvider.notifier)
                        .startImport(),
                  );
                case _SongListMenuAction.signOut:
                  unawaited(_signOut(context, ref));
              }
            },
            itemBuilder: (_) => [
              if (_canEditSongs(orgId))
                const PopupMenuItem(
                  key: Key('song-import-menu-item'),
                  value: _SongListMenuAction.import,
                  child: Text(AppStrings.songImportAction),
                ),
              const PopupMenuItem(
                value: _SongListMenuAction.signOut,
                child: Text(AppStrings.signOutAction),
              ),
            ],
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
                const ReauthBanner(),
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

                            final visibleSongs = browseRows
                                .map((row) => row.song)
                                .toList(growable: false);

                            if (visibleSongs.isEmpty) {
                              return const Center(
                                child: Text(
                                  AppStrings.songListNoResultsMessage,
                                ),
                              );
                            }

                            return ListView.separated(
                              key: const ValueKey('song-library-results-list'),
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

  // Gates the overflow-menu Import item, which cannot host an [IfCapability]
  // widget directly. By the time the menu opens, the visible capability-gated
  // icons (e.g. Add song) have already triggered editSongs resolution into the
  // resolver cache, so the synchronous lookup is populated. While the capability
  // is still unknown we hide the item (matching [IfCapability]'s hidden-until-
  // resolved behavior); only an unavailable resolver fails open, since the
  // backend remains the enforcement boundary.
  bool _canEditSongs(String? orgId) {
    if (orgId == null) return false;
    try {
      final resolver = ref.read(capabilityResolverProvider);
      return resolver.hasCapabilitySync(orgId, Capability.editSongs) ?? false;
    } catch (_) {
      return true;
    }
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
