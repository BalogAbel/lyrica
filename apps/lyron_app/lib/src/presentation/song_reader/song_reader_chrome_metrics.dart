import 'package:flutter/foundation.dart';
import 'package:lyron_app/src/app/reader_theme.dart';

/// Fixed sizes for the compact shell's chrome (top bar, bottom bar, control
/// rail), resolved off viewport width.
///
/// This is the second of the reader's three width thresholds to be reused
/// here: [readerRegularTypeScaleMinWidth] (600, `reader_theme.dart:13`) picks
/// between the phone and tablet/desktop bar sizes below. It sits alongside
/// `denseLayoutMinWidth` (1180, two-column content — `song_reader_fit.dart:166`)
/// and the expanded shell's 1600 (`song_reader_layout.dart:33`); all three key
/// off viewport WIDTH. This file does not declare a fourth threshold or a
/// second 600 — one definition per value is the rule the token layer is built
/// on.
///
/// **The bottom bar height carried here is the BAR only.** The home-indicator
/// safe-area inset (`MediaQuery.viewPaddingOf(context).bottom`) is added by
/// `SongReaderBottomBar` at render time, not folded into [bottomBarHeight].
/// Keeping the split lets this value object — and any test of it — stay free
/// of `MediaQuery`, while the widget test that needs the inset injects one
/// case at a time (see spec section 6, "Per-surface safe area").
@immutable
class SongReaderChromeMetrics {
  const SongReaderChromeMetrics({
    required this.bottomBarHeight,
    required this.topBarHeight,
    required this.railEdgeInset,
  });

  /// Resolves the chrome metrics for a compact-shell viewport of [width].
  ///
  /// Below [readerRegularTypeScaleMinWidth] (phone) the bars are shorter,
  /// matching Material 3's own phone/tablet split.
  factory SongReaderChromeMetrics.resolve(double width) {
    final isRegular = width >= readerRegularTypeScaleMinWidth;
    return SongReaderChromeMetrics(
      bottomBarHeight: isRegular ? 64.0 : 58.0,
      topBarHeight: isRegular ? 64.0 : 58.0,
      railEdgeInset: 12.0,
    );
  }

  /// Height of the always-visible bottom bar's BAR portion, excluding the
  /// home-indicator safe-area inset. 64.0 at or above
  /// [readerRegularTypeScaleMinWidth] (tablet/desktop), 58.0 below it
  /// (phone) — the same phone/tablet split the type scale and
  /// `SongReaderMetrics` already use (`reader_theme.dart`'s
  /// `_readerMetrics`), so the chrome does not introduce a fourth scale of
  /// its own.
  final double bottomBarHeight;

  /// Height of the floating top bar, which overlays the content rather than
  /// occupying `Column` space (see spec section 6). Mirrors
  /// [bottomBarHeight]'s phone/tablet split for the same reason: the two
  /// bars read as one system, so they should not silently disagree by a few
  /// px at the same breakpoint.
  final double topBarHeight;

  /// Edge inset between the compact shell's right edge and the floating
  /// control rail, on both axes of the rail's own padding.
  ///
  /// 12.0 matches the reader's existing side padding convention
  /// (`song_reader_shell.dart`'s `_contentPadding` uses the same horizontal
  /// figure), so the rail sits at the same distance from the edge that the
  /// content itself already respects.
  final double railEdgeInset;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SongReaderChromeMetrics &&
        other.bottomBarHeight == bottomBarHeight &&
        other.topBarHeight == topBarHeight &&
        other.railEdgeInset == railEdgeInset;
  }

  @override
  int get hashCode => Object.hash(bottomBarHeight, topBarHeight, railEdgeInset);
}
