import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

  test('browse state starts with title sort', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      container.read(songLibraryBrowseControllerProvider),
      const SongLibraryBrowseState(
        query: '',
        sort: SongLibraryBrowseSort.titleAscending,
      ),
    );
  });

  test('browse sort can reset', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final controller = container.read(
      songLibraryBrowseControllerProvider.notifier,
    );
    controller
      ..setQuery('grace')
      ..setSort(SongLibraryBrowseSort.titleAscending);

    expect(
      container.read(songLibraryBrowseControllerProvider),
      const SongLibraryBrowseState(
        query: 'grace',
        sort: SongLibraryBrowseSort.titleAscending,
      ),
    );

    controller.reset();

    expect(
      container.read(songLibraryBrowseControllerProvider),
      const SongLibraryBrowseState(
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

  test('filterSongLibraryBrowseRows returns all rows sorted by title', () {
    const rows = [
      SongLibraryBrowseRow(
        song: SongSummary(id: 'song-2', slug: 'beta', title: 'Beta'),
      ),
      SongLibraryBrowseRow(
        song: SongSummary(id: 'song-1', slug: 'alpha', title: 'Alpha'),
      ),
      SongLibraryBrowseRow(
        song: SongSummary(id: 'song-3', slug: 'gamma', title: 'Gamma'),
      ),
    ];

    final result = filterSongLibraryBrowseRows(
      rows: rows,
      query: '',
      sort: SongLibraryBrowseSort.titleAscending,
    );

    expect(result, hasLength(3));
    expect(
      result.map((r) => r.song.title),
      containsAllInOrder(['Alpha', 'Beta', 'Gamma']),
    );
  });

  test('filterSongLibraryBrowseRows filters by query', () {
    const rows = [
      SongLibraryBrowseRow(
        song: SongSummary(id: 'song-1', slug: 'amazing-grace', title: 'Amazing Grace'),
      ),
      SongLibraryBrowseRow(
        song: SongSummary(id: 'song-2', slug: 'great-faith', title: 'Great Is Thy Faithfulness'),
      ),
    ];

    final result = filterSongLibraryBrowseRows(
      rows: rows,
      query: 'grace',
      sort: SongLibraryBrowseSort.titleAscending,
    );

    expect(result, hasLength(1));
    expect(result.single.song.title, 'Amazing Grace');
  });
}
