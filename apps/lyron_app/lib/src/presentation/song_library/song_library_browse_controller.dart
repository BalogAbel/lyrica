import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/presentation/song_library/song_library_browse_state.dart';

class SongLibraryBrowseController
    extends StateNotifier<SongLibraryBrowseState> {
  SongLibraryBrowseController() : super(const SongLibraryBrowseState());

  void setQuery(String query) {
    state = state.copyWith(query: query);
  }

  void setFilter(SongLibraryBrowseFilter filter) {
    state = state.copyWith(filter: filter);
  }

  void setSort(SongLibraryBrowseSort sort) {
    state = state.copyWith(sort: sort);
  }

  void reset() {
    state = const SongLibraryBrowseState();
  }
}
