import 'package:flutter/material.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_char_metrics.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_fit.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_expanded_context_panel.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_expanded_tools_panel.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_section_grid.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/two_pointer_scale_recognizer.dart';

class SongReaderExpandedSurface extends StatefulWidget {
  const SongReaderExpandedSurface({
    super.key,
    required this.projection,
    required this.showContextPanel,
    required this.contentColumnCount,
    required this.onTransposeDown,
    required this.onTransposeUp,
    this.onCapoDown,
    this.onCapoUp,
    required this.onDecreaseFontScale,
    required this.onIncreaseFontScale,
    this.previousTitle,
    this.nextTitle,
    this.onPreviousTap,
    this.onNextTap,
    required this.contentPadding,
    this.onSetFontScale,
    this.onPersistFontScale,
  });

  final SongReaderProjection projection;
  final bool showContextPanel;
  final String? previousTitle;
  final String? nextTitle;
  final VoidCallback? onPreviousTap;
  final VoidCallback? onNextTap;
  final int contentColumnCount;
  final VoidCallback onTransposeDown;
  final VoidCallback onTransposeUp;
  final VoidCallback? onCapoDown;
  final VoidCallback? onCapoUp;
  final VoidCallback onDecreaseFontScale;
  final VoidCallback onIncreaseFontScale;

  /// Padding applied around the song content grid inside the scroll view.
  final EdgeInsetsGeometry contentPadding;

  /// Called continuously during a two-finger pinch with the new absolute scale.
  final ValueChanged<double>? onSetFontScale;

  /// Called once when the pinch gesture ends (e.g. to persist the scale).
  final VoidCallback? onPersistFontScale;

  @override
  State<SongReaderExpandedSurface> createState() =>
      _SongReaderExpandedSurfaceState();
}

class _SongReaderExpandedSurfaceState extends State<SongReaderExpandedSurface> {
  late final ScrollController _scrollController;

  // Pinch-to-zoom state.
  double _pinchBaselineScale = 1.0;
  double _lastEmittedScale = 1.0;

  // Fit-to-screen toggle state.
  //
  // When non-null, a fit is active: _preFitScale holds the scale that was in
  // effect before the first double-tap (so the second double-tap can restore
  // it). The field is also reset in didUpdateWidget: if the projection scale
  // changes to something other than the fit we last applied and other than the
  // stored pre-fit scale, the user must have changed scale via pinch/buttons,
  // so we discard the stale restore point and treat the next double-tap as a
  // fresh fit.
  double? _preFitScale;
  double? _lastAppliedFitScale;

  // Latest constraints from the content LayoutBuilder, used by _handleDoubleTap.
  BoxConstraints? _contentConstraints;

