import 'package:flutter/material.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_overflow_menu.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

/// App bar for the song reader screen: back button, title with an optional
/// effective-key subtitle, a warning indicator for recoverable parse
/// diagnostics, and the overflow menu.
///
/// Owns the decision of whether to show the overflow menu and its
/// construction (`showOverflowMenu`/`viewMode`/`canEditSongs` are resolved
/// values, not providers) — the actual action handling stays with the screen
/// via [onOverflowAction], since it dispatches to `ref`-touching commands.
class SongReaderAppBar extends StatelessWidget implements PreferredSizeWidget {
  const SongReaderAppBar({
    super.key,
    required this.title,
    this.effectiveKey,
    required this.onBack,
    this.hasRecoverableWarnings = false,
    this.onShowWarnings,
    required this.showOverflowMenu,
    required this.viewMode,
    required this.canEditSongs,
    required this.isDarkActive,
    this.onOverflowAction,
  });

  final String title;
  final String? effectiveKey;
  final VoidCallback onBack;
  final bool hasRecoverableWarnings;
  final VoidCallback? onShowWarnings;
  final bool showOverflowMenu;
  final SongReaderViewMode viewMode;
  final bool canEditSongs;
  final bool isDarkActive;
  final void Function(SongReaderOverflowAction action)? onOverflowAction;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: false,
      leading: IconButton(
        tooltip: AppStrings.songReaderBackAction,
        onPressed: onBack,
        icon: const BackButtonIcon(),
      ),
      title: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title),
          if (effectiveKey != null)
            Builder(
              builder: (context) {
                final theme = Theme.of(context);
                return Text(
                  '${AppStrings.songReaderKeyLabelPrefix}$effectiveKey',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                );
              },
            ),
        ],
      ),
      actions: [
        if (hasRecoverableWarnings)
          IconButton(
            tooltip: AppStrings.songReaderWarningsSemantics,
            icon: const Icon(Icons.warning_amber_outlined),
            onPressed: onShowWarnings,
          ),
        if (showOverflowMenu)
          SongReaderOverflowMenu(
            viewMode: viewMode,
            canEditSongs: canEditSongs,
            isDarkActive: isDarkActive,
            onSelected: onOverflowAction!,
          ),
      ],
    );
  }
}
