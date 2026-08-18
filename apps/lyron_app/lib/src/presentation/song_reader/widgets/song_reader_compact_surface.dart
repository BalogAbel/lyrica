import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_char_metrics.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_chrome_metrics.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_fit.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_bottom_bar.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_control_bar.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_section_grid.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/two_pointer_scale_recognizer.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

class SongReaderCompactSurface extends StatefulWidget {
  const SongReaderCompactSurface({
    super.key,
    required this.projection,
    required this.areControlsVisible,
    required this.currentTitle,
    this.topBar,
    required this.onSurfaceTap,
    required this.hasRecoverableWarnings,
    required this.warningCount,
    required this.contentColumnCount,
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
    this.position,
    this.itemCount,
    required this.maxContentWidth,
    required this.contentPadding,
  });

  final SongReaderProjection projection;
  final bool areControlsVisible;
  final String currentTitle;

  /// The reader's top bar content (back button, title, warnings, overflow
  /// menu). Rendered as a `Positioned` overlay when the chrome is revealed —
  /// see the `Stack` in `build()`. Owned by the screen (which also decides
  /// whether the compact shell or the expanded shell's `Scaffold.appBar`
  /// renders it), so this widget just places it. Nullable so widget tests
  /// that only care about the content geometry (e.g. the chrome guard test)
  /// don't have to supply one; production call sites always pass it.
  final Widget? topBar;
  final String? previousTitle;
  final String? nextTitle;
  final VoidCallback? onPreviousTap;
  final VoidCallback? onNextTap;

  /// 1-based position of the current item within its session, for the
  /// bottom bar's plan-scoped "3 / 7" set position. Null when not
  /// plan-scoped or unknown.
  final int? position;

  /// Total number of items in the session, alongside [position].
  final int? itemCount;

  final VoidCallback onSurfaceTap;
  final bool hasRecoverableWarnings;
  final int warningCount;
  final int contentColumnCount;
  final bool showBottomContextBar;
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

  // Resolved padding dimensions (updated each build inside the LayoutBuilder).
  double _contentPaddingH = 0;
  double _contentPaddingV = 0;

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

