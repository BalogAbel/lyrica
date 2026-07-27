import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_types.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_immersive_mode.dart';
import 'package:lyron_app/src/router/app_routes.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

/// Edit and delete actions for the song reader's overflow menu.
///
/// Owns the `ref.read`/`ref.invalidate` calls and dialog flows for editing
/// and deleting the current song. The screen supplies the pieces that are
/// tied to its own lifecycle: the [SongReaderImmersiveMode] instance plus the
/// control visibility captured before the async gap (for the edit push/pop
/// immersive dance), and a callback to run after a successful delete (which
/// needs the screen's routing/scoped-mode state to decide where "back" goes).
class SongReaderSongActions {
  const SongReaderSongActions({required this.songId});

  final String songId;

  Future<void> edit(
    BuildContext context,
    WidgetRef ref, {
    required SongReaderImmersiveMode immersiveMode,
    required bool wasImmersive,
  }) async {
    final activeContext = ref.read(activeCatalogContextProvider);
    if (activeContext == null) {
      return;
    }
    final songSummary = await ref
        .read(songLibraryServiceProvider)
        .getSongSummaryById(context: activeContext, songId: songId);
    if (!context.mounted) {
      return;
    }

    final songSlug = songSummary?.slug;
    if (songSlug == null || songSlug.isEmpty) {
      return;
    }

    // Capture control visibility before the async gap so we can restore the
    // immersive state on return. The editor is pushed (not replaced), so this
    // screen is not disposed and must restore the system UI itself.
    immersiveMode.apply(false);
    await context.push(
      AppRoutes.songEditor.path.replaceFirst(':songSlug', songSlug),
    );
    if (context.mounted) {
      immersiveMode.apply(wasImmersive);
    }
  }

  Future<void> delete(
    BuildContext context,
    WidgetRef ref, {
    required void Function(BuildContext context) onDeleted,
  }) async {
    final activeContext = ref.read(activeCatalogContextProvider);
    if (activeContext == null) {
      return;
    }

    try {
      await ref
          .read(songLibraryServiceProvider)
          .deleteSong(context: activeContext, songId: songId);
      ref.invalidate(songMutationEntriesProvider);
      ref.invalidate(songLibraryListProvider);
      if (context.mounted) {
        onDeleted(context);
      }
    } on SongDeleteBlockedException {
      if (!context.mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          content: const Text(AppStrings.songDeleteBlockedMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(AppStrings.songCancelAction),
            ),
          ],
        ),
      );
    } on SongConflictResolutionRequiredException {
      if (!context.mounted) {
        return;
      }
      await _showConflictResolutionRequiredDialog(context);
    }
  }

  Future<void> _showConflictResolutionRequiredDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AppStrings.songConflictTitle),
        content: const Text(AppStrings.songConflictMessage),
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
