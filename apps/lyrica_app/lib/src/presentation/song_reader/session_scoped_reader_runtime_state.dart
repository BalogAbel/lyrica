import 'package:lyrica_app/src/presentation/song_reader/song_reader_state.dart';

class SessionScopedReaderRuntimeState {
  SessionScopedReaderRuntimeState({
    this.planId,
    this.sessionId,
    this.songId,
    SongReaderState? readerState,
  }) : readerState = readerState ?? SongReaderState();

  final String? planId;
  final String? sessionId;
  final String? songId;
  final SongReaderState readerState;

  SessionScopedReaderRuntimeState copyWith({
    String? planId,
    String? sessionId,
    String? songId,
    SongReaderState? readerState,
  }) {
    return SessionScopedReaderRuntimeState(
      planId: planId ?? this.planId,
      sessionId: sessionId ?? this.sessionId,
      songId: songId ?? this.songId,
      readerState: readerState ?? this.readerState,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SessionScopedReaderRuntimeState &&
        other.planId == planId &&
        other.sessionId == sessionId &&
        other.songId == songId &&
        other.readerState == readerState;
  }

  @override
  int get hashCode => Object.hash(planId, sessionId, songId, readerState);
}