    // Subtract resolved content padding so the fit estimate uses the same
    // dimensions as the actual scrollable area.
    final rawWidth = constraints.maxWidth < widget.maxContentWidth
        ? constraints.maxWidth
        : widget.maxContentWidth;
    final availableWidth = rawWidth - _contentPaddingH;
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
              // Disabled while the chrome is revealed: a GestureDetector
              // with both onTap and onDoubleTap must wait to disambiguate
              // the two on every tap, including taps on the top bar / rail
              // buttons nested inside it below (they still hit-test through
              // this ancestor). That wait was intermittently stealing
              // repeat taps on those buttons -- e.g. reopening the overflow
              // menu a second time silently did nothing instead of showing
              // it, because the ambient double-tap recognizer paired it
              // with the tap that first opened the menu. Double-tap-to-fit
              // only makes sense over content anyway, never while the
              // overlay chrome is up, so gating it here is correct, not
              // just a workaround.
              onDoubleTap: widget.areControlsVisible ? null : _handleDoubleTap,
              child: Builder(
                builder: (context) {
                  final chromeMetrics = SongReaderChromeMetrics.resolve(
                    MediaQuery.sizeOf(context).width,
                  );
                  return Column(
                    children: [
                      Expanded(
                        child: Stack(
                          // NON-NEGOTIABLE: `content` (the LayoutBuilder
                          // below) must stay the ONLY non-Positioned child of
                          // this Stack. A Stack sizes itself off its
                          // non-positioned children only, and hands them
                          // constraints derived solely from its own incoming
                          // constraints -- never from sibling Positioned
                          // children. That is what keeps revealing the top
                          // bar / rail from changing the `availableHeight`
                          // the fit LayoutBuilder below sees. Do NOT add a
                          // second non-Positioned child, do NOT give the
                          // overlays `StackFit.expand`, and do NOT wrap
                          // `content` in anything that reads the overlays'
                          // size. See
                          // test/presentation/song_reader/widgets/song_reader_chrome_geometry_test.dart,
                          // which fails the instant this invariant breaks.
                          children: [
                            LayoutBuilder(
                              builder: (context, constraints) {
                                // Store constraints and resolved padding so
                                // _handleDoubleTap can use the viewport
                                // dimensions without capturing a stale
                                // BuildContext.
                                final resolved = widget.contentPadding.resolve(
                                  Directionality.maybeOf(context) ??
                                      TextDirection.ltr,
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
                                    child:
                                        // A fixed left edge, not a centred shrink-wrap.
                                        // Center + ConstrainedBox passed LOOSE
                                        // constraints down, so the section grid's
                                        // Column sized itself to its own longest
                                        // line and was then centred -- every
                                        // section started from a content-dependent
                                        // left edge. A tight width on the section
                                        // grid itself is what fixes that; swapping
                                        // Center for Align around the OLD child
                                        // would shrink-wrap identically. The outer
                                        // Align (rather than dropping it) is still
                                        // needed so the SingleChildScrollView
                                        // itself stays full viewport width and the
                                        // scrollbar thumb sits at the physical
                                        // screen edge -- only the positioned child
                                        // is tight-width and left-aligned.
                                        Align(
                                          alignment: Alignment.topLeft,
                                          child: SizedBox(
                                            width: math.min(
                                              constraints.maxWidth,
                                              widget.maxContentWidth,
                                            ),
                                            child: Padding(
                                              padding: widget.contentPadding,
                                              child: SongReaderSectionGrid(
                                                leadingDirectiveText: widget
                                                    .projection
                                                    .capoDirectiveText,
                                                sections:
                                                    widget.projection.sections,
                                                viewMode:
                                                    widget.projection.viewMode,
                                                sharedFontScale: widget
                                                    .projection
                                                    .sharedFontScale,
                                                columnCount:
                                                    widget.contentColumnCount,
                                                availableHeight:
                                                    availableHeight, // already padding-adjusted
                                              ),
                                            ),
                                          ),
                                        ),
                                  ),
                                );
                              },
                            ),
                            if (widget.areControlsVisible &&
                                widget.topBar != null)
                              Positioned(
                                top: 0,
                                left: 0,
                                right: 0,
                                child: widget.topBar!,
                              ),
                            if (widget.areControlsVisible)
                              Positioned(
                                top: 0,
                                bottom: 0,
                                right: chromeMetrics.railEdgeInset,
                                child: Center(
                                  child: SongReaderControlBar(
                                    projection: widget.projection,
                                    onTransposeDown: widget.onTransposeDown,
                                    onTransposeUp: widget.onTransposeUp,
                                    onCapoDown: widget.onCapoDown,
                                    onCapoUp: widget.onCapoUp,
                                    onDecreaseFontScale:
                                        widget.onDecreaseFontScale,
                                    onIncreaseFontScale:
                                        widget.onIncreaseFontScale,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      // Always-present bottom bar slot: unlike the top bar and
                      // rail above, this does not depend on
                      // `areControlsVisible` -- it occupies layout space in
                      // the Column at all times (spec section 6, "an
                      // always-visible bottom bar"). A hard SizedBox height,
                      // not a minHeight -- SongReaderBottomBar's contents are
                      // sized to fit `bottomBarHeight` exactly (song-
                      // presentation slice Task 6).
                      SizedBox(
                        height: chromeMetrics.bottomBarHeight,
                        child: SongReaderBottomBar(
                          currentTitle: widget.currentTitle,
                          keyLabel: widget.projection.effectiveKey,
                          capoLabel: widget.projection.isCapoDirectiveVisible
                              ? widget.projection.capoDirectiveText
                              : null,
                          position: widget.position,
                          itemCount: widget.itemCount,
                          isPlanScoped: widget.showBottomContextBar,
                          previousTitle: widget.previousTitle,
                          nextTitle: widget.nextTitle,
                          onPreviousTap: widget.onPreviousTap,
                          onNextTap: widget.onNextTap,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
