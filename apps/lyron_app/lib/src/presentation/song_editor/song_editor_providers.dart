import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/application/provider_retry_policy.dart';
import 'package:lyron_app/src/application/providers.dart';

final class SongEditorRouteData {
  const SongEditorRouteData({
    required this.songId,
    required this.songSlug,
    required this.source,
  });

  final String songId;
  final String songSlug;
  final String source;
}

final songEditorSourceProvider = FutureProvider.autoDispose
    .family<String, String>((ref, songId) async {
      final context = ref.watch(activeCatalogContextProvider);
      if (context == null) {
        throw StateError(
          'Song editor source requested without an active catalog context.',
        );
      }

      final service = ref.watch(songLibraryServiceProvider);
      final source = await service.getSongSource(
        context: context,
        songId: songId,
      );
      return source.source;
    }, retry: noAutomaticProviderRetry);

final songEditorRouteDataProvider = FutureProvider.autoDispose
    .family<SongEditorRouteData?, String>((ref, songSlug) async {
      final context = ref.watch(activeCatalogContextProvider);
      if (context == null) {
        return null;
      }

      final service = ref.watch(songLibraryServiceProvider);
      final song = await service.getSongSummaryBySlug(
        context: context,
        songSlug: songSlug,
      );
      if (song == null) {
        return null;
      }

      final source = await service.getSongSource(
        context: context,
        songId: song.id,
      );
      return SongEditorRouteData(
        songId: song.id,
        songSlug: songSlug,
        source: source.source,
      );
    }, retry: noAutomaticProviderRetry);
