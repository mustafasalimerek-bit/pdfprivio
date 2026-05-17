import 'package:flutter/material.dart';

import '../core/theme/colors.dart';
import '../core/theme/layout.dart';

/// Layout chrome for the three top-level nav surfaces.
///
/// Two flavours:
///   * [ScreenContainer]            — list-based screens (Settings,
///     Tools, populated Recent). Title pinned to the top, body
///     scrolls.
///   * [CenteredScreenContainer]    — empty / hero states (boş
///     Recent, error states). A top bar stays pinned while the hero
///     cluster sits at the optical center (~%42-45 from the top, not
///     pure 50%, per Apple HIG visual-weight guidance).
///
/// Both apply the shared horizontal padding, top padding, and
/// brand-cream background — so the three screens read as one
/// family.

class ScreenContainer extends StatelessWidget {
  final String title;
  final Widget? titleTrailing;
  final Widget child;

  const ScreenContainer({
    super.key,
    required this.title,
    required this.child,
    this.titleTrailing,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Layout.screenHorizontalPadding,
              Layout.screenTopPadding,
              Layout.screenHorizontalPadding,
              Layout.titleToContentSpacing,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: Layout.titleFontSize,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.4,
                      height: 1.1,
                    ),
                  ),
                ),
                ?titleTrailing,
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                Layout.screenHorizontalPadding,
                0,
                Layout.screenHorizontalPadding,
                Layout.screenBottomPadding,
              ),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

/// Centers a hero cluster between two flexible spacers. The bottom
/// minLength is intentionally larger than the top so the cluster
/// lands a bit above geometric middle — that's the optical center,
/// not 50%.
class CenteredScreenContainer extends StatelessWidget {
  final Widget topBar;
  final Widget child;

  const CenteredScreenContainer({
    super.key,
    required this.topBar,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Layout.screenHorizontalPadding,
              Layout.screenTopPadding,
              Layout.screenHorizontalPadding,
              0,
            ),
            child: SizedBox(
              width: double.infinity,
              child: topBar,
            ),
          ),
          const Spacer(flex: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: Layout.emptyStateContentMaxWidth,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Layout.screenHorizontalPadding,
              ),
              child: child,
            ),
          ),
          const Spacer(flex: 5),
        ],
      ),
    );
  }
}
