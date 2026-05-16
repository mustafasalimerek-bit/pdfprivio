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
