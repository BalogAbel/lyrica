import 'package:flutter/foundation.dart';
import 'package:lyrica_app/src/domain/song/song_not_found_exception.dart';
import 'package:lyrica_app/src/domain/song/song_repository.dart';
import 'package:lyrica_app/src/domain/song/song_source.dart';
import 'package:lyrica_app/src/domain/song/song_summary.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef ListSongRows = Future<List<Map<String, dynamic>>> Function();
typedef GetSongRow = Future<Map<String, dynamic>?> Function(String id);

class SupabaseSongRepository implements SongRepository {
  SupabaseSongRepository(SupabaseClient client)
    : this.testing(
        listSongsRows: () async {
          final rows = await client
              .from('songs')
              .select('id, title')
              .order('title');
          return List<Map<String, dynamic>>.from(rows);
        },
        getSongRow: (id) async {
          final row = await client
              .from('songs')
              .select('id, chordpro_source')
              .eq('id', id)
              .maybeSingle();
          return row == null ? null : Map<String, dynamic>.from(row);
        },
      );

  @visibleForTesting
  SupabaseSongRepository.testing({
    required ListSongRows listSongsRows,
    required GetSongRow getSongRow,
  }) : _listSongsRows = listSongsRows,
       _getSongRow = getSongRow;

  final ListSongRows _listSongsRows;
  final GetSongRow _getSongRow;

  @override
  Future<List<SongSummary>> listSongs() async {
    final rows = await _listSongsRows();

    return rows
        .map(
          (row) => SongSummary(
            id: row['id'] as String,
            title: row['title'] as String,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<SongSource> getSongSource(String id) async {
    final row = await _getSongRow(id);
    if (row == null) {
      throw SongNotFoundException(id);
    }

    return SongSource(
      id: row['id'] as String,
      source: row['chordpro_source'] as String,
    );
  }
}
