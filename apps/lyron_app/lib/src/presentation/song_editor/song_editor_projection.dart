import 'package:lyron_app/src/presentation/song_editor/song_editor_state.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';

class SongEditorProjection {
  SongEditorProjection({required SongEditorState state})
    : state = state,
      summaryTitle = state.parsedSong.title.trim().isEmpty
          ? 'Untitled song'
          : state.parsedSong.title.trim(),
      summaryArtist = state.parsedSong.artist.trim().isEmpty
          ? 'Unknown artist'
          : state.parsedSong.artist.trim(),
      summaryKey = state.parsedSong.sourceKey?.trim().isEmpty ?? true
          ? '—'
          : state.parsedSong.sourceKey!.trim(),
      summaryTempo = state.parsedSong.tempoBpm == null
          ? '—'
          : '${state.parsedSong.tempoBpm} bpm',
      summaryTags = state.parsedSong.tags.isEmpty
          ? '—'
          : state.parsedSong.tags.join(', '),
      summaryTranspose = _formatSigned(state.parsedSong.baseTranspose),
      summaryCapo = '${state.parsedSong.baseCapo}',
      preview = SongReaderProjection(
        song: state.parsedSong.toReaderSong(),
        state: SongReaderState(),
      );

  final SongEditorState state;
  final String summaryTitle;
  final String summaryArtist;
  final String summaryKey;
  final String summaryTempo;
  final String summaryTags;
  final String summaryTranspose;
  final String summaryCapo;
  final SongReaderProjection preview;

  String get previewSubtitle {
    return '$summaryArtist · Key $summaryKey · Tempo $summaryTempo';
  }
}

String _formatSigned(int value) {
  return value > 0 ? '+$value' : '$value';
}
