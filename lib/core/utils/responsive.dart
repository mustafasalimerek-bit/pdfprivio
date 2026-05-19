import 'package:flutter/material.dart';

/// Breakpoints + a max-width body wrapper for iPad Stage Manager and
/// Split View. Phones stay full-width; once the window crosses
/// [iPadCompact] we centre-constrain so a 12.9" Pro doesn't stretch
/// forms to absurd line lengths.
class Breakpoints {
  static const double compact = 600; // small Split View pane width
  static const double iPadCompact = 700; // big-enough-for-grid
  static const double iPadRegular = 1000; // 3-col home grid threshold

  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).width < compact;

  static bool isWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= iPadCompact;

  static bool isExtraWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= iPadRegular;

  /// User-facing name for the device the app is running on. Lets copy
  /// like "Stays on your iPhone" / "Stays on your iPad" adapt to the
  /// actual hardware instead of falling back to the generic "device".
  ///
  /// Uses [View.of] + [FlutterView.display] (the physical screen) rather
  /// than [MediaQuery.sizeOf] (the window). In iPad Split View / Slide
  /// Over the window can shrink to phone-sized widths, but the user is
  /// still on an iPad — saying "Stays on your iPhone" in that pane
  /// would read wrong. Threshold mirrors UIKit's regular horizontal
  /// size class: every iPad has shortestSide ≥ 600 in points, every
  /// iPhone is below.
  static String deviceNoun(BuildContext context) {
    final display = View.of(context).display;
    final shortest = display.size.shortestSide / display.devicePixelRatio;
    return shortest >= 600 ? 'iPad' : 'iPhone';
  }
}

/// Centred max-width body. Drop-in replacement for plain `body:` —
/// keeps phone layouts identical, caps content at 720 dp on wide
/// windows so settings, audit log, batch picker, etc. stay readable.
class MaxWidthBody extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const MaxWidthBody({
    super.key,
    required this.child,
    this.maxWidth = 720,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
