import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_fit.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_bottom_context_bar.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_compact_overlay.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_section_grid.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/two_pointer_scale_recognizer.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

class SongReaderCompactSurface extends StatefulWidget {
  const SongReaderCompactSurface({
    super.key,
    required this.projection,
    required this.areControlsVisible,
    required this.currentTitle,
    required this.onSurfaceTap,
    required this.hasRecoverableWarnings,
    required this.warningCount,
    required this.contentColumnCount,
    required this.onToggleViewMode,
    required this.onTransposeDown,
    required this.onTransposeUp,
    this.onCapoDown,
    this.onCapoUp,
    required this.onDecreaseFontScale,
    required this.onIncreaseFontScale,
    required this.showBottomContextBar,
    this.onSetFontScale,
    this.onPersistFontScale,
    this.previousTitle,
    this.nextTitle,
    this.onPreviousTap,
    this.onNextTap,
    required this.maxContentWidth,
    required this.contentPadding,
  });

  final SongReaderProjection projection;
  final bool areControlsVisible;
  final String currentTitle;
  final String? previousTitle;
  final String? nextTitle;
  final VoidCallback? onPreviousTap;
  final VoidCallback? onNextTap;
  final VoidCallback onSurfaceTap;
  final bool hasRecoverableWarnings;
  final int warningCount;
  final int contentColumnCount;
  final bool showBottomContextBar;
  final VoidCallback onToggleViewMode;
  final VoidCallback onTransposeDown;
  final VoidCallback onTransposeUp;
  final VoidCallback? onCapoDown;
  final VoidCallback? onCapoUp;
  final VoidCallback onDecreaseFontScale;
  final VoidCallback onIncreaseFontScale;

  /// Called continuously during a two-finger pinch with the new absolute scale.
  final ValueChanged<double>? onSetFontScale;

  /// Called once when the pinch gesture ends (e.g. to persist the scale).
  final VoidCallback? onPersistFontScale;

  /// Maximum logical width of the song content area (centering cap).
  final double maxContentWidth;

  /// Padding applied around the song content grid inside the scroll view.
  final EdgeInsetsGeometry contentPadding;

  @override
  State<SongReaderCompactSurface> createState() =>
      _SongReaderCompactSurfaceState();
}

class _SongReaderCompactSurfaceState extends State<SongReaderCompactSurface> {
  static const _tapSlop = 8.0;

  late final ScrollController _scrollController;

  int? _activePointer;
  Offset? _pointerDownPosition;
  bool _movedBeyondTapSlop = false;

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

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void didUpdateWidget(covariant SongReaderCompactSurface oldWidget) {
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

    final availableHeight = constraints.maxHeight;
    // Content is horizontally capped by maxContentWidth; use the smaller of
    // the viewport width and the cap so the estimate matches the real layout.
    final availableWidth = constraints.maxWidth < widget.maxContentWidth
        ? constraints.maxWidth
        : widget.maxContentWidth;

    if (_preFitScale == null) {
      // First double-tap: compute and apply fit scale.
      _preFitScale = widget.projection.sharedFontScale;
      final fit = resolveFitFontScale(
        sections: widget.projection.sections,
        viewMode: widget.projection.viewMode,
        availableWidth: availableWidth,
        availableHeight: availableHeight,
        minScale: SongReaderState.minSharedFontScale,
        maxScale: SongReaderState.maxSharedFontScale,
        allowTwoColumns: widget.contentColumnCount > 1,
        leadingDirectiveHeight: widget.projection.capoDirectiveText != null
            ? directiveLineHeight + sectionGap
            : 0,
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

  void _handlePointerDown(PointerDownEvent event) {
    if (event.buttons != kPrimaryButton || _activePointer != null) {
      return;
    }

    _activePointer = event.pointer;
    _pointerDownPosition = event.position;
    _movedBeyondTapSlop = false;
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer || _pointerDownPosition == null) {
      return;
    }

    final distance = (event.position - _pointerDownPosition!).distance;
    if (distance > _tapSlop) {
      _movedBeyondTapSlop = true;
    }
  }

  void _handlePointerEnd(int pointer) {
    if (pointer != _activePointer) {
      return;
    }

    final shouldRevealOverlay =
        !_movedBeyondTapSlop && !widget.areControlsVisible;
    _activePointer = null;
    _pointerDownPosition = null;
    _movedBeyondTapSlop = false;

    if (shouldRevealOverlay) {
      widget.onSurfaceTap();
    }
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
    return FocusableActionDetector(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (intent) {
            widget.onSurfaceTap();
            return null;
          },
        ),
      },
      child: Semantics(
        button: true,
        label: widget.areControlsVisible
            ? AppStrings.songReaderHideControlsSemantics
            : AppStrings.songReaderShowControlsSemantics,
        onTap: widget.onSurfaceTap,
        child: RawGestureDetector(
          gestures: {
            TwoPointerScaleRecognizer:
                GestureRecognizerFactoryWithHandlers<TwoPointerScaleRecognizer>(
                  () => TwoPointerScaleRecognizer(debugOwner: this),
                  (instance) {
                    instance
                      ..onStart = _handleScaleStart
                      ..onUpdate = _handleScaleUpdate
                      ..onEnd = _handleScaleEnd;
                  },
                ),
          },
          child: Listener(
            onPointerDown: _handlePointerDown,
            onPointerMove: _handlePointerMove,
            onPointerUp: (event) => _handlePointerEnd(event.pointer),
            onPointerCancel: (event) => _handlePointerEnd(event.pointer),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.areControlsVisible ? widget.onSurfaceTap : null,
              onDoubleTap: _handleDoubleTap,
              child: Stack(
                children: [
                  Column(
                    children: [
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            // Store constraints so _handleDoubleTap can use
                            // the viewport dimensions without capturing a stale
                            // BuildContext.
                            _contentConstraints = constraints;
                            final availableHeight = constraints.maxHeight;
                            return Scrollbar(
                              controller: _scrollController,
                              child: SingleChildScrollView(
                                controller: _scrollController,
                                child: Center(
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: widget.maxContentWidth,
                                    ),
                                    child: Padding(
                                      padding: widget.contentPadding,
                                      child: SongReaderSectionGrid(
                                        leadingDirectiveText:
                                            widget.projection.capoDirectiveText,
                                        sections: widget.projection.sections,
                                        viewMode: widget.projection.viewMode,
                                        sharedFontScale:
                                            widget.projection.sharedFontScale,
                                        columnCount: widget.contentColumnCount,
                                        availableHeight: availableHeight,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      if (widget.showBottomContextBar) ...[
                        const SizedBox(height: 16),
                        SongReaderBottomContextBar(
                          currentTitle: widget.currentTitle,
                          previousTitle: widget.previousTitle,
                          nextTitle: widget.nextTitle,
                          onPreviousTap: widget.onPreviousTap,
                          onNextTap: widget.onNextTap,
                        ),
                      ],
                    ],
                  ),
                  SongReaderCompactOverlay(
                    isVisible: widget.areControlsVisible,
                    projection: widget.projection,
                    hasRecoverableWarnings: widget.hasRecoverableWarnings,
                    warningCount: widget.warningCount,
                    onToggleViewMode: widget.onToggleViewMode,
                    onTransposeDown: widget.onTransposeDown,
                    onTransposeUp: widget.onTransposeUp,
                    onCapoDown: widget.onCapoDown,
                    onCapoUp: widget.onCapoUp,
                    onDecreaseFontScale: widget.onDecreaseFontScale,
                    onIncreaseFontScale: widget.onIncreaseFontScale,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
