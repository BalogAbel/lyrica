import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/presentation/planning/session_song_picker_state.dart';
import 'package:lyron_app/src/presentation/song_library/song_library_browse_row.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

class SessionSongPicker extends StatefulWidget {
  const SessionSongPicker({
    super.key,
    required this.eligibleSongs,
    required this.onPick,
    required this.onCancel,
    required this.compact,
    this.phase = SessionSongPickerPhase.ready,
  });

  final List<SongSummary> eligibleSongs;
  final ValueChanged<SongSummary> onPick;
  final VoidCallback onCancel;
  final bool compact;
  final SessionSongPickerPhase phase;

  @override
  State<SessionSongPicker> createState() => _SessionSongPickerState();
}

class _SessionSongPickerState extends State<SessionSongPicker> {
  late final TextEditingController _searchController;
  SessionSongPickerState _state = const SessionSongPickerState();

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredSongs = filterSongSummariesByQuery(
      widget.eligibleSongs,
      _state.query,
    );
    final content = _PickerContent(
      compact: widget.compact,
      phase: widget.phase,
      searchController: _searchController,
      query: _state.query,
      eligibleSongs: widget.eligibleSongs,
      filteredSongs: filteredSongs,
      onQueryChanged: (query) {
        setState(() {
          _state = _state.copyWith(query: query);
        });
      },
      onPick: widget.onPick,
      onCancel: widget.onCancel,
    );

    if (widget.compact) {
      return content.buildCompact(context);
    }

    return content.buildWide(context);
  }
}

class _PickerContent {
  const _PickerContent({
    required this.compact,
    required this.phase,
    required this.searchController,
    required this.query,
    required this.eligibleSongs,
    required this.filteredSongs,
    required this.onQueryChanged,
    required this.onPick,
    required this.onCancel,
  });

  final bool compact;
  final SessionSongPickerPhase phase;
  final TextEditingController searchController;
  final String query;
  final List<SongSummary> eligibleSongs;
  final List<SongSummary> filteredSongs;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<SongSummary> onPick;
  final VoidCallback onCancel;

  Widget buildCompact(BuildContext context) {
    return Scaffold(
      key: const ValueKey('session-song-picker-sheet'),
      appBar: AppBar(
        leading: BackButton(onPressed: onCancel),
        title: const Text(AppStrings.sessionItemSongPickerTitle),
      ),
      body: _Body(
        compact: true,
        phase: phase,
        searchController: searchController,
        query: query,
        eligibleSongs: eligibleSongs,
        filteredSongs: filteredSongs,
        onQueryChanged: onQueryChanged,
        onPick: onPick,
        onCancel: onCancel,
      ),
    );
  }

  Widget buildWide(BuildContext context) {
    return AlertDialog(
      title: const Text(AppStrings.sessionItemSongPickerTitle),
      content: SizedBox(
        width: 460,
        height: 380,
        child: _Body(
          compact: false,
          phase: phase,
          searchController: searchController,
          query: query,
          eligibleSongs: eligibleSongs,
          filteredSongs: filteredSongs,
          onQueryChanged: onQueryChanged,
          onPick: onPick,
          onCancel: onCancel,
        ),
      ),
      actions: [
        TextButton(
          onPressed: onCancel,
          child: const Text(AppStrings.songCancelAction),
        ),
      ],
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.compact,
    required this.phase,
    required this.searchController,
    required this.query,
    required this.eligibleSongs,
    required this.filteredSongs,
    required this.onQueryChanged,
    required this.onPick,
    required this.onCancel,
  });

