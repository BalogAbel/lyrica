import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [LocalFileComparator] that lets a golden differ from its master by a
/// small share of pixels.
///
/// The reader-chrome goldens are generated on macOS and compared on the
/// `ubuntu-latest` CI runner. The same widget tree anti-aliases rounded corners
/// and icon edges slightly differently there, so an exact comparison would
/// fail for no real change. [maxDiffPercent] is the share of differing pixels
/// that still passes, as a fraction: `0.005` is 0.5%. It never exceeds `0.01`
/// (1%): a larger difference is a real change to investigate, not a tolerance
/// to raise.
///
/// Set it per test file in `setUpAll`, never globally, so only the goldens
/// that need the tolerance get it:
///
/// ```dart
/// late GoldenFileComparator previous;
///
/// setUpAll(() {
///   previous = goldenFileComparator;
///   goldenFileComparator = TolerantGoldenComparator(
///     (previous as LocalFileComparator).basedir.resolve('my_golden_test.dart'),
///     maxDiffPercent: 0.005,
///   );
/// });
///
/// tearDownAll(() => goldenFileComparator = previous);
/// ```
///
/// A different image size always fails, however small the tolerance (the
/// pixel comparison reports it as a full difference).
class TolerantGoldenComparator extends LocalFileComparator {
  /// Golden keys are interpreted relative to the directory of [testFile], as
  /// in [LocalFileComparator]. [maxDiffPercent] must be a fraction in
  /// 0..0.01.
  TolerantGoldenComparator(super.testFile, {required this.maxDiffPercent})
    : assert(
        maxDiffPercent >= 0 && maxDiffPercent <= 0.01,
        'maxDiffPercent is a fraction (0.005 is 0.5%) and never above 0.01',
      );

  /// The largest share of differing pixels that still passes, as a fraction.
  final double maxDiffPercent;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );

    if (result.passed || result.diffPercent <= maxDiffPercent) {
      result.dispose();
      return true;
    }

    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}
