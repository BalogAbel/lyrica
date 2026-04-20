import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_types.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/presentation/song_library/song_library_browse_state.dart';

void main() {
  test(
    'browse rows join mutations and filter by current browse state',
    () async {
      final container = ProviderContainer(
        overrides: [
          songLibraryListProvider.overrideWith(
            (ref) async => const [
              SongSummary(id: 'song-1', slug: 'alpha', title: 'Alpha'),
              SongSummary(id: 'song-2', slug: 'beta', title: 'Beta'),
              SongSummary(id: 'song-3', slug: 'gamma', title: 'Gamma'),
            ],
          ),
          songMutationEntriesProvider.overrideWith(
            (ref) async => const [
              SongMutationRecord(
                id: 'song-2',
                organizationId: 'org-1',
                slug: 'beta',
                title: 'Beta',
                chordproSource: '{title: Beta}',
                version: 2,
                baseVersion: 1,
                syncStatus: SongSyncStatus.pendingUpdate,
              ),
              SongMutationRecord(
                id: 'song-3',
                organizationId: 'org-1',
                slug: 'gamma',
                title: 'Gamma',
                chordproSource: '{title: Gamma}',
                version: 3,
                baseVersion: 2,
                syncStatus: SongSyncStatus.conflict,
              ),
            ],
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(songLibraryListProvider.future);
      await container.read(songMutationEntriesProvider.future);

      expect(
        container
            .read(songLibraryBrowseRowsProvider)
            .map((row) => row.song.title),
        ['Alpha', 'Beta', 'Gamma'],
      );

      container
          .read(songLibraryBrowseControllerProvider.notifier)
          .setQuery('mm');
      expect(
        container
            .read(songLibraryBrowseRowsProvider)
            .map((row) => row.song.title),
        ['Gamma'],
      );

      container.read(songLibraryBrowseControllerProvider.notifier).setQuery('');
      container
          .read(songLibraryBrowseControllerProvider.notifier)
          .setFilter(SongLibraryBrowseFilter.pendingSync);

      final pendingRows = container.read(songLibraryBrowseRowsProvider);
      expect(pendingRows.map((row) => row.song.title), ['Beta']);

      container
          .read(songLibraryBrowseControllerProvider.notifier)
          .setFilter(SongLibraryBrowseFilter.conflicts);
      expect(
        container
            .read(songLibraryBrowseRowsProvider)
            .map((row) => row.song.title),
        ['Gamma'],
      );
    },
  );
}
