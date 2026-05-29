import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/presentation/song_library/song_library_browse_state.dart';

class SongLibraryBrowseRow {
  const SongLibraryBrowseRow({required this.song});

  final SongSummary song;

  bool matchesQuery(String query) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return true;
    }

    return song.title.toLowerCase().contains(normalizedQuery);
  }
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
}) {
  return songs
      .map((song) => SongLibraryBrowseRow(song: song))
      .toList(growable: false);
}

List<SongLibraryBrowseRow> filterSongLibraryBrowseRows({
  required List<SongLibraryBrowseRow> rows,
  required String query,
  required SongLibraryBrowseSort sort,
}) {
  final normalizedQuery = query.trim().toLowerCase();
  final filteredRows = rows
      .where((row) {
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
