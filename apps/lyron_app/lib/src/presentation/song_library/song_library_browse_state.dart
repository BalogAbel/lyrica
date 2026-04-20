enum SongLibraryBrowseFilter {
  all,
  pendingSync,
  conflicts,
}

enum SongLibraryBrowseSort {
  titleAscending,
}

class SongLibraryBrowseState {
  const SongLibraryBrowseState({
    this.query = '',
    this.filter = SongLibraryBrowseFilter.all,
    this.sort = SongLibraryBrowseSort.titleAscending,
  });

  final String query;
  final SongLibraryBrowseFilter filter;
  final SongLibraryBrowseSort sort;

  SongLibraryBrowseState copyWith({
    String? query,
    SongLibraryBrowseFilter? filter,
    SongLibraryBrowseSort? sort,
  }) {
    return SongLibraryBrowseState(
      query: query ?? this.query,
      filter: filter ?? this.filter,
      sort: sort ?? this.sort,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SongLibraryBrowseState &&
        other.query == query &&
        other.filter == filter &&
        other.sort == sort;
  }

  @override
  int get hashCode => Object.hash(query, filter, sort);
}
