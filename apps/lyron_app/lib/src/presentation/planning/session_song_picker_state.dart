enum SessionSongPickerPhase { loading, unavailable, ready, addInProgress }

class SessionSongPickerState {
  const SessionSongPickerState({
    this.query = '',
    this.phase = SessionSongPickerPhase.ready,
  });

  final String query;
  final SessionSongPickerPhase phase;

  SessionSongPickerState copyWith({
    String? query,
    SessionSongPickerPhase? phase,
  }) {
    return SessionSongPickerState(
      query: query ?? this.query,
      phase: phase ?? this.phase,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SessionSongPickerState &&
        other.query == query &&
        other.phase == phase;
  }

  @override
  int get hashCode => Object.hash(query, phase);
}
