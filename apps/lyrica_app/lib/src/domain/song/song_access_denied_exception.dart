class SongAccessDeniedException implements Exception {
  const SongAccessDeniedException(this.songId);

  final String songId;

  @override
  String toString() => 'SongAccessDeniedException(songId: $songId)';
}
