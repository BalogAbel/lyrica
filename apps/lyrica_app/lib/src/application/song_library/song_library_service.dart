import 'package:lyrica_app/src/domain/song/song_repository.dart';
import 'package:lyrica_app/src/domain/song/song_source.dart';
import 'package:lyrica_app/src/domain/song/song_summary.dart';

class SongLibraryService {
  const SongLibraryService(this._repository);

  final SongRepository _repository;

  Future<List<SongSummary>> listSongs() {
    return _repository.listSongs();
  }

  Future<SongSource> getSongSource(String id) {
    return _repository.getSongSource(id);
  }
}
