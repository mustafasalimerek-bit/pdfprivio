/// Source-of-truth constants for the app. As of v1.0 most of these are
/// not yet referenced (Settings hardcodes its own URLs, PurchaseService
/// owns its own IAP IDs); they live here so the next refactor pass can
/// switch call sites to AppConstants without first having to chase down
/// the canonical values. **Keep these in sync with reality.**
class AppConstants {
  AppConstants._();

  static const String appName = 'Privio';
  static const String appTagline = 'Offline PDF tools. No subscription.';

  // Legal URLs — verified live (GitHub Pages hosted from
  // erekstudio-legal repo, served under the /pdfprivio/ path).
  static const String privacyPolicyUrl =
      'https://mustafasalimerek-bit.github.io/pdfprivio/privacy/';
  static const String termsOfServiceUrl =
      'https://mustafasalimerek-bit.github.io/pdfprivio/terms/';

  // Apple App Store — actual live listing.
  static const String appStoreId = '6769985472';
  static const String appStoreUrl =
      'https://apps.apple.com/app/id6769985472';

  // Google Play Store (Android target — not yet shipped).
  static const String playStorePackage = 'com.erekstudio.pdfprivio';
  static const String playConsoleAppId = '4976288492451327073';

  // IAP product IDs — MUST match the App Store Connect product
  // identifiers exactly. The previous values here (`pdfprivio_pro_*`)
  // were placeholders that never matched ASC; corrected to the live IDs
  // used by PurchaseService.
  static const String iapLifetimeProductId =
      'com.erekstudio.pdfprivio.pro_lifetime';
  static const String iapMonthlyProductId =
      'com.erekstudio.pdfprivio.pro_monthly';
  static const String iapYearlyProductId =
      'com.erekstudio.pdfprivio.pro_yearly';
}
