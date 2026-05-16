class AppConstants {
  AppConstants._();

  static const String appName = 'PDFPrivio';
  static const String appTagline = 'Offline PDF tools. No subscription.';

  // Legal URLs (will live under erekstudio-legal GitHub Pages once created)
  static const String privacyPolicyUrl =
      'https://mustafasalimerek-bit.github.io/erekstudio-legal/pdfprivio/privacy_en.html';
  static const String termsOfServiceUrl =
      'https://mustafasalimerek-bit.github.io/erekstudio-legal/pdfprivio/terms_en.html';

  // Apple App Store ID (App Store Connect)
  static const String appStoreId = '6769270643';
  // Google Play Store
  static const String playStorePackage = 'com.erekstudio.pdfprivio';
  static const String playConsoleAppId = '4976288492451327073';

  // IAP product IDs — same across stores so client code does not branch
  static const String iapLifetimeProductId = 'pdfprivio_pro_lifetime';
  static const String iapMonthlyProductId = 'pdfprivio_pro_monthly';
  static const String iapYearlyProductId = 'pdfprivio_pro_yearly';
}
