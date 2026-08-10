import 'package:flutter/material.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

/// Actions the song reader overflow menu can emit. The screen owning the menu
/// interprets each value and performs the corresponding side effect.
enum SongReaderOverflowAction {
  toggleViewMode,
  guitarView,
  pianoView,
  toggleTheme,
  edit,
  delete,
}

/// Overflow (⋮) menu for the song reader app bar.
///
/// Presents the view-mode toggle and instrument display switches
/// unconditionally, plus edit/delete entries when [canEditSongs] is true.
/// This widget does not read any providers — capability checks stay with the
/// screen, which decides what is available and passes that decision in.
class SongReaderOverflowMenu extends StatelessWidget {
  const SongReaderOverflowMenu({
    super.key,
    required this.viewMode,
    required this.canEditSongs,
    required this.isDarkActive,
    required this.onSelected,
  });

  final SongReaderViewMode viewMode;
  final bool canEditSongs;

  /// Whether the reader is currently rendering dark. Passed in rather than
  /// read from a provider: this widget stays provider-free, like the rest of
  /// the reader's leaf widgets.
  final bool isDarkActive;
  final void Function(SongReaderOverflowAction action) onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<SongReaderOverflowAction>(
      icon: const Icon(Icons.more_horiz),
      onSelected: onSelected,
      itemBuilder: (context) => [
        PopupMenuItem(
          value: SongReaderOverflowAction.toggleViewMode,
          child: Text(
            viewMode == SongReaderViewMode.chordsAndLyrics
                ? AppStrings.songReaderLyricsOnlyAction
                : AppStrings.songReaderChordsAndLyricsAction,
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: SongReaderOverflowAction.guitarView,
          child: Text(AppStrings.songReaderGuitarViewAction),
        ),
        PopupMenuItem(
          value: SongReaderOverflowAction.pianoView,
          child: Text(AppStrings.songReaderPianoViewAction),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: SongReaderOverflowAction.toggleTheme,
          child: Text(
            isDarkActive
                ? AppStrings.songReaderLightThemeAction
                : AppStrings.songReaderDarkThemeAction,
          ),
        ),
        if (canEditSongs) ...[
          const PopupMenuDivider(),
          PopupMenuItem(
            value: SongReaderOverflowAction.edit,
            child: Text(AppStrings.songEditAction),
          ),
          PopupMenuItem(
            value: SongReaderOverflowAction.delete,
            child: Text(AppStrings.songDeleteAction),
          ),
        ],
      ],
    );
  }
}