  final bool compact;
  final SessionSongPickerPhase phase;
  final TextEditingController searchController;
  final String query;
  final List<SongSummary> eligibleSongs;
  final List<SongSummary> filteredSongs;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<SongSummary> onPick;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final hasEligibleSongs = eligibleSongs.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        key: const ValueKey('session-song-picker-body'),
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const ValueKey('session-song-picker-search-field'),
            controller: searchController,
            enabled: phase == SessionSongPickerPhase.ready,
            decoration: const InputDecoration(
              labelText: AppStrings.sessionItemSongPickerSearchLabel,
              hintText: AppStrings.sessionItemSongPickerSearchHint,
            ),
            onChanged: onQueryChanged,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: phase == SessionSongPickerPhase.loading
                ? const Center(
                    child: Text(AppStrings.sessionItemSongPickerLoadingMessage),
                  )
                : phase == SessionSongPickerPhase.unavailable
                ? const Center(
                    child: Text(
                      AppStrings.sessionItemSongPickerUnavailableMessage,
                    ),
                  )
                : phase == SessionSongPickerPhase.addInProgress
                ? const Center(
                    child: Text(
                      AppStrings.sessionItemSongPickerAddInProgressMessage,
                    ),
                  )
                : !hasEligibleSongs
                ? Center(
                    child: _StateCopy(
                      compact: compact,
                      text: AppStrings.sessionItemSongPickerEmptyMessage,
                    ),
                  )
                : filteredSongs.isEmpty
                ? Center(
                    child: _StateCopy(
                      compact: compact,
                      text: AppStrings.sessionItemSongPickerNoResultsMessage,
                    ),
                  )
                : ListView.separated(
                    itemCount: filteredSongs.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final song = filteredSongs[index];
                      return FocusableActionDetector(
                        enabled: phase == SessionSongPickerPhase.ready,
                        shortcuts: const {
                          SingleActivator(LogicalKeyboardKey.enter):
                              ActivateIntent(),
                          SingleActivator(LogicalKeyboardKey.space):
                              ActivateIntent(),
                        },
                        actions: {
                          ActivateIntent: CallbackAction<ActivateIntent>(
                            onInvoke: (intent) {
                              onPick(song);
                              return null;
                            },
                          ),
                        },
                        child: ListTile(
                          key: ValueKey('session-song-option-${song.id}'),
                          title: Text(song.title),
                          trailing: FilledButton(
                            onPressed: phase == SessionSongPickerPhase.ready
                                ? () => onPick(song)
                                : null,
                            child: const Text('Add'),
                          ),
                          onTap: phase == SessionSongPickerPhase.ready
                              ? () => onPick(song)
                              : null,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _StateCopy extends StatelessWidget {
  const _StateCopy({required this.compact, required this.text});

  final bool compact;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 0 : 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

Future<SongSummary?> showSessionSongPicker({
  required BuildContext context,
  required FutureOr<List<SongSummary>> eligibleSongs,
  Future<bool> Function(SongSummary song)? onPick,
}) {
  final compact = MediaQuery.sizeOf(context).width < 600;
  final resultCompleter = Completer<SongSummary?>();
  final route = _SessionSongPickerRoute(
    eligibleSongs: eligibleSongs,
    onPick: onPick,
    compact: compact,
    onComplete: (result) {
      if (!resultCompleter.isCompleted) {
        resultCompleter.complete(result);
      }
    },
  );
  if (compact) {
    unawaited(
      showModalBottomSheet<SongSummary>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        useRootNavigator: true,
        showDragHandle: false,
        builder: (_) => route,
      ).then((value) {
        if (value == null && !resultCompleter.isCompleted) {
          resultCompleter.complete(value);
        }
      }),
    );
    return resultCompleter.future;
  }

  unawaited(
    showDialog<SongSummary>(context: context, builder: (_) => route).then((
      value,
    ) {
      if (value == null && !resultCompleter.isCompleted) {
        resultCompleter.complete(value);
      }
    }),
  );
  return resultCompleter.future;
}

class _SessionSongPickerRoute extends StatefulWidget {
  const _SessionSongPickerRoute({
    required this.eligibleSongs,
    required this.onPick,
    required this.compact,
    required this.onComplete,
  });

  final FutureOr<List<SongSummary>> eligibleSongs;
  final Future<bool> Function(SongSummary song)? onPick;
  final bool compact;
  final ValueChanged<SongSummary?> onComplete;

  @override
  State<_SessionSongPickerRoute> createState() =>
      _SessionSongPickerRouteState();
}

class _SessionSongPickerRouteState extends State<_SessionSongPickerRoute> {
  SessionSongPickerPhase _phase = SessionSongPickerPhase.loading;
  List<SongSummary> _eligibleSongs = const [];

  @override
  void initState() {
    super.initState();
    _loadEligibleSongs();
  }

  Future<void> _loadEligibleSongs() async {
    final songs = widget.eligibleSongs;
    if (songs is List<SongSummary>) {
      setState(() {
        _eligibleSongs = _sortedSongs(songs);
        _phase = SessionSongPickerPhase.ready;
      });
      return;
    }

    try {
      final resolvedSongs = await songs;
      if (!mounted) {
        return;
      }
      setState(() {
        _eligibleSongs = _sortedSongs(resolvedSongs);
        _phase = SessionSongPickerPhase.ready;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _eligibleSongs = const [];
        _phase = SessionSongPickerPhase.unavailable;
      });
    }
  }

  List<SongSummary> _sortedSongs(List<SongSummary> songs) {
    final sortedSongs = [...songs];
    sortedSongs.sort((left, right) {
      final titleCompare = left.title.compareTo(right.title);
      if (titleCompare != 0) {
        return titleCompare;
      }
      return left.id.compareTo(right.id);
    });
    return sortedSongs;
  }

  Future<void> _handlePick(SongSummary song) async {
    if (_phase != SessionSongPickerPhase.ready) {
      return;
    }

    setState(() {
      _phase = SessionSongPickerPhase.addInProgress;
    });

    if (!widget.compact) {
      final callback = widget.onPick;
      if (callback != null) {
        unawaited(() async {
          try {
            final shouldClose = await Future.sync(() => callback(song));
            widget.onComplete(shouldClose ? song : null);
          } catch (error, stackTrace) {
            FlutterError.reportError(
              FlutterErrorDetails(exception: error, stack: stackTrace),
            );
            widget.onComplete(null);
          }
        }());
      } else {
        widget.onComplete(song);
      }
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(song);
      return;
    }

    try {
      final callback = widget.onPick;
      final shouldClose = callback == null ? true : await callback(song);
      if (!mounted) {
        return;
      }
      if (!shouldClose) {
        setState(() {
          _phase = SessionSongPickerPhase.ready;
        });
        return;
      }
      widget.onComplete(song);
      Navigator.of(context).pop(song);
    } catch (_) {
      if (mounted) {
        setState(() {
          _phase = SessionSongPickerPhase.ready;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = SessionSongPicker(
      compact: widget.compact,
      eligibleSongs: _eligibleSongs,
      onPick: _handlePick,
      onCancel: () {
        widget.onComplete(null);
        Navigator.of(context).pop();
      },
      phase: _phase,
    );

    if (widget.compact) {
      return SizedBox(
        height: MediaQuery.sizeOf(context).height,
        child: content,
      );
    }

    return content;
  }
}
