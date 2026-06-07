import 'package:flutter/gestures.dart';

/// A [ScaleGestureRecognizer] that refuses to win the gesture arena until at
/// least two pointers are tracked.  This lets a [SingleChildScrollView]'s
/// vertical-drag recognizer continue to own single-finger drags uncontested,
/// while this recognizer takes over only when a true pinch (2+ fingers) is
/// detected.
class TwoPointerScaleRecognizer extends ScaleGestureRecognizer {
  TwoPointerScaleRecognizer({super.debugOwner, super.supportedDevices});

  /// Tracks the IDs of pointers currently known to this recognizer.
  /// Using a Set prevents double-counting if a pointer ID is reused before
  /// removal, and keeps the count accurate when the recognizer loses the arena
  /// or a pointer is rejected mid-gesture.
  final Set<int> _trackedPointers = {};

  @override
  void addPointer(PointerDownEvent event) {
    _trackedPointers.add(event.pointer);
    super.addPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      _trackedPointers.remove(event.pointer);
    }
    super.handleEvent(event);
  }

  @override
  void rejectGesture(int pointer) {
    _trackedPointers.remove(pointer);
    super.rejectGesture(pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _trackedPointers.clear();
    super.didStopTrackingLastPointer(pointer);
  }

  @override
  void resolve(GestureDisposition disposition) {
    // Only accept when two or more pointers are involved; otherwise reject so
    // the arena remains open for the scroll recognizer.
    if (_trackedPointers.length < 2 &&
        disposition == GestureDisposition.accepted) {
      super.resolve(GestureDisposition.rejected);
      return;
    }
    super.resolve(disposition);
  }
}
