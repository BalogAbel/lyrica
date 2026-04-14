import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_bottom_context_bar.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_compact_overlay.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_section_grid.dart';

class SongReaderCompactSurface extends StatefulWidget {
  const SongReaderCompactSurface({
    super.key,
    required this.projection,
    required this.areControlsVisible,
    required this.currentTitle,
    required this.onSurfaceTap,
    required this.onSurfaceDoubleTap,
    required this.hasRecoverableWarnings,
    required this.warningCount,
    required this.contentColumnCount,
    required this.onToggleViewMode,
    required this.onTransposeDown,
    required this.onTransposeUp,
    required this.onDecreaseFontScale,
    required this.onIncreaseFontScale,
    this.previousTitle,
    this.nextTitle,
  });

  final SongReaderProjection projection;
  final bool areControlsVisible;
  final String currentTitle;
  final String? previousTitle;
  final String? nextTitle;
  final VoidCallback onSurfaceTap;
  final VoidCallback onSurfaceDoubleTap;
  final bool hasRecoverableWarnings;
  final int warningCount;
  final int contentColumnCount;
  final VoidCallback onToggleViewMode;
  final VoidCallback onTransposeDown;
  final VoidCallback onTransposeUp;
  final VoidCallback onDecreaseFontScale;
  final VoidCallback onIncreaseFontScale;

  @override
  State<SongReaderCompactSurface> createState() =>
      _SongReaderCompactSurfaceState();
}

class _SongReaderCompactSurfaceState extends State<SongReaderCompactSurface> {
  static const _tapSlop = 8.0;

  int? _activePointer;
  Offset? _pointerDownPosition;
  bool _movedBeyondTapSlop = false;

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

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: (event) => _handlePointerEnd(event.pointer),
      onPointerCancel: (event) => _handlePointerEnd(event.pointer),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.areControlsVisible ? widget.onSurfaceTap : null,
        onDoubleTap: widget.onSurfaceDoubleTap,
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        child: SongReaderSectionGrid(
                          sections: widget.projection.sections,
                          viewMode: widget.projection.viewMode,
                          sharedFontScale: widget.projection.sharedFontScale,
                          columnCount: widget.contentColumnCount,
                          availableHeight: constraints.maxHeight,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                SongReaderBottomContextBar(
                  currentTitle: widget.currentTitle,
                  previousTitle: widget.previousTitle,
                  nextTitle: widget.nextTitle,
                ),
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
              onDecreaseFontScale: widget.onDecreaseFontScale,
              onIncreaseFontScale: widget.onIncreaseFontScale,
            ),
          ],
        ),
      ),
    );
  }
}
