// The reader has no blanket `SafeArea` any more: each chrome surface
// consumes the inset it sits against, so the bottom bar can be the spec's
// `58 + home-indicator inset` rather than finding the inset already eaten by
// an ancestor (docs/specs/2026-08-09-song-presentation.md, section 6).
//
// The iOS Simulator is not available on this machine (Command Line Tools
// only, no `simctl`) and there is no Android emulator image, so these tests
// are the whole of the evidence for that behaviour. They are deliberately
// exact rather than approximate.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_chrome_metrics.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_state.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_bottom_bar.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_top_bar.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

/// The iPhone home-indicator inset, in logical pixels.
const double _homeIndicatorInset = 34.0;

/// A landscape notch-shaped side inset, distinguishable on the left and
/// right so a widget that swaps them (or drops one) shows up as a geometry
/// failure rather than a coincidental pass.
const EdgeInsets _landscapeNotch = EdgeInsets.only(left: 40, right: 60);

const Size _phone = Size(375, 812);
const Size _phoneLandscape = Size(812, 375);
const Size _tablet = Size(834, 1194);

Widget _wrap(
  Widget child, {
  required Size size,
  EdgeInsets viewPadding = EdgeInsets.zero,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: size, viewPadding: viewPadding),
      child: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: size.width, child: child),
        ),
      ),
    ),
  );
}

Widget _bottomBar() => const SongReaderBottomBar(currentTitle: 'Song');

Widget _planScopedBottomBar() => const SongReaderBottomBar(
  currentTitle: 'Song',
  isPlanScoped: true,
  previousTitle: 'Before',
  nextTitle: 'After',
  onPreviousTap: _noop,
  onNextTap: _noop,
);

Widget _topBar() => SongReaderTopBar(
  title: 'Song',
  onBack: () {},
  hasRecoverableWarnings: false,
  onShowWarnings: () {},
  showOverflowMenu: false,
  viewMode: SongReaderViewMode.chordsAndLyrics,
  canEditSongs: false,
  isDarkActive: false,
);

void _noop() {}

