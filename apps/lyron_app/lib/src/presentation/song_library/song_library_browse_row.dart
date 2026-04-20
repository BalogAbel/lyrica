import 'package:lyron_app/src/application/song_library/song_mutation_sync_types.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/presentation/song_library/song_library_browse_state.dart';

class SongLibraryBrowseRow {
  const SongLibraryBrowseRow({required this.song, this.mutationRecord});

  final SongSummary song;
  final SongMutationRecord? mutationRecord;

  bool matchesQuery(String query) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return true;
    }

    return song.title.toLowerCase().contains(normalizedQuery);
  }

  bool matchesFilter(SongLibraryBrowseFilter filter) {
    return switch (filter) {
      SongLibraryBrowseFilter.all => true,
      SongLibraryBrowseFilter.pendingSync =>
        mutationRecord != null &&
            _pendingStatuses.contains(mutationRecord!.syncStatus),
      SongLibraryBrowseFilter.conflicts =>
        mutationRecord?.syncStatus == SongSyncStatus.conflict,
    };
  }

  static const _pendingStatuses = {
    SongSyncStatus.pendingCreate,
    SongSyncStatus.pendingUpdate,
    SongSyncStatus.pendingDelete,
  };
}

List<SongSummary> filterSongSummariesByQuery(
  List<SongSummary> songs,
  String query,
) {
  final normalizedQuery = query.trim().toLowerCase();
  if (normalizedQuery.isEmpty) {
    return songs;
  }

  return songs
      .where((song) => song.title.toLowerCase().contains(normalizedQuery))
      .toList(growable: false);
}

List<SongLibraryBrowseRow> buildSongLibraryBrowseRows({
  required List<SongSummary> songs,
  required List<SongMutationRecord> mutationEntries,
}) {
  final mutationBySongId = <String, SongMutationRecord>{
    for (final mutation in mutationEntries) mutation.id: mutation,
  };

  return songs
      .map(
        (song) => SongLibraryBrowseRow(
          song: song,
          mutationRecord: mutationBySongId[song.id],
        ),
      )
      .toList(growable: false);
}

List<SongLibraryBrowseRow> filterSongLibraryBrowseRows({
  required List<SongLibraryBrowseRow> rows,
  required String query,
  required SongLibraryBrowseFilter filter,
  required SongLibraryBrowseSort sort,
}) {
  final normalizedQuery = query.trim().toLowerCase();
  final filteredRows = rows
      .where((row) {
        if (!row.matchesFilter(filter)) {
          return false;
        }

        if (normalizedQuery.isEmpty) {
          return true;
        }

        return row.song.title.toLowerCase().contains(normalizedQuery);
      })
      .toList(growable: false);

  return switch (sort) {
    SongLibraryBrowseSort.titleAscending => [
      ...filteredRows..sort((left, right) {
        final titleCompare = left.song.title.compareTo(right.song.title);
        if (titleCompare != 0) {
          return titleCompare;
        }
        return left.song.id.compareTo(right.song.id);
      }),
    ],
  };
}
