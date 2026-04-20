import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_types.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/presentation/song_library/song_library_browse_row.dart';
import 'package:lyron_app/src/presentation/song_library/song_library_browse_state.dart';
import 'package:lyron_app/src/presentation/song_library/song_library_providers.dart';

void main() {
  test('browse query starts empty and can reset to empty', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      container.read(songLibraryBrowseControllerProvider),
      const SongLibraryBrowseState(),
    );

    container
        .read(songLibraryBrowseControllerProvider.notifier)
        .setQuery('grace');
    expect(
      container.read(songLibraryBrowseControllerProvider),
      const SongLibraryBrowseState(query: 'grace'),
    );

    container.read(songLibraryBrowseControllerProvider.notifier).reset();
    expect(
      container.read(songLibraryBrowseControllerProvider),
      const SongLibraryBrowseState(),
    );
  });

  test('browse state starts on all songs with title sort', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      container.read(songLibraryBrowseControllerProvider),
      const SongLibraryBrowseState(
        query: '',
        filter: SongLibraryBrowseFilter.all,
        sort: SongLibraryBrowseSort.titleAscending,
      ),
    );
  });

  test('browse filter and sort can reset together', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final controller = container.read(
      songLibraryBrowseControllerProvider.notifier,
    );
    controller
      ..setQuery('grace')
      ..setFilter(SongLibraryBrowseFilter.pendingSync)
      ..setSort(SongLibraryBrowseSort.titleAscending);

    expect(
      container.read(songLibraryBrowseControllerProvider),
      const SongLibraryBrowseState(
        query: 'grace',
        filter: SongLibraryBrowseFilter.pendingSync,
        sort: SongLibraryBrowseSort.titleAscending,
      ),
    );

    controller.reset();

    expect(
      container.read(songLibraryBrowseControllerProvider),
      const SongLibraryBrowseState(
        filter: SongLibraryBrowseFilter.all,
        sort: SongLibraryBrowseSort.titleAscending,
      ),
    );
  });

  test('browse query survives unrelated provider recomputation', () {
    final rebuildTickProvider = StateProvider<int>((ref) => 0);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final derivedProvider = Provider<String>((ref) {
      ref.watch(rebuildTickProvider);
      return ref.watch(songLibraryBrowseControllerProvider).query;
    });

    expect(container.read(derivedProvider), isEmpty);

    container
        .read(songLibraryBrowseControllerProvider.notifier)
        .setQuery('grace');
    expect(container.read(derivedProvider), 'grace');

    container.read(rebuildTickProvider.notifier).state = 1;
    expect(container.read(derivedProvider), 'grace');
  });

  test('title filter ignores case and surrounding whitespace', () {
    const songs = [
      SongSummary(id: 'song-1', slug: 'amazing-grace', title: 'Amazing Grace'),
      SongSummary(
        id: 'song-2',
        slug: 'great-is-thy-faithfulness',
        title: 'Great Is Thy Faithfulness',
      ),
    ];

    final matches = filterSongSummariesByQuery(songs, '  GRACE  ');

    expect(matches, hasLength(1));
    expect(matches.single.title, 'Amazing Grace');
  });

  test('title filter yields no matches when query misses every title', () {
    const songs = [
      SongSummary(id: 'song-1', slug: 'amazing-grace', title: 'Amazing Grace'),
    ];

    final matches = filterSongSummariesByQuery(songs, 'zzz');

    expect(matches, isEmpty);
  });

  test('browse row filter keeps conflict rows under conflicts', () {
    const rows = [
      SongLibraryBrowseRow(
        song: SongSummary(id: 'song-1', slug: 'alpha', title: 'Alpha'),
      ),
      SongLibraryBrowseRow(
        song: SongSummary(id: 'song-2', slug: 'beta', title: 'Beta'),
        mutationRecord: SongMutationRecord(
          id: 'song-2',
          organizationId: 'org-1',
          slug: 'beta',
          title: 'Beta',
          chordproSource: '{title: Beta}',
          version: 2,
          baseVersion: 1,
          syncStatus: SongSyncStatus.pendingUpdate,
        ),
      ),
      SongLibraryBrowseRow(
        song: SongSummary(id: 'song-3', slug: 'gamma', title: 'Gamma'),
        mutationRecord: SongMutationRecord(
          id: 'song-3',
          organizationId: 'org-1',
          slug: 'gamma',
          title: 'Gamma',
          chordproSource: '{title: Gamma}',
          version: 3,
          baseVersion: 2,
          syncStatus: SongSyncStatus.conflict,
        ),
      ),
    ];

    final matches = filterSongLibraryBrowseRows(
      rows: rows,
      query: '',
      filter: SongLibraryBrowseFilter.conflicts,
      sort: SongLibraryBrowseSort.titleAscending,
    );

    expect(matches, hasLength(1));
    expect(matches.single.song.title, 'Gamma');
  });

  test(
    'browse row filter keeps every pending sync state under pending sync',
    () {
      const rows = [
        SongLibraryBrowseRow(
          song: SongSummary(id: 'song-1', slug: 'alpha', title: 'Alpha'),
        ),
        SongLibraryBrowseRow(
          song: SongSummary(id: 'song-2', slug: 'beta', title: 'Beta'),
          mutationRecord: SongMutationRecord(
            id: 'song-2',
            organizationId: 'org-1',
            slug: 'beta',
            title: 'Beta',
            chordproSource: '{title: Beta}',
            version: 2,
            baseVersion: null,
            syncStatus: SongSyncStatus.pendingCreate,
          ),
        ),
        SongLibraryBrowseRow(
          song: SongSummary(id: 'song-3', slug: 'gamma', title: 'Gamma'),
          mutationRecord: SongMutationRecord(
            id: 'song-3',
            organizationId: 'org-1',
            slug: 'gamma',
            title: 'Gamma',
            chordproSource: '{title: Gamma}',
            version: 3,
            baseVersion: 2,
            syncStatus: SongSyncStatus.pendingUpdate,
          ),
        ),
        SongLibraryBrowseRow(
          song: SongSummary(id: 'song-4', slug: 'delta', title: 'Delta'),
          mutationRecord: SongMutationRecord(
            id: 'song-4',
            organizationId: 'org-1',
            slug: 'delta',
            title: 'Delta',
            chordproSource: '{title: Delta}',
            version: 4,
            baseVersion: 3,
            syncStatus: SongSyncStatus.pendingDelete,
          ),
        ),
        SongLibraryBrowseRow(
          song: SongSummary(id: 'song-5', slug: 'epsilon', title: 'Epsilon'),
          mutationRecord: SongMutationRecord(
            id: 'song-5',
            organizationId: 'org-1',
            slug: 'epsilon',
            title: 'Epsilon',
            chordproSource: '{title: Epsilon}',
            version: 5,
            baseVersion: 4,
            syncStatus: SongSyncStatus.conflict,
          ),
        ),
      ];

      final matches = filterSongLibraryBrowseRows(
        rows: rows,
        query: '',
        filter: SongLibraryBrowseFilter.pendingSync,
        sort: SongLibraryBrowseSort.titleAscending,
      );

      expect(matches, hasLength(3));
      expect(
        matches.map((row) => row.song.title),
        containsAllInOrder(['Beta', 'Delta', 'Gamma']),
      );
    },
  );
}