void main() {
  group('bottom bar consumes the home-indicator inset', () {
    testWidgets('phone: total height is the bar height plus the inset', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          _bottomBar(),
          size: _phone,
          viewPadding: const EdgeInsets.only(bottom: _homeIndicatorInset),
        ),
      );

      final barHeight = SongReaderChromeMetrics.resolve(
        _phone.width,
      ).bottomBarHeight;
      expect(barHeight, 58.0);
      expect(
        tester.getSize(find.byType(SongReaderBottomBar)).height,
        barHeight + _homeIndicatorInset,
      );
    });

    testWidgets('tablet: total height is the bar height plus the inset', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          _bottomBar(),
          size: _tablet,
          viewPadding: const EdgeInsets.only(bottom: _homeIndicatorInset),
        ),
      );

      final barHeight = SongReaderChromeMetrics.resolve(
        _tablet.width,
      ).bottomBarHeight;
      expect(barHeight, 64.0);
      expect(
        tester.getSize(find.byType(SongReaderBottomBar)).height,
        barHeight + _homeIndicatorInset,
      );
    });

    testWidgets('with no inset the bar is exactly the bar height', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(_bottomBar(), size: _phone));
      expect(tester.getSize(find.byType(SongReaderBottomBar)).height, 58.0);

      await tester.pumpWidget(_wrap(_bottomBar(), size: _tablet));
      expect(tester.getSize(find.byType(SongReaderBottomBar)).height, 64.0);
    });

    testWidgets('the inset is empty space below the content, not padding '
        'that pushes the label down', (tester) async {
      await tester.pumpWidget(_wrap(_bottomBar(), size: _phone));
      final withoutInset = tester.getRect(find.text('Song'));

      await tester.pumpWidget(
        _wrap(
          _bottomBar(),
          size: _phone,
          viewPadding: const EdgeInsets.only(bottom: _homeIndicatorInset),
        ),
      );
      final withInset = tester.getRect(find.text('Song'));

      // The bar grows downwards into the inset; the content stays put.
      expect(withInset.top, withoutInset.top);

      final barBottom = tester.getRect(find.byType(SongReaderBottomBar)).bottom;
      expect(
        withInset.bottom,
        lessThanOrEqualTo(barBottom - _homeIndicatorInset),
        reason: 'content must not render inside the home-indicator inset',
      );
    });

    testWidgets('reads viewPadding rather than padding', (tester) async {
      // The bar must size off `viewPadding`, not `padding`. This pins that
      // choice: `padding` is left at its default zero while `viewPadding`
      // carries the home-indicator inset, so a bar reading `paddingOf` would
      // come out at the bare 58 instead of 92.
      //
      // Deliberately no `Scaffold` here. A `Scaffold` removes the bottom
      // padding from its body once a keyboard covers it, which is the right
      // behaviour — the home indicator is not visible under a keyboard — but
      // it would mask which MediaQuery field this widget actually reads.
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: _phone,
              viewPadding: EdgeInsets.only(bottom: _homeIndicatorInset),
              viewInsets: EdgeInsets.only(bottom: 300),
            ),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 375,
                child: SongReaderBottomBar(currentTitle: 'Song'),
              ),
            ),
          ),
        ),
      );

      expect(
        tester.getSize(find.byType(SongReaderBottomBar)).height,
        58.0 + _homeIndicatorInset,
      );
    });
  });

  group('top bar consumes the top inset', () {
    testWidgets('grows by the top inset', (tester) async {
      await tester.pumpWidget(_wrap(_topBar(), size: _phone));
      final withoutInset = tester.getSize(find.byType(SongReaderTopBar)).height;

      await tester.pumpWidget(
        _wrap(
          _topBar(),
          size: _phone,
          viewPadding: const EdgeInsets.only(top: 44),
        ),
      );

      expect(
        tester.getSize(find.byType(SongReaderTopBar)).height,
        withoutInset + 44,
      );
    });

    testWidgets('is exactly the bar height with no inset', (tester) async {
      await tester.pumpWidget(_wrap(_topBar(), size: _tablet));

      expect(
        tester.getSize(find.byType(SongReaderTopBar)).height,
        SongReaderChromeMetrics.resolve(_tablet.width).topBarHeight,
      );
    });
  });

  group('landscape side insets', () {
    // A landscape notch lands on the left or right edge, not top/bottom, so
    // these pin the left/right half of the same per-surface-inset story the
    // groups above cover for top/bottom: the top bar's back button and the
    // bottom bar's chevrons must not render underneath it.
    testWidgets('top bar: the back button clears the left inset', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(_topBar(), size: _phoneLandscape, viewPadding: _landscapeNotch),
      );

      final backButton = tester.getRect(
        find.byTooltip(AppStrings.songReaderBackAction),
      );

      expect(backButton.left, greaterThanOrEqualTo(_landscapeNotch.left));
    });

    testWidgets(
      'top bar: the back button shifts right by exactly the left inset',
      (tester) async {
        await tester.pumpWidget(_wrap(_topBar(), size: _phoneLandscape));
        final withoutInset = tester
            .getRect(find.byTooltip(AppStrings.songReaderBackAction))
            .left;

        await tester.pumpWidget(
          _wrap(_topBar(), size: _phoneLandscape, viewPadding: _landscapeNotch),
        );
        final withInset = tester
            .getRect(find.byTooltip(AppStrings.songReaderBackAction))
            .left;

        expect(withInset - withoutInset, _landscapeNotch.left);
      },
    );

    testWidgets('bottom bar: the previous chevron clears the left inset', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          _planScopedBottomBar(),
          size: _phoneLandscape,
          viewPadding: _landscapeNotch,
        ),
      );

      final previous = tester.getRect(
        find.byKey(SongReaderBottomBar.previousSegmentKey),
      );

      expect(previous.left, greaterThanOrEqualTo(_landscapeNotch.left));
    });

    testWidgets('bottom bar: the next chevron clears the right inset', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          _planScopedBottomBar(),
          size: _phoneLandscape,
          viewPadding: _landscapeNotch,
        ),
      );

      final next = tester.getRect(
        find.byKey(SongReaderBottomBar.nextSegmentKey),
      );

      expect(
        next.right,
        lessThanOrEqualTo(_phoneLandscape.width - _landscapeNotch.right),
      );
    });

    testWidgets(
      'bottom bar: the chevrons shift inward by exactly the side insets',
      (tester) async {
        await tester.pumpWidget(
          _wrap(_planScopedBottomBar(), size: _phoneLandscape),
        );
        final previousWithoutInset = tester
            .getRect(find.byKey(SongReaderBottomBar.previousSegmentKey))
            .left;
        final nextWithoutInset = tester
            .getRect(find.byKey(SongReaderBottomBar.nextSegmentKey))
            .right;

        await tester.pumpWidget(
          _wrap(
            _planScopedBottomBar(),
            size: _phoneLandscape,
            viewPadding: _landscapeNotch,
          ),
        );
        final previousWithInset = tester
            .getRect(find.byKey(SongReaderBottomBar.previousSegmentKey))
            .left;
        final nextWithInset = tester
            .getRect(find.byKey(SongReaderBottomBar.nextSegmentKey))
            .right;

        expect(previousWithInset - previousWithoutInset, _landscapeNotch.left);
        expect(nextWithoutInset - nextWithInset, _landscapeNotch.right);
      },
    );
  });
}
