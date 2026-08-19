import 'package:flutter/material.dart';
import 'package:lyron_app/src/app/reader_theme.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_chrome_metrics.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

/// The reader's always-visible bottom bar (spec section 6). Occupies layout
/// space in the compact shell's `Column` at all times — unlike the top bar
/// and control rail, it is never hidden.
///
/// Three content modes, chosen from [isPlanScoped] and the bar's own width
/// (never a bare `600` — always [readerRegularTypeScaleMinWidth]):
///
/// - **Plan-scoped, tablet** (width >= [readerRegularTypeScaleMinWidth]):
///   previous item (chevron + title) | current title/key/capo/position |
///   next item (title + chevron).
/// - **Catalogue** (`isPlanScoped: false`): current title/key/capo, centred.
///   No chevrons, no neighbour placeholders.
/// - **Plan-scoped, phone**: chevrons only, no neighbour titles. Current
///   title/key/capo/position stay centred.
///
/// This widget sizes itself: `SongReaderChromeMetrics.bottomBarHeight`
/// (64 tablet / 58 phone) plus the bottom safe-area inset it reads from
/// `MediaQuery.viewPaddingOf`. The metrics constant deliberately carries the
/// bar height ONLY, so it stays testable without a fake `MediaQuery`; the
/// inset is added here, where the `MediaQuery` actually is. Callers must not
/// wrap this in a `SizedBox` of their own — doing so reintroduces the
/// mismatch on a notched phone that this arrangement exists to prevent.
class SongReaderBottomBar extends StatelessWidget {
  const SongReaderBottomBar({
    super.key,
    required this.currentTitle,
    this.keyLabel,
    this.capoLabel,
    this.position,
    this.itemCount,
    this.isPlanScoped = false,
    this.previousTitle,
    this.nextTitle,
    this.onPreviousTap,
    this.onNextTap,
  });

  static const previousSegmentKey = Key(
    'song-reader-bottom-bar-previous-segment',
  );
  static const nextSegmentKey = Key('song-reader-bottom-bar-next-segment');
  static const disabledSegmentOpacity = 0.5;

  /// Caps the text scale this bar renders at, independent of the system
  /// setting. The bar's height is chrome the spec pins at 64/58 -- letting
  /// the two-line title/subtitle block grow with the system text scale
  /// would either overflow that fixed height (measured: 6px overflow at
  /// 1.5x, 24px at 2.0x, both breakpoints) or force the bar itself to grow,
  /// which eats into the song's space -- the exact thing this restructure
  /// exists to stop (spec section 6, "Space recovered"). Clamping the bar's
  /// own scale instead means very large system text scales lose some
  /// legibility in this one fixed-height bar rather than breaking layout or
  /// shrinking the reading area. 1.2 was chosen empirically: measured against
  /// this bar's own content at both breakpoints, 1.25 is already the first
  /// scale that overflows (by 1px at the tablet breakpoint), so 1.2 keeps a
  /// deliberate margin rather than sitting exactly on the boundary.
  static const _maxTextScaleFactor = 1.2;

  /// The current song's title. Always shown, centred within its column.
  final String currentTitle;

  /// The current song's effective key, or null when unknown.
  final String? keyLabel;

  /// The capo directive text (e.g. "Capo 3"), or null. Callers gate this on
  /// `SongReaderProjection.isCapoDirectiveVisible`
  /// (`song_reader_projection.dart:23-25`) before passing it in — this
  /// widget just renders whatever it is given.
  final String? capoLabel;

  /// 1-based position of the current item within its session, or null when
  /// not plan-scoped (or unknown).
  final int? position;

  /// Total number of items in the session, or null alongside [position].
  final int? itemCount;

  /// Whether the reader is scoped to a plan session. Selects between the
  /// plan-scoped layout (neighbour chevrons, position) and the catalogue
  /// layout (centred current-song info only).
  final bool isPlanScoped;

  final String? previousTitle;
  final String? nextTitle;
  final VoidCallback? onPreviousTap;
  final VoidCallback? onNextTap;

