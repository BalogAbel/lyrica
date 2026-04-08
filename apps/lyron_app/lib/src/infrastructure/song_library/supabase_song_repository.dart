import 'package:flutter/foundation.dart';
import 'package:lyron_app/src/domain/song/song_access_denied_exception.dart';
import 'package:lyron_app/src/domain/song/song_not_found_exception.dart';
import 'package:lyron_app/src/domain/song/song_repository.dart';
import 'package:lyron_app/src/domain/song/song_source.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef ListSongRows = Future<List<Map<String, dynamic>>> Function();
typedef GetSongRow = Future<Map<String, dynamic>?> Function(String id);
typedef GetSongSummaryBySlugRow =
    Future<Map<String, dynamic>?> Function(String songSlug);

class SupabaseSongRepository implements SongRepository {
  SupabaseSongRepository(SupabaseClient client)
    : this.testing(
        listSongsRows: () async {
          final rows = await client
              .from('songs')
              .select('id, slug, title, version')
              .order('title');
          return List<Map<String, dynamic>>.from(rows);
        },
        getSongRow: (id) async {
          final row = await client
              .from('songs')
              .select('id, slug, chordpro_source')
              .eq('id', id)
              .maybeSingle();
          return row == null ? null : Map<String, dynamic>.from(row);
        },
        getSongSummaryBySlugRow: (songSlug) async {
          final row = await client
              .from('songs')
              .select('id, slug, title, version')
              .eq('slug', songSlug)
              .maybeSingle();
          return row == null ? null : Map<String, dynamic>.from(row);
        },
      );

  @visibleForTesting
  SupabaseSongRepository.testing({
    required ListSongRows listSongsRows,
    required GetSongRow getSongRow,
    GetSongSummaryBySlugRow? getSongSummaryBySlugRow,
  }) : _listSongsRows = listSongsRows,
       _getSongRow = getSongRow,
       _getSongSummaryBySlugRow =
           getSongSummaryBySlugRow ??
           ((songSlug) async {
             final rows = await listSongsRows();
             for (final row in rows) {
               if (row['slug'] == songSlug) {
                 return row;
               }
             }
             return null;
           });

  final ListSongRows _listSongsRows;
  final GetSongRow _getSongRow;
  final GetSongSummaryBySlugRow _getSongSummaryBySlugRow;

  @override
  Future<List<SongSummary>> listSongs() async {
    final rows = await _listSongsRows();

    return rows
        .map(
          (row) => SongSummary(
            id: row['id'] as String,
            slug: row['slug'] as String? ?? row['id'] as String,
            title: row['title'] as String,
            version: (row['version'] as num?)?.toInt() ?? 1,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<SongSource> getSongSource(String id) async {
    final row = await _getSongRowOrThrow(id);
    if (row == null) {
      throw SongNotFoundException(id);
    }

    return SongSource(
      id: row['id'] as String,
      source: row['chordpro_source'] as String,
    );
  }

  Future<SongSummary?> getSongSummaryBySlug(String songSlug) async {
    final row = await _getSongSummaryBySlugRow(songSlug);
    if (row == null) {
      return null;
    }

    return SongSummary(
      id: row['id'] as String,
      slug: row['slug'] as String? ?? row['id'] as String,
      title: row['title'] as String,
      version: (row['version'] as num?)?.toInt() ?? 1,
    );
  }

  Future<Map<String, dynamic>?> _getSongRowOrThrow(String id) async {
    try {
      return await _getSongRow(id);
    } on PostgrestException catch (error) {
      if (_isAccessDeniedPostgrest(error)) {
        throw SongAccessDeniedException(id);
      }
      rethrow;
    } catch (error) {
      if (error.runtimeType.toString().contains('AccessDenied')) {
        throw SongAccessDeniedException(id);
      }
      rethrow;
    }
  }

  bool _isAccessDeniedPostgrest(PostgrestException error) {
    return error.code == '42501' ||
        error.code == '403' ||
        error.message.toLowerCase().contains('permission denied');
  }
}
