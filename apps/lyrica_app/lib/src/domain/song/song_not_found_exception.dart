class SongNotFoundException implements Exception {
  const SongNotFoundException(this.songId);

  final String songId;

  @override
  String toString() => 'SongNotFoundException(songId: $songId)';
}
