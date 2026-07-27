import 'package:flutter/material.dart';
import 'package:lyron_app/src/application/song_library/catalog_snapshot_state.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_types.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

/// Whether a scoped reader's "song not found" error should render as the
/// deleted-song tombstone (title preserved, explicit deleted/conflict
/// messaging) rather than the generic "scoped context unavailable" message.
bool canShowScopedDeletedTombstone({
  required CatalogSnapshotState catalogState,
  required SongMutationRecord? mutationRecord,
}) {
  return mutationRecord?.isRemoteDeletedConflict == true ||
      catalogState.context != null;
}

/// Centered loading message shown while the catalog context or the song
/// itself is still resolving.
class SongReaderLoadingView extends StatelessWidget {
  const SongReaderLoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text(AppStrings.songReaderLoadingMessage));
  }
}

/// Centered message shown when a scoped reader's session/plan context could
/// not be resolved.
class SongReaderScopedUnavailableView extends StatelessWidget {
  const SongReaderScopedUnavailableView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        AppStrings.scopedReaderContextUnavailableMessage,
        textAlign: TextAlign.center,
      ),
    );
  }
}

/// Centered message shown when the backend denies access to the song.
class SongReaderAccessDeniedView extends StatelessWidget {
  const SongReaderAccessDeniedView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text(AppStrings.songReaderAccessDeniedMessage));
  }
}

/// Centered message shown when an unscoped reader's song cannot be found.
class SongReaderNotFoundView extends StatelessWidget {
  const SongReaderNotFoundView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text(AppStrings.songReaderUnavailableMessage));
  }
}

/// Centered failure message with a retry action, shown for any other
/// (non-access-denied, non-not-found) load failure.
class SongReaderLoadFailureView extends StatelessWidget {
  const SongReaderLoadFailureView({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
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
            onPressed: onRetry,
            child: const Text(AppStrings.retryAction),
          ),
        ],
      ),
    );
  }
}

/// Tombstone shown for a scoped reader whose song was deleted (locally or
/// remotely), preserving the last-known [title] and an explicit [message].
class SongReaderDeletedTombstoneView extends StatelessWidget {
  const SongReaderDeletedTombstoneView({
    super.key,
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            const Text(
              AppStrings.songReaderDeletedTitle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

/// Standalone scaffold shown when a scoped reader is opened directly and its
/// session-scoped context request itself failed outright (before the main
/// app bar/body shell would otherwise render).
class SongReaderScopedContextFailureScaffold extends StatelessWidget {
  const SongReaderScopedContextFailureScaffold({
    super.key,
    required this.onBack,
  });

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: AppStrings.songReaderBackAction,
          onPressed: onBack,
          icon: const BackButtonIcon(),
        ),
        title: const Text(AppStrings.songReaderTitle),
      ),
      body: const SafeArea(child: SongReaderScopedUnavailableView()),
    );
  }
}
