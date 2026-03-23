import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lyrica_app/src/presentation/song_library/song_library_providers.dart';
import 'package:lyrica_app/src/shared/app_strings.dart';

class SongListScreen extends ConsumerWidget {
  const SongListScreen({super.key});

  static const _contentWidth = 720.0;
  static const _horizontalPadding = 24.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songsAsync = ref.watch(songLibraryListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.appName)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _contentWidth),
            child: songsAsync.when(
              loading: () =>
                  const Center(child: Text(AppStrings.songListLoadingMessage)),
              error: (error, stackTrace) => _RetryableErrorState(
                message: AppStrings.songListLoadFailureMessage,
                onRetry: () => ref.invalidate(songLibraryListProvider),
              ),
              data: (songs) {
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
                      onTap: () => context.go('/songs/${song.id}'),
                    );
                  },
                );
              },
            ),
          ),
        ),
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
