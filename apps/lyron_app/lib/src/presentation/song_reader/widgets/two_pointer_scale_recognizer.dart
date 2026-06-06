import 'package:flutter/gestures.dart';

/// A [ScaleGestureRecognizer] that refuses to win the gesture arena until at
/// least two pointers are tracked.  This lets a [SingleChildScrollView]'s
/// vertical-drag recognizer continue to own single-finger drags uncontested,
/// while this recognizer takes over only when a true pinch (2+ fingers) is
/// detected.
class TwoPointerScaleRecognizer extends ScaleGestureRecognizer {
  TwoPointerScaleRecognizer({super.debugOwner, super.supportedDevices});

  int _trackedPointerCount = 0;

  @override
  void addPointer(PointerDownEvent event) {
    _trackedPointerCount++;
    super.addPointer(event);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _trackedPointerCount = 0;
    super.didStopTrackingLastPointer(pointer);
  }

  @override
  void resolve(GestureDisposition disposition) {
    // Only accept when two or more pointers are involved; otherwise reject so
    // the arena remains open for the scroll recognizer.
    if (_trackedPointerCount < 2 &&
        disposition == GestureDisposition.accepted) {
      super.resolve(GestureDisposition.rejected);
      return;
    }
    super.resolve(disposition);
  }
}