  @override
  Widget build(BuildContext context) {
    final readerTheme = ReaderTheme.of(context);

    return Material(
      color: readerTheme.floatingChromeBackground,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final chromeMetrics = SongReaderChromeMetrics.resolve(
            constraints.maxWidth,
          );
          // The reader has no ancestor `SafeArea` (see
          // `song_reader_shell.dart`), so this bar consumes the bottom inset
          // itself: its total height is the bar height plus the inset, and
          // the inset sits UNDER the bar's content rather than pushing the
          // labels down. `viewPaddingOf`, not `paddingOf` — the reader has no
          // text input, so the bar must not move if a keyboard appears.
          //
          // It also runs edge to edge, so a landscape notch on either side
          // would otherwise sit directly on top of the previous/next chevron
          // -- consume the left/right insets too, the same way the top bar
          // and the control rail's caller do.
          final viewPadding = MediaQuery.viewPaddingOf(context);
          final bottomInset = viewPadding.bottom;
          final isRegular =
              constraints.maxWidth >= readerRegularTypeScaleMinWidth;
          final showNeighborTitles = isPlanScoped && isRegular;

          final center = _CurrentSongInfo(
            title: currentTitle,
            keyLabel: keyLabel,
            capoLabel: capoLabel,
            position: isPlanScoped ? position : null,
            itemCount: isPlanScoped ? itemCount : null,
            titleSubtitleGap: chromeMetrics.bottomBarTitleSubtitleGap,
          );

          Widget content;
          if (!isPlanScoped) {
            content = Center(child: center);
          } else {
            content = Row(
              children: [
                _NeighborSegment(
                  key: previousSegmentKey,
                  direction: _NeighborDirection.previous,
                  title: showNeighborTitles ? previousTitle : null,
                  showTitle: showNeighborTitles,
                  onTap: onPreviousTap,
                ),
                Expanded(child: Center(child: center)),
                _NeighborSegment(
                  key: nextSegmentKey,
                  direction: _NeighborDirection.next,
                  title: showNeighborTitles ? nextTitle : null,
                  showTitle: showNeighborTitles,
                  onTap: onNextTap,
                ),
              ],
            );
          }

          final verticalPadding = chromeMetrics.bottomBarVerticalPadding;
          final horizontalPadding = chromeMetrics.bottomBarHorizontalPadding;

          final clampedTextScaler = MediaQuery.textScalerOf(
            context,
          ).clamp(maxScaleFactor: _maxTextScaleFactor);

          return SizedBox(
            height: chromeMetrics.bottomBarHeight + bottomInset,
            child: MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: clampedTextScaler),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding + viewPadding.left,
                  verticalPadding,
                  horizontalPadding + viewPadding.right,
                  verticalPadding + bottomInset,
                ),
                child: content,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CurrentSongInfo extends StatelessWidget {
  const _CurrentSongInfo({
    required this.title,
    required this.keyLabel,
    required this.capoLabel,
    required this.position,
    required this.itemCount,
    required this.titleSubtitleGap,
  });

  final String title;
  final String? keyLabel;
  final String? capoLabel;
  final int? position;
  final int? itemCount;

  /// Gap between the title line and the subtitle line, from
  /// [SongReaderChromeMetrics.bottomBarTitleSubtitleGap] -- ADR-033 forbids
  /// hardcoding it here as a `SizedBox` literal.
  final double titleSubtitleGap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitleParts = <String>[
      if (keyLabel != null) '${AppStrings.songReaderKeyLabelPrefix}$keyLabel',
      ?capoLabel,
      if (position != null && itemCount != null) '$position / $itemCount',
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleSmall,
        ),
        if (subtitleParts.isNotEmpty) ...[
          SizedBox(height: titleSubtitleGap),
          Text(
            subtitleParts.join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

enum _NeighborDirection { previous, next }

class _NeighborSegment extends StatelessWidget {
  const _NeighborSegment({
    super.key,
    required this.direction,
    required this.title,
    required this.showTitle,
    required this.onTap,
  });

  final _NeighborDirection direction;
  final String? title;
  final bool showTitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPrevious = direction == _NeighborDirection.previous;
    final tooltip = isPrevious
        ? AppStrings.scopedReaderPreviousAction
        : AppStrings.scopedReaderNextAction;
    final icon = isPrevious ? Icons.chevron_left : Icons.chevron_right;

    final chevron = Icon(icon, color: theme.colorScheme.onSurfaceVariant);

    final children = <Widget>[
      if (isPrevious) chevron,
      if (showTitle && title != null)
        Flexible(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              title!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: isPrevious ? TextAlign.start : TextAlign.end,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ),
      if (!isPrevious) chevron,
    ];

    final body = Row(
      mainAxisSize: showTitle ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: isPrevious
          ? MainAxisAlignment.start
          : MainAxisAlignment.end,
      children: children,
    );

    final segment = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Opacity(
            opacity: onTap == null
                ? SongReaderBottomBar.disabledSegmentOpacity
                : 1,
            child: Tooltip(message: tooltip, child: body),
          ),
        ),
      ),
    );

    return showTitle ? Expanded(child: segment) : segment;
  }
}
