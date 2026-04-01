import 'package:flutter/services.dart';
import 'package:lyron_app/src/domain/song/song_not_found_exception.dart';
import 'package:lyron_app/src/domain/song/song_repository.dart';
import 'package:lyron_app/src/domain/song/song_source.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';

class AssetSongRepository implements SongRepository {
  AssetSongRepository({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;

  static const _songs = <_AssetSong>[
    _AssetSong(
      id: 'a_forrasnal',
      title: 'A forrásnál',
      assetPath: 'assets/songs/a_forrasnal.pro',
    ),
    _AssetSong(
      id: 'a_mi_istenunk',
      title: 'A mi Istenünk (Leborulok előtted)',
      assetPath: 'assets/songs/a_mi_istenunk.pro',
    ),
    _AssetSong(
      id: 'egy_ut',
      title: 'Egy út',
      assetPath: 'assets/songs/egy_ut.pro',
    ),
  ];

  @override
  Future<List<SongSummary>> listSongs() async {
    return _songs
        .map((song) => SongSummary(id: song.id, title: song.title))
        .toList(growable: false);
  }

  @override
  Future<SongSource> getSongSource(String id) async {
    final song = _songById(id);
    final source = await _bundle.loadString(song.assetPath);

    return SongSource(id: song.id, source: source);
  }

  _AssetSong _songById(String id) {
    for (final song in _songs) {
      if (song.id == id) {
        return song;
      }
    }

    throw SongNotFoundException(id);
  }
}

class _AssetSong {
  const _AssetSong({
    required this.id,
    required this.title,
    required this.assetPath,
  });

  final String id;
  final String title;
  final String assetPath;
}
