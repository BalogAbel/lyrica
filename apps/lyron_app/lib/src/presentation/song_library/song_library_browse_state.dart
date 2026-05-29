enum SongLibraryBrowseSort { titleAscending }

class SongLibraryBrowseState {
  const SongLibraryBrowseState({
    this.query = '',
    this.sort = SongLibraryBrowseSort.titleAscending,
  });

  final String query;
  final SongLibraryBrowseSort sort;

  SongLibraryBrowseState copyWith({
    String? query,
    SongLibraryBrowseSort? sort,
  }) {
    return SongLibraryBrowseState(
      query: query ?? this.query,
      sort: sort ?? this.sort,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SongLibraryBrowseState &&
        other.query == query &&
        other.sort == sort;
  }

  @override
  int get hashCode => Object.hash(query, sort);
}
