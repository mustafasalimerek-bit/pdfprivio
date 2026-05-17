/// Shared layout grammar for top-level navigation screens
/// (Recent / Tools / Settings).
///
/// Calibrated for iPhone 17 Pro Max (~956pt logical height). Title
/// font, paddings, and icon dims were bumped from the v1.0 tokens so
/// the screens don't feel tight on the large hardware while still
/// reading well on SE-class devices.
///
/// Lower-level tool screens (NDA, Sign, OCR, etc.) keep their own
/// chrome (`tool_chrome.dart`) — this file is intentionally scoped
/// to the three top-level surfaces.
class Layout {
  Layout._();

  // Screen-level padding
  static const double screenHorizontalPadding = 18;
  static const double screenTopPadding = 8;
  static const double screenBottomPadding = 14;

  // Title bar (large editorial title, no navigation chrome)
  static const double titleFontSize = 28;
  static const double titleToContentSpacing = 14;

  // Section spacing
  static const double sectionSpacing = 22;
  static const double sectionHeaderFontSize = 11;
  static const double sectionHeaderLetterSpacing = 0.6;
  static const double sectionHeaderToCardSpacing = 8;

  // Card
  static const double cardCornerRadius = 14;
  static const double cardInternalPadding = 14;
  static const double cardDividerInset = 14;

  // Hero / promo card
  static const double heroCornerRadius = 18;
  static const double heroPadding = 18;

  // Pill / badge
  static const double pillHorizontalPadding = 11;
  static const double pillVerticalPadding = 5;

  // Primary CTA button — 14pt rounded rectangle (NOT a pill).
  static const double primaryButtonCornerRadius = 14;
  static const double primaryButtonHorizontalPadding = 18;
  static const double primaryButtonVerticalPadding = 16;

  // Icon containers inside card rows
  static const double iconContainerSize = 36;
  static const double iconContainerCornerRadius = 10;
  static const double iconSize = 19;

  // Empty state (e.g. Recent before any files)
  static const double emptyStateIllustrationSize = 110;
  static const double emptyStateContentMaxWidth = 320;
}