  // Resolved padding dimensions (updated each build inside the LayoutBuilder).
  double _contentPaddingH = 0;
  double _contentPaddingV = 0;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void didUpdateWidget(covariant SongReaderExpandedSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newScale = widget.projection.sharedFontScale;
    // If a fit is active and the incoming scale is neither the fit value we
    // applied nor the stored pre-fit scale, the user changed scale externally
    // (pinch / buttons). Clear the stale restore point so the next double-tap
    // starts a fresh fit rather than restoring an outdated scale.
    if (_preFitScale != null &&
        newScale != _lastAppliedFitScale &&
        newScale != _preFitScale) {
      _preFitScale = null;
      _lastAppliedFitScale = null;
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Handles a double-tap: first tap fits the song to the viewport, second tap
  /// restores the pre-fit scale.
  void _handleDoubleTap() {
    final constraints = _contentConstraints;
    if (constraints == null) return;

    // Subtract resolved content padding so the fit estimate uses the same
    // dimensions as the actual scrollable area.
    final availableWidth = constraints.maxWidth - _contentPaddingH;
    final availableHeight = constraints.maxHeight - _contentPaddingV;

    if (_preFitScale == null) {
      // First double-tap: compute and apply fit scale. Measure the real
      // lyric/chord character advances once here (a single-shot event
      // handler, not a per-line or per-binary-search-iteration call) rather
      // than let the fit calculator guess with a flat constant.
      _preFitScale = widget.projection.sharedFontScale;
      final charWidths = measureSongReaderCharWidths(context);
      final fit = resolveFitFontScale(
        sections: widget.projection.sections,
        viewMode: widget.projection.viewMode,
        availableWidth: availableWidth,
        availableHeight: availableHeight,
        minScale: SongReaderState.minSharedFontScale,
        maxScale: SongReaderState.maxSharedFontScale,
        allowTwoColumns: widget.contentColumnCount > 1,
        leadingDirectiveHeight: widget.projection.capoDirectiveText != null
            ? charWidths.metrics.directiveLineHeight +
                  charWidths.metrics.sectionGap
            : 0,
        leadingDirectiveText: widget.projection.capoDirectiveText,
        lyricCharWidth: charWidths.lyricCharWidth,
        chordCharWidth: charWidths.chordCharWidth,
        headerCharWidth: charWidths.headerCharWidth,
        textScale: charWidths.textScale,
        metrics: charWidths.metrics,
      );
      _lastAppliedFitScale = fit;
      widget.onSetFontScale?.call(fit);
    } else {
      // Second double-tap: restore the stored pre-fit scale.
      widget.onSetFontScale?.call(_preFitScale!);
      _preFitScale = null;
      _lastAppliedFitScale = null;
    }
    widget.onPersistFontScale?.call();
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _pinchBaselineScale = widget.projection.sharedFontScale;
    _lastEmittedScale = widget.projection.sharedFontScale;
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount < 2) {
      // Single-finger — let scroll happen, do not adjust font scale.
      return;
    }
    final newScale = (_pinchBaselineScale * details.scale).clamp(
      SongReaderState.minSharedFontScale,
      SongReaderState.maxSharedFontScale,
    );
    if ((newScale - _lastEmittedScale).abs() < 0.005) {
      return;
    }
    _lastEmittedScale = newScale;
    widget.onSetFontScale?.call(newScale);
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    widget.onPersistFontScale?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 240,
          child: Align(
            alignment: Alignment.topLeft,
            child: widget.showContextPanel
                ? SongReaderExpandedContextPanel(
                    previousTitle: widget.previousTitle,
                    nextTitle: widget.nextTitle,
                    onPreviousTap: widget.onPreviousTap,
                    onNextTap: widget.onNextTap,
                  )
                : const SizedBox.shrink(),
          ),
        ),
        const SizedBox(width: 24),
        Expanded(
          child: RawGestureDetector(
            gestures: {
              TwoPointerScaleRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    TwoPointerScaleRecognizer
                  >(() => TwoPointerScaleRecognizer(debugOwner: this), (
                    instance,
                  ) {
                    instance
                      ..onStart = _handleScaleStart
                      ..onUpdate = _handleScaleUpdate
                      ..onEnd = _handleScaleEnd;
                  }),
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onDoubleTap: _handleDoubleTap,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Store constraints and resolved padding so _handleDoubleTap
                  // can use the viewport dimensions without a stale BuildContext.
                  final resolved = widget.contentPadding.resolve(
                    Directionality.maybeOf(context) ?? TextDirection.ltr,
                  );
                  _contentPaddingH = resolved.horizontal;
                  _contentPaddingV = resolved.vertical;
                  _contentConstraints = constraints;
                  final availableHeight =
                      constraints.maxHeight - _contentPaddingV;
                  return Scrollbar(
                    controller: _scrollController,
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      // The outer Row governs this column's width; no ConstrainedBox
                      // needed. Padding lives inside so the scrollbar thumb reaches
                      // the physical edge.
                      child: Padding(
                        padding: widget.contentPadding,
                        child: SongReaderSectionGrid(
                          leadingDirectiveText:
                              widget.projection.capoDirectiveText,
                          sections: widget.projection.sections,
                          viewMode: widget.projection.viewMode,
                          sharedFontScale: widget.projection.sharedFontScale,
                          columnCount: widget.contentColumnCount,
                          availableHeight:
                              availableHeight, // already padding-adjusted
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(width: 24),
        SizedBox(
          width: 320,
          child: SongReaderExpandedToolsPanel(
            projection: widget.projection,
            onTransposeDown: widget.onTransposeDown,
            onTransposeUp: widget.onTransposeUp,
            onCapoDown: widget.onCapoDown,
            onCapoUp: widget.onCapoUp,
            onDecreaseFontScale: widget.onDecreaseFontScale,
            onIncreaseFontScale: widget.onIncreaseFontScale,
          ),
        ),
      ],
    );
  }
}
