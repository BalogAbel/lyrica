import 'package:flutter/material.dart';
import 'package:lyron_app/src/app/reader_theme.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_chrome_metrics.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_overflow_menu.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

/// The reader's floating top bar (spec section 6, "Chrome"). Hidden by
/// default, revealed by tapping the content, and drawn as a `Positioned`
/// overlay in `SongReaderCompactSurface`'s `Stack` -- excluded from the fit
/// calculation's available height the same way the control rail is. See
/// that widget's `Stack` comment for why that exclusion is structural.
///
/// Contents, leading to trailing: back, the song title, the
/// recoverable-warnings indicator, and the overflow menu.
///
/// **Back uses the standard back symbol (`BackButtonIcon`), never a "Back"
/// text label.** This follows Apple's HIG *Toolbars*, which places the
/// control that returns to the previous view at the leading edge of the top
/// toolbar and requires the standard symbol there -- see spec "Platform
/// conformance". A back control in the bottom bar was rejected for the same
/// reason; do not move it there.
///
/// **The title is deliberately duplicated with the bottom bar's own title.**
/// An empty title area here was rejected by the product owner (spec section
/// 6). Do not "fix" this by removing it.
///
/// Floats over scrolling lyric content, so unlike the always-visible bottom
/// bar (which sits below the content in the `Column` and inherits the
/// ambient surface) it needs its own background to stay legible in both
/// themes -- taken from [ReaderTheme.floatingChromeBackground], never
/// hardcoded (ADR-033).
class SongReaderTopBar extends StatelessWidget {
  const SongReaderTopBar({
    super.key,
    required this.title,
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
  final VoidCallback onBack;
  final bool hasRecoverableWarnings;
  final VoidCallback? onShowWarnings;
  final bool showOverflowMenu;
  final SongReaderViewMode viewMode;
  final bool canEditSongs;
  final bool isDarkActive;
  final void Function(SongReaderOverflowAction action)? onOverflowAction;

  @override
  Widget build(BuildContext context) {
    final readerTheme = ReaderTheme.of(context);
    final textTheme = Theme.of(context).textTheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Resolved off the bar's OWN width, matching how
        // SongReaderBottomBar and SongReaderChromeMetrics.resolve are used
        // elsewhere -- the bar can be narrower than the full viewport (e.g.
        // the expanded shell never builds this widget, but a defensive
        // resolve here still keys off available width rather than a second
        // MediaQuery read).
        final chromeMetrics = SongReaderChromeMetrics.resolve(
          constraints.maxWidth,
        );
        // This bar floats over the content and sits at the very top of the
        // screen (there is no ancestor `SafeArea` -- see
        // `song_reader_shell.dart`), so it consumes the top safe-area inset
        // itself, the same way `SongReaderBottomBar` consumes the bottom
        // one: total height is the bar height plus the inset, with the
        // inset riding above the bar's own content rather than pushing it
        // down. `viewPaddingOf`, not `paddingOf` -- the reader has no text
        // input, so this must not react to a keyboard.
        //
        // It also runs edge to edge (no ancestor offsets it -- the compact
        // surface's `Positioned` for this bar is `left: 0, right: 0`), so a
        // landscape notch on either side would otherwise sit directly on top
        // of the leading back button or the trailing overflow menu. Consuming
        // the left/right insets here, the same way the control rail's
        // caller adds `viewPaddingOf(context).right` to its edge offset
        // (`song_reader_compact_surface.dart`), keeps both controls clear of
        // it.
        final viewPadding = MediaQuery.viewPaddingOf(context);
        return Material(
          key: const Key('song-reader-top-bar-surface'),
          color: readerTheme.floatingChromeBackground,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              viewPadding.left,
              viewPadding.top,
              viewPadding.right,
              0,
            ),
            child: SizedBox(
              height: chromeMetrics.topBarHeight,
              child: Row(
                children: [
                  IconButton(
                    tooltip: AppStrings.songReaderBackAction,
                    onPressed: onBack,
                    icon: const BackButtonIcon(),
                  ),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleMedium,
                    ),
                  ),
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
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
