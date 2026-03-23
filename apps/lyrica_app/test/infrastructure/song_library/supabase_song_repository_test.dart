import 'package:flutter_test/flutter_test.dart';
import 'package:lyrica_app/src/domain/song/song_not_found_exception.dart';
import 'package:lyrica_app/src/domain/song/song_summary.dart';
import 'package:lyrica_app/src/infrastructure/song_library/supabase_song_repository.dart';

void main() {
  test('lists minimal song summaries from the backend rows', () async {
    final repository = SupabaseSongRepository.testing(
      listSongsRows: () async => [
        {'id': 'song-1', 'title': 'A forrásnál'},
        {'id': 'song-2', 'title': 'A mi Istenünk (Leborulok előtted)'},
        {'id': 'song-3', 'title': 'Egy út'},
      ],
      getSongRow: (id) async => {
        'id': id,
        'chordpro_source': '{title:Egy út}\n',
      },
    );

    final songs = await repository.listSongs();

    expect(songs, hasLength(3));
    expect(songs.first, const SongSummary(id: 'song-1', title: 'A forrásnál'));
  });

  test('returns raw chordpro source for a song id', () async {
    final repository = SupabaseSongRepository.testing(
      listSongsRows: () async => const [],
      getSongRow: (id) async => {
        'id': id,
        'chordpro_source': '{title:Egy út}\n{key:B}',
      },
    );

    final source = await repository.getSongSource('song-3');

    expect(source.id, 'song-3');
    expect(source.source, contains('{title:'));
  });

  test('maps a missing song row to SongNotFoundException', () async {
    final repository = SupabaseSongRepository.testing(
      listSongsRows: () async => const [],
      getSongRow: (id) async => null,
    );

    expect(
      () => repository.getSongSource('missing'),
      throwsA(isA<SongNotFoundException>()),
    );
  });
}
